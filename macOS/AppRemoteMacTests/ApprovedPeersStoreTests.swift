import Foundation
import XCTest
import RemoteCore
@testable import VibeWalkieMac

@MainActor
final class ApprovedPeersStoreTests: XCTestCase {
    private var directory: URL!
    private var fileURL: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("peers.json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        fileURL = nil
        directory = nil
    }

    func testLoadMergesSamePhysicalIPhoneWithTwoIdentifiers() throws {
        let key = Data(repeating: 7, count: 32)
        let older = ApprovedPeer(
            id: "old-user-defaults-id",
            name: "iPhone",
            publicKey: key,
            pairedAt: Date(timeIntervalSince1970: 100),
            lastSeenAt: Date(timeIntervalSince1970: 200)
        )
        let current = ApprovedPeer(
            id: "new-user-defaults-id",
            name: "iPhone",
            publicKey: key,
            pairedAt: Date(timeIntervalSince1970: 300)
        )
        try RemoteCoding.encoder.encode([older, current]).write(to: fileURL)

        let store = ApprovedPeersStore(fileURL: fileURL)

        XCTAssertEqual(store.peers.count, 1)
        XCTAssertEqual(store.peers.first?.id, current.id)
        let persisted = try RemoteCoding.decoder.decode(
            [ApprovedPeer].self,
            from: Data(contentsOf: fileURL)
        )
        XCTAssertEqual(persisted, [current])
    }

    func testApproveReplacesExistingEntryWithSamePublicKey() {
        let key = Data(repeating: 9, count: 32)
        let store = ApprovedPeersStore(fileURL: fileURL)
        store.approve(ApprovedPeer(
            id: "first-id",
            name: "Ancien iPhone",
            publicKey: key,
            pairedAt: Date(timeIntervalSince1970: 100)
        ))

        let replacement = ApprovedPeer(
            id: "replacement-id",
            name: "iPhone",
            publicKey: key,
            pairedAt: Date(timeIntervalSince1970: 200)
        )
        store.approve(replacement)

        XCTAssertEqual(store.peers, [replacement])
    }

    func testActiveAuthorizationWinsOverNewerRevokedDuplicate() throws {
        let key = Data(repeating: 3, count: 32)
        let active = ApprovedPeer(
            id: "active-id",
            name: "iPhone",
            publicKey: key,
            pairedAt: Date(timeIntervalSince1970: 100)
        )
        let revoked = ApprovedPeer(
            id: "revoked-id",
            name: "iPhone",
            publicKey: key,
            pairedAt: Date(timeIntervalSince1970: 500),
            isRevoked: true
        )
        try RemoteCoding.encoder.encode([active, revoked]).write(to: fileURL)

        let store = ApprovedPeersStore(fileURL: fileURL)

        XCTAssertEqual(store.peers, [active])
    }
}
