import XCTest
import RemoteCore
@testable import VibeWalkieiOS

@MainActor
final class DictationControllerTests: XCTestCase {
    func testExpandedTrackpadSpeedMigrationRaisesLegacyMaximumsOnlyOnce() {
        let suiteName = "TrackpadSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(3.0, forKey: "trackpadSensitivity")
        defaults.set(2.0, forKey: "scrollSensitivity")

        TrackpadSettings.migrateExpandedSpeedRange(defaults: defaults)

        XCTAssertEqual(defaults.double(forKey: "trackpadSensitivity"), 5.0)
        XCTAssertEqual(defaults.double(forKey: "scrollSensitivity"), 4.0)

        defaults.set(5.7, forKey: "trackpadSensitivity")
        defaults.set(4.6, forKey: "scrollSensitivity")
        TrackpadSettings.migrateExpandedSpeedRange(defaults: defaults)
        XCTAssertEqual(defaults.double(forKey: "trackpadSensitivity"), 5.7)
        XCTAssertEqual(defaults.double(forKey: "scrollSensitivity"), 4.6)
    }

    private var transport: FakeDictationTransport!
    private var engine: FakeSpeechEngine!
    private var controller: DictationController!

    override func setUp() async throws {
        try await super.setUp()
        transport = FakeDictationTransport()
        engine = FakeSpeechEngine(finalText: "Bonjour depuis le test")
        controller = DictationController(client: transport, engine: engine)
    }

    override func tearDown() async throws {
        controller = nil
        engine = nil
        transport = nil
        try await super.tearDown()
    }

    func testSuccessfulDictationSendsTextOnceAndWaitsForAcknowledgement() async throws {
        transport.suspendInsertReply = true
        controller.pressBegan()
        try await waitUntil { self.engine.didStart }
        controller.pressEnded()
        try await waitUntil { self.transport.insertPayloads.count == 1 }

        XCTAssertEqual(controller.phase, .sending)
        XCTAssertEqual(transport.insertPayloads.first?.text, "Bonjour depuis le test")

        transport.completeInsertReply()
        try await waitUntil {
            if case .delivered = self.controller.phase { return true }
            return false
        }
        XCTAssertEqual(transport.insertPayloads.count, 1)
    }

    func testSlideCancellationNeverInsertsText() async throws {
        controller.pressBegan()
        try await waitUntil { self.engine.didStart }
        controller.pressMoved(CGPoint(x: -100, y: 0))
        controller.pressEnded()

        try await waitUntil { self.engine.didCancel }
        XCTAssertTrue(transport.insertPayloads.isEmpty)
        XCTAssertEqual(transport.cancelPayloads.count, 1)
    }

    func testSystemCancellationNeverInsertsText() async throws {
        controller.pressBegan()
        try await waitUntil { self.engine.didStart }
        controller.pressCancelled()

        try await waitUntil { self.engine.didCancel }
        XCTAssertTrue(transport.insertPayloads.isEmpty)
        XCTAssertEqual(transport.cancelPayloads.count, 1)
    }

    func testEmptyFinalTextIsNotSent() async throws {
        engine.finalText = "   \n"
        controller.pressBegan()
        try await waitUntil { self.engine.didStart }
        controller.pressEnded()

        try await waitUntil { self.transport.cancelPayloads.count == 1 }
        XCTAssertTrue(transport.insertPayloads.isEmpty)
    }

    func testSecureTargetFailurePreventsMicrophoneStart() async throws {
        transport.recordingError = RemoteErrorPayload(code: .secureField)
        controller.pressBegan()

        try await waitUntil {
            if case .failed = self.controller.phase { return true }
            return false
        }
        XCTAssertFalse(engine.didStart)
        XCTAssertTrue(transport.insertPayloads.isEmpty)
    }

    func testAcknowledgementTimeoutIsReportedWithoutResending() async throws {
        transport.insertError = RemoteErrorPayload(code: .internalFailure, detail: "timeout")
        controller.pressBegan()
        try await waitUntil { self.engine.didStart }
        controller.pressEnded()

        try await waitUntil {
            if case .failed = self.controller.phase { return true }
            return false
        }
        XCTAssertEqual(transport.insertPayloads.count, 1)
    }

    func testUnverifiedInsertionIsNeverReportedAsWritten() async throws {
        transport.insertionIsVerified = false
        controller.pressBegan()
        try await waitUntil { self.engine.didStart }
        controller.pressEnded()

        try await waitUntil {
            if case .sentUnverified = self.controller.phase { return true }
            return false
        }
        XCTAssertEqual(transport.insertPayloads.count, 1)
    }

    func testSelectedDictationLocaleIsSentToMac() async throws {
        controller = DictationController(
            client: transport,
            engine: engine,
            localeIdentifier: "en-US"
        )

        controller.pressBegan()
        try await waitUntil { self.engine.didStart }

        XCTAssertEqual(transport.recordingPayloads.first?.locale, "en-US")
        controller.pressCancelled()
    }

    func testUnsupportedSystemLanguageFallsBackToFrench() {
        let locale = DictationLanguage.deviceLocaleIdentifier
        XCTAssertFalse(locale.isEmpty)
        XCTAssertTrue(locale.hasPrefix("fr") || locale.hasPrefix("en"))
    }

    func testAnalyzerPromotesLastHypothesisAfterEndOfInput() {
        let (stream, continuation) = AsyncStream<SpeechUpdate>.makeStream()
        _ = stream
        let state = AnalyzerRecognitionState(continuation: continuation)

        state.receive(text: "Bonjour", isFinal: false)
        XCTAssertEqual(state.finalUpdate.finalizedText, "")
        state.finish()

        XCTAssertEqual(state.finalUpdate.text, "Bonjour")
        XCTAssertEqual(state.finalUpdate.finalizedText, "Bonjour")
    }

    func testAnalyzerKeepsFinalPrefixAndLastHypothesis() {
        let (stream, continuation) = AsyncStream<SpeechUpdate>.makeStream()
        _ = stream
        let state = AnalyzerRecognitionState(continuation: continuation)

        state.receive(text: "Bonjour", isFinal: true)
        state.receive(text: "tout le monde", isFinal: false)
        state.finish()

        XCTAssertEqual(state.finalUpdate.finalizedText, "Bonjour tout le monde")
    }

    func testModernTranscriberIsPreferredWhenAvailable() {
        XCTAssertEqual(
            AppleSpeechTranscriberKind.candidates(speechTranscriberIsAvailable: true),
            [.speechTranscriber, .dictationTranscriber]
        )
    }

    func testDictationTranscriberRemainsFallbackOnOlderHardware() {
        XCTAssertEqual(
            AppleSpeechTranscriberKind.candidates(speechTranscriberIsAvailable: false),
            [.dictationTranscriber]
        )
    }

    func testLegacyTranscriptCleanupDeletesExistingData() throws {
        let suiteName = "LegacyTranscriptCleanupTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "com.nicolascleton.viberemote.historyEnabled")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = directory.appendingPathComponent("transcripts.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("ancienne dictée".utf8).write(to: fileURL)

        LegacyTranscriptCleanup.run(defaults: defaults, fileURL: fileURL)

        XCTAssertNil(defaults.object(forKey: "com.nicolascleton.viberemote.historyEnabled"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            guard clock.now < deadline else {
                XCTFail("Condition non satisfaite avant le délai")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

@MainActor
private final class FakeDictationTransport: DictationTransport {
    var recordingPayloads: [RecordingStartedPayload] = []
    var insertPayloads: [InsertTextPayload] = []
    var cancelPayloads: [CancelPayload] = []
    var recordingError: Error?
    var insertError: Error?
    var suspendInsertReply = false
    var insertionIsVerified = true
    private var insertContinuation: CheckedContinuation<RemoteEnvelope, Error>?

    func send<T: Encodable>(type: RemoteMessageType, payload: T) async throws -> RemoteEnvelope {
        switch type {
        case .recordingStarted:
            if let recordingError { throw recordingError }
            let value = try decode(payload, as: RecordingStartedPayload.self)
            recordingPayloads.append(value)
            return try response(
                type: .acknowledgement,
                payload: AcknowledgementPayload(
                    ok: true,
                    targetToken: TargetToken(
                        token: "target-\(recordingPayloads.count)",
                        applicationName: "Notes",
                        bundleIdentifier: "com.apple.Notes",
                        windowTitle: "Note",
                        expiresAt: Date().addingTimeInterval(120)
                    )
                )
            )

        case .insertText:
            let value = try decode(payload, as: InsertTextPayload.self)
            insertPayloads.append(value)
            if let insertError { throw insertError }
            if suspendInsertReply {
                return try await withCheckedThrowingContinuation { insertContinuation = $0 }
            }
            return try successfulInsertResponse()

        case .cancel:
            cancelPayloads.append(try decode(payload, as: CancelPayload.self))
            return try response(type: .acknowledgement, payload: AcknowledgementPayload(ok: true))

        default:
            throw RemoteErrorPayload(code: .protocolMismatch, detail: "message inattendu")
        }
    }

    func completeInsertReply() {
        guard let insertContinuation else { return }
        self.insertContinuation = nil
        do {
            insertContinuation.resume(returning: try successfulInsertResponse())
        } catch {
            insertContinuation.resume(throwing: error)
        }
    }

    private func successfulInsertResponse() throws -> RemoteEnvelope {
        try response(
            type: .acknowledgement,
            payload: AcknowledgementPayload(
                ok: true,
                insertion: InsertionResult(
                    method: .axSelectedText,
                    verified: insertionIsVerified,
                    pasteboardRestored: nil,
                    applicationName: "Notes"
                )
            )
        )
    }

    private func response<T: Encodable>(type: RemoteMessageType, payload: T) throws -> RemoteEnvelope {
        try RemoteEnvelope.make(type: type, sessionID: "tests", sequence: 1, payload: payload)
    }

    private func decode<T: Decodable, Value: Encodable>(_ value: Value, as type: T.Type) throws -> T {
        let data = try RemoteCoding.encoder.encode(value)
        return try RemoteCoding.decoder.decode(type, from: data)
    }
}

@MainActor
private final class FakeSpeechEngine: SpeechEngine {
    var finalText: String
    private(set) var didStart = false
    private(set) var didCancel = false
    var isAvailable = true

    init(finalText: String) {
        self.finalText = finalText
    }

    func prepare() async throws {}

    func start() async throws -> AsyncStream<SpeechUpdate> {
        didStart = true
        return AsyncStream { continuation in
            continuation.yield(SpeechUpdate(text: finalText, finalizedText: finalText))
            continuation.finish()
        }
    }

    func finish() async throws -> SpeechUpdate {
        SpeechUpdate(text: finalText, finalizedText: finalText)
    }

    func cancel() async {
        didCancel = true
    }
}
