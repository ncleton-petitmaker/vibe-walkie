import SwiftUI
import RemoteCore

@MainActor
protocol DictationTransport: AnyObject {
    func send<T: Encodable>(type: RemoteMessageType, payload: T) async throws -> RemoteEnvelope
}

extension MacConnectionClient: DictationTransport {}

/// Orchestration d'une dictée transactionnelle : la cible est capturée avant
/// le micro et le texte n'est annoncé livré qu'après l'accusé du Mac.
@MainActor
final class DictationController: ObservableObject {

    enum Phase: Equatable {
        case idle
        case recording
        case armedForCancel
        case finalizing
        case sending
        case delivered(String)
        case sentUnverified(String)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var partialText = ""
    @Published private(set) var level: CGFloat = 0

    private let client: any DictationTransport
    private let history: TranscriptHistoryStore
    private var engine: (any SpeechEngine)?
    private var dictationID = UUID()
    private var targetToken: TargetToken?
    private var captureTask: Task<Void, Never>?
    private var partialsTask: Task<Void, Never>?
    private var resetTask: Task<Void, Never>?

    private static let cancelThreshold: CGFloat = -70

    init(
        client: any DictationTransport,
        history: TranscriptHistoryStore,
        engine: (any SpeechEngine)? = nil
    ) {
        self.client = client
        self.history = history
        self.engine = engine
    }

    var isRecording: Bool {
        phase == .recording || phase == .armedForCancel
    }

#if DEBUG
    func configureMarketingRecording() {
        partialText = "Prépare le compte-rendu et partage-le avec l’équipe."
        level = 0.72
        phase = .recording
    }

    func configureMarketingDelivered() {
        partialText = ""
        level = 0
        phase = .delivered("Écrit dans Notes")
    }
#endif

    func prepareEngine() async {
        guard #available(iOS 26.0, *) else {
            phase = .failed("Vibe Remote nécessite iOS 26.")
            return
        }
        let engine = AppleSpeechAnalyzerEngine()
        do {
            try await engine.prepare()
            self.engine = engine
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func pressBegan() {
        guard !isRecording, phase != .finalizing, phase != .sending else { return }
        resetTask?.cancel()
        captureTask?.cancel()
        HapticFeedback.shared.prepare()
        partialText = ""
        dictationID = UUID()
        targetToken = nil
        phase = .recording

        let currentID = dictationID
        captureTask = Task { [weak self] in
            guard let self else { return }
            do {
                let token = try await requestTarget(for: currentID)
                guard !Task.isCancelled, isRecording, dictationID == currentID else {
                    await cancelRemoteTarget(for: currentID)
                    return
                }
                targetToken = token
                try await startCapture()
            } catch is CancellationError {
                await cancelRemoteTarget(for: currentID)
            } catch let error as RemoteErrorPayload {
                await fail(error.message)
            } catch {
                await fail(error.localizedDescription)
            }
        }
    }

    func pressMoved(_ translation: CGPoint) {
        guard isRecording else { return }
        let armed = translation.x < Self.cancelThreshold
        if armed && phase != .armedForCancel {
            phase = .armedForCancel
            HapticFeedback.shared.armedForCancel()
        } else if !armed && phase == .armedForCancel {
            phase = .recording
            HapticFeedback.shared.tick()
        }
    }

    func pressEnded() {
        guard isRecording else { return }
        if phase == .armedForCancel {
            cancelDictation(reason: "Annulé")
            return
        }
        captureTask?.cancel()
        captureTask = nil
        finishAndSend()
    }

    func pressCancelled() {
        guard isRecording else { return }
        cancelDictation(reason: "Dictée interrompue")
    }

    private func requestTarget(for id: UUID) async throws -> TargetToken {
        let response = try await client.send(
            type: .recordingStarted,
            payload: RecordingStartedPayload(locale: VibeRemoteInfo.dictationLocale, dictationID: id)
        )
        let ack = try response.decodePayload(AcknowledgementPayload.self)
        guard let token = ack.targetToken else {
            throw RemoteErrorPayload(code: .noFocusedTarget)
        }
        return token
    }

    private func startCapture() async throws {
        guard let engine else { throw SpeechEngineError.notPrepared }
        let stream = try await engine.start()
        guard !Task.isCancelled, isRecording else {
            await engine.cancel()
            throw CancellationError()
        }
        HapticFeedback.shared.recordingStarted()
        partialsTask = Task { [weak self] in
            for await update in stream {
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.partialText = update.text }
            }
        }
    }

    private func finishAndSend() {
        phase = .finalizing
        let currentID = dictationID
        let token = targetToken
        Task { [weak self] in
            guard let self else { return }
            guard let engine else {
                await fail(SpeechEngineError.notPrepared.localizedDescription)
                return
            }
            let update: SpeechUpdate
            do {
                update = try await engine.finish()
            } catch {
                partialsTask?.cancel()
                partialsTask = nil
                await cancelRemoteTarget(for: currentID)
                await fail(error.localizedDescription)
                return
            }
            partialsTask?.cancel()
            partialsTask = nil

            let finalText = update.finalizedText.trimmingCharacters(in: .whitespacesAndNewlines)
            partialText = finalText
            guard !finalText.isEmpty else {
                await cancelRemoteTarget(for: currentID)
                await fail("Aucune parole détectée")
                return
            }
            guard let token else {
                history.record(finalText, delivery: .notSent, applicationName: nil)
                await fail("Aucun champ actif sur le Mac")
                return
            }

            phase = .sending
            let entry = history.record(finalText, delivery: .pending, applicationName: token.applicationName)
            do {
                let response = try await client.send(
                    type: .insertText,
                    payload: InsertTextPayload(targetToken: token.token, text: finalText, dictationID: currentID)
                )
                let ack = try response.decodePayload(AcknowledgementPayload.self)
                guard ack.ok, let insertion = ack.insertion else {
                    throw RemoteErrorPayload(code: .internalFailure, detail: "accusé incomplet")
                }
                if insertion.verified {
                    history.update(entry.id, delivery: .delivered, applicationName: insertion.applicationName)
                    HapticFeedback.shared.delivered()
                    phase = .delivered("Écrit dans \(insertion.applicationName)")
                } else {
                    history.update(entry.id, delivery: .unknown, applicationName: insertion.applicationName)
                    phase = .sentUnverified("Envoyé à \(insertion.applicationName) — vérifiez le champ")
                }
                scheduleReset()
            } catch let error as RemoteErrorPayload {
                let delivery: DeliveryState = error.detail == "timeout" ? .unknown : .notSent
                history.update(entry.id, delivery: delivery)
                await fail(error.message)
            } catch {
                history.update(entry.id, delivery: .unknown)
                await fail("Livraison non confirmée. Le texte reste dans l’historique.")
            }
        }
    }

    private func cancelDictation(reason: String) {
        captureTask?.cancel()
        captureTask = nil
        partialsTask?.cancel()
        partialsTask = nil
        partialText = ""
        let currentID = dictationID

        Task { [weak self] in
            guard let self else { return }
            await engine?.cancel()
            await cancelRemoteTarget(for: currentID)
            phase = .failed(reason)
            scheduleReset()
        }
    }

    private func cancelRemoteTarget(for id: UUID) async {
        guard targetToken != nil || dictationID == id else { return }
        _ = try? await client.send(type: .cancel, payload: CancelPayload(dictationID: id))
        targetToken = nil
    }

    private func fail(_ message: String) async {
        HapticFeedback.shared.failed()
        phase = .failed(message)
        scheduleReset()
    }

    private func scheduleReset() {
        resetTask?.cancel()
        resetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.phase = .idle
                self?.partialText = ""
                self?.targetToken = nil
            }
        }
    }

    /// Renvoie une transcription en capturant toujours une nouvelle cible.
    func resend(_ entry: TranscriptEntry) {
        Task { [weak self] in
            guard let self else { return }
            phase = .sending
            let resendID = UUID()
            do {
                let token = try await requestTarget(for: resendID)
                let response = try await client.send(
                    type: .insertText,
                    payload: InsertTextPayload(targetToken: token.token, text: entry.text, dictationID: resendID)
                )
                let ack = try response.decodePayload(AcknowledgementPayload.self)
                guard ack.ok, let insertion = ack.insertion else {
                    throw RemoteErrorPayload(code: .internalFailure, detail: "accusé incomplet")
                }
                if insertion.verified {
                    history.update(entry.id, delivery: .delivered, applicationName: insertion.applicationName)
                    HapticFeedback.shared.delivered()
                    phase = .delivered("Renvoyé dans \(insertion.applicationName)")
                } else {
                    history.update(entry.id, delivery: .unknown, applicationName: insertion.applicationName)
                    phase = .sentUnverified("Renvoyé à \(insertion.applicationName) — vérifiez le champ")
                }
                scheduleReset()
            } catch let error as RemoteErrorPayload {
                history.update(entry.id, delivery: .notSent)
                await fail(error.message)
            } catch {
                history.update(entry.id, delivery: .unknown)
                await fail("Livraison non confirmée")
            }
        }
    }
}
