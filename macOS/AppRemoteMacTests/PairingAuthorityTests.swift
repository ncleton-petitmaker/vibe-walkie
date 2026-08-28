import CryptoKit
import Foundation
import XCTest
import RemoteCore
@testable import VibeRemoteMac

@MainActor
final class PairingAuthorityTests: XCTestCase {
    private var directory: URL!
    private var peers: ApprovedPeersStore!
    private var authority: PairingAuthority!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        peers = ApprovedPeersStore(fileURL: directory.appendingPathComponent("peers.json"))
        authority = PairingAuthority(peers: peers)
    }

    override func tearDown() async throws {
        authority.endPairing()
        try? FileManager.default.removeItem(at: directory)
        authority = nil
        peers = nil
        directory = nil
    }

    func testUnknownIPhoneWaitsForHumanApproval() throws {
        let signed = try responseForActivePairing()
        let decision = try authority.authenticate(response: signed.response, nonce: signed.nonce)
        guard case .requiresApproval(let pending) = decision else {
            return XCTFail("Une approbation humaine était attendue")
        }
        XCTAssertEqual(pending.peer.name, "iPhone Test")
        XCTAssertTrue(peers.peers.isEmpty)
        XCTAssertNotNil(authority.pendingApproval)
    }

    func testApprovalPersistsKeyAndKnownDeviceReconnects() throws {
        let signed = try responseForActivePairing()
        let decision = try authority.authenticate(response: signed.response, nonce: signed.nonce)
        guard case .requiresApproval(let pending) = decision else {
            return XCTFail("Approbation attendue")
        }
        XCTAssertNotNil(authority.approve(pending.id))
        XCTAssertEqual(peers.peers.count, 1)

        let nonce = SecureRandom.bytes(32)
        let reconnect = try makeResponse(key: signed.key, nonce: nonce, secret: nil)
        guard case .approved(let peer) = try authority.authenticate(response: reconnect, nonce: nonce) else {
            return XCTFail("Reconnexion connue attendue")
        }
        XCTAssertEqual(peer.id, "iphone-test")
    }

    func testDenialDoesNotPersistDevice() throws {
        let signed = try responseForActivePairing()
        let decision = try authority.authenticate(response: signed.response, nonce: signed.nonce)
        guard case .requiresApproval(let pending) = decision else {
            return XCTFail("Approbation attendue")
        }
        XCTAssertTrue(authority.cancelPendingApproval(pending.id))
        XCTAssertTrue(peers.peers.isEmpty)
        XCTAssertNil(authority.pendingApproval)
    }

    func testExpiredApprovalIsDetected() {
        let pending = PairingAuthority.PendingApproval(
            id: UUID(),
            peer: ApprovedPeer(id: "x", name: "x", publicKey: Data(), pairedAt: Date()),
            confirmationCode: "123456",
            expiresAt: Date().addingTimeInterval(-1)
        )
        XCTAssertTrue(pending.isExpired)
    }

    func testRevokedDeviceCannotReconnect() throws {
        let signed = try responseForActivePairing()
        let decision = try authority.authenticate(response: signed.response, nonce: signed.nonce)
        guard case .requiresApproval(let pending) = decision else {
            return XCTFail("Approbation attendue")
        }
        _ = authority.approve(pending.id)
        peers.revoke("iphone-test")

        let nonce = SecureRandom.bytes(32)
        let reconnect = try makeResponse(key: signed.key, nonce: nonce, secret: nil)
        XCTAssertThrowsError(try authority.authenticate(response: reconnect, nonce: nonce))
    }

    private func responseForActivePairing() throws -> (
        response: PairingResponsePayload,
        nonce: Data,
        key: Curve25519.Signing.PrivateKey
    ) {
        _ = authority.beginPairing(macName: "Mac Test", serviceName: "VibeRemote-Test", fingerprint: "empreinte")
        let key = Curve25519.Signing.PrivateKey()
        let nonce = SecureRandom.bytes(32)
        let secret = Data(base64Encoded: authority.activeSession!.payload.pairingSecret)!
        return (try makeResponse(key: key, nonce: nonce, secret: secret), nonce, key)
    }

    private func makeResponse(
        key: Curve25519.Signing.PrivateKey,
        nonce: Data,
        secret: Data?
    ) throws -> PairingResponsePayload {
        PairingResponsePayload(
            deviceIdentifier: "iphone-test",
            deviceName: "iPhone Test",
            publicKey: key.publicKey.rawRepresentation,
            signature: try ChallengeSigner.sign(
                nonce: nonce,
                deviceIdentifier: "iphone-test",
                pairingSecret: secret,
                privateKey: key
            ),
            pairingSecret: secret
        )
    }
}
