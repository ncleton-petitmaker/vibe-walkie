import SwiftUI
import RemoteCore

@MainActor
protocol DictationTransport: AnyObject {
    func send<T: Encodable>(type: RemoteMessageType, payload: T) async throws -> RemoteEnvelope
}

extension HostConnectionClient: DictationTransport {}

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
    private var engine: (any SpeechEngine)?
    private var dictationLocaleIdentifier: String
    private var dictationID = UUID()
    private var targetToken: TargetToken?
    private var captureTask: Task<Void, Never>?
    private var partialsTask: Task<Void, Never>?
    private var resetTask: Task<Void, Never>?

    private static let cancelThreshold: CGFloat = -70

    init(
        client: any DictationTransport,
        engine: (any SpeechEngine)? = nil,
        localeIdentifier: String = DictationLanguage.deviceLocaleIdentifier
    ) {
        self.client = client
        self.engine = engine
        dictationLocaleIdentifier = localeIdentifier
    }

    var isRecording: Bool {
        phase == .recording || phase == .armedForCancel
    }

#if DEBUG
    func configureMarketingRecording() {
        partialText = AppL10n.text("ios.control.the.pointer.keyboard.and.dictation.from.this.iphone.no.2d4c813")
        level = 0.72
        phase = .recording
    }

    func configureMarketingDelivered() {
        partialText = ""
        level = 0
        phase = .delivered(AppL10n.format("ios.written.in.value.5e6ee32", "Notes"))
    }
#endif

    func prepareEngine(localeIdentifier: String) async {
        guard #available(iOS 26.0, *) else {
            phase = .failed(AppL10n.text("ios.on.device.transcription.is.unavailable.on.this.device.8f2dc9f"))
            return
        }
        if isRecording || phase == .finalizing || phase == .sending { return }
        await engine?.cancel()
        let engine = AppleSpeechAnalyzerEngine(localeIdentifier: localeIdentifier)
        dictationLocaleIdentifier = localeIdentifier
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
                await fail(AppL10n.remoteError(error.code))
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
            cancelDictation(reason: AppL10n.text("ios.close.711e5f2"))
            return
        }
        captureTask?.cancel()
        captureTask = nil
        finishAndSend()
    }

    func pressCancelled() {
        guard isRecording else { return }
        cancelDictation(reason: AppL10n.text("ios.close.711e5f2"))
    }

    private func requestTarget(for id: UUID) async throws -> TargetToken {
        let response = try await client.send(
            type: .recordingStarted,
            payload: RecordingStartedPayload(locale: dictationLocaleIdentifier, dictationID: id)
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
                await fail(AppL10n.text("ios.no.speech.detected.61bb54a"))
                return
            }
            guard let token else {
                await fail(AppL10n.text("ios.no.active.text.field.on.the.mac.880e867"))
                return
            }

            phase = .sending
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
                    HapticFeedback.shared.delivered()
                    phase = .delivered(AppL10n.format("ios.written.in.value.5e6ee32", insertion.applicationName))
                } else {
                    phase = .sentUnverified(AppL10n.format("ios.sent.to.value.check.the.field.8ae889d", insertion.applicationName))
                }
                scheduleReset()
            } catch let error as RemoteErrorPayload {
                await fail(AppL10n.remoteError(error.code))
            } catch {
                await fail(AppL10n.text("ios.delivery.not.confirmed.check.the.active.field.e0e5a15"))
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

}
