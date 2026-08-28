import XCTest
import RemoteCore
@testable import VibeRemoteiOS

@MainActor
final class DictationControllerTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var history: TranscriptHistoryStore!
    private var transport: FakeDictationTransport!
    private var engine: FakeSpeechEngine!
    private var controller: DictationController!

    override func setUp() async throws {
        try await super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "DictationControllerTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        history = TranscriptHistoryStore(
            fileURL: directory.appendingPathComponent("history.json"),
            defaults: defaults
        )
        transport = FakeDictationTransport()
        engine = FakeSpeechEngine(finalText: "Bonjour depuis le test")
        controller = DictationController(client: transport, history: history, engine: engine)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
        controller = nil
        engine = nil
        transport = nil
        history = nil
        defaults = nil
        suiteName = nil
        directory = nil
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
        XCTAssertEqual(history.entries.first?.delivery, .pending)

        transport.completeInsertReply()
        try await waitUntil {
            if case .delivered = self.controller.phase { return true }
            return false
        }
        XCTAssertEqual(history.entries.first?.delivery, .delivered)
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
        XCTAssertTrue(history.entries.isEmpty)
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
        XCTAssertTrue(history.entries.isEmpty)
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

    func testAcknowledgementTimeoutKeepsTextAsUnknownForResend() async throws {
        transport.insertError = RemoteErrorPayload(code: .internalFailure, detail: "timeout")
        controller.pressBegan()
        try await waitUntil { self.engine.didStart }
        controller.pressEnded()

        try await waitUntil { self.history.entries.first?.delivery == .unknown }
        XCTAssertEqual(history.entries.first?.text, "Bonjour depuis le test")
        XCTAssertEqual(transport.insertPayloads.count, 1)
    }

    func testResendAlwaysCapturesANewTarget() async throws {
        let entry = history.record("Texte à renvoyer", delivery: .unknown, applicationName: nil)
        controller.resend(entry)

        try await waitUntil { self.history.entries.first?.delivery == .delivered }
        XCTAssertEqual(transport.recordingPayloads.count, 1)
        XCTAssertEqual(transport.insertPayloads.count, 1)
        XCTAssertEqual(transport.insertPayloads.first?.text, "Texte à renvoyer")
        XCTAssertEqual(transport.insertPayloads.first?.dictationID, transport.recordingPayloads.first?.dictationID)
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
                    verified: true,
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
