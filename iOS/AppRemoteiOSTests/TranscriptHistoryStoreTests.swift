import XCTest
import RemoteCore
@testable import VibeRemoteiOS

@MainActor
final class TranscriptHistoryStoreTests: XCTestCase {
    private var directory: URL!
    private var fileURL: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        suiteName = "VibeRemoteTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        fileURL = directory.appendingPathComponent("history.json")
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
        defaults = nil
        fileURL = nil
        directory = nil
        suiteName = nil
    }

    func testHistoryIsLimitedToFiftyEntries() {
        let store = makeStore()
        for index in 0..<60 {
            store.record("Texte \(index)", delivery: .delivered, applicationName: "Notes")
        }
        XCTAssertEqual(store.entries.count, 50)
        XCTAssertEqual(store.entries.first?.text, "Texte 59")
    }

    func testClearDeletesPersistedHistory() {
        let store = makeStore()
        store.record("Confidentiel", delivery: .delivered, applicationName: "Mail")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        store.clear()
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testDisablingHistoryClearsAndStopsPersistence() {
        let store = makeStore()
        store.record("Avant", delivery: .delivered, applicationName: nil)
        store.isEnabled = false
        _ = store.record("Après", delivery: .notSent, applicationName: nil)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testDeliveryCanBeUpdatedAfterAcknowledgement() {
        let store = makeStore()
        let entry = store.record("Bonjour", delivery: .pending, applicationName: "Notes")
        store.update(entry.id, delivery: .delivered, applicationName: "Pages")
        XCTAssertEqual(store.entries.first?.delivery.rawValue, DeliveryState.delivered.rawValue)
        XCTAssertEqual(store.entries.first?.applicationName, "Pages")
    }

    func testEntriesOlderThanSevenDaysArePrunedOnLoad() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let old = TranscriptEntry(
            id: UUID(),
            text: "Ancien",
            createdAt: Date().addingTimeInterval(-8 * 24 * 3600),
            delivery: .delivered,
            applicationName: nil
        )
        try RemoteCoding.encoder.encode([old]).write(to: fileURL, options: .atomic)
        XCTAssertTrue(makeStore().entries.isEmpty)
    }

    private func makeStore() -> TranscriptHistoryStore {
        TranscriptHistoryStore(fileURL: fileURL, defaults: defaults)
    }
}
