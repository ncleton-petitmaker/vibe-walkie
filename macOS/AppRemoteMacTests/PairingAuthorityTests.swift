import CryptoKit
import Foundation
import XCTest
import RemoteCore
@testable import VibeWalkieMac

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

    func testUnknownIPhoneIsApprovedByValidQR() throws {
        let signed = try responseForActivePairing()
        let decision = try authority.authenticate(response: signed.response, nonce: signed.nonce)
        guard case .approved(let peer) = decision else {
            return XCTFail("Le QR valide doit autoriser immédiatement l’iPhone")
        }
        XCTAssertEqual(peer.name, "iPhone Test")
        XCTAssertEqual(peers.peers.count, 1)
        XCTAssertNil(authority.pendingApproval)
        XCTAssertNil(authority.activeSession)
    }

    func testApprovalPersistsKeyAndKnownDeviceReconnects() throws {
        let signed = try responseForActivePairing()
        let decision = try authority.authenticate(response: signed.response, nonce: signed.nonce)
        guard case .approved = decision else {
            return XCTFail("Autorisation immédiate attendue")
        }
        XCTAssertEqual(peers.peers.count, 1)

        let nonce = SecureRandom.bytes(32)
        let reconnect = try makeResponse(key: signed.signer, nonce: nonce, secret: nil)
        guard case .approved(let peer) = try authority.authenticate(response: reconnect, nonce: nonce) else {
            return XCTFail("Reconnexion connue attendue")
        }
        XCTAssertEqual(peer.id, "iphone-test")
    }

    func testForgottenIPhoneCanReplaceItsKeyWithANewQR() throws {
        let original = try responseForActivePairing()
        guard case .approved = try authority.authenticate(
            response: original.response,
            nonce: original.nonce
        ) else {
            return XCTFail("Première autorisation attendue")
        }

        _ = authority.beginPairing(
            macName: "Mac Test",
            serviceName: "VibeRemote-Test",
            fingerprint: "empreinte"
        )
        let replacementKey = Curve25519.Signing.PrivateKey()
        let nonce = SecureRandom.bytes(32)
        let secret = Data(base64Encoded: authority.activeSession!.payload.pairingSecret)!
        let replacement = try makeResponse(key: replacementKey, nonce: nonce, secret: secret)

        guard case .approved = try authority.authenticate(
            response: replacement,
            nonce: nonce
        ) else {
            return XCTFail("Le nouveau QR doit autoriser le remplacement de clé")
        }
        XCTAssertEqual(peers.peers.first?.publicKey, replacementKey.publicKey.rawRepresentation)
    }

    func testInvalidPairingSecretDoesNotPersistDevice() throws {
        let signed = try responseForActivePairing()
        let invalid = try makeResponse(
            key: signed.signer,
            nonce: signed.nonce,
            secret: SecureRandom.bytes(16)
        )
        XCTAssertThrowsError(try authority.authenticate(response: invalid, nonce: signed.nonce))
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
        guard case .approved = decision else {
            return XCTFail("Autorisation attendue")
        }
        peers.revoke("iphone-test")

        let nonce = SecureRandom.bytes(32)
        let reconnect = try makeResponse(key: signed.signer, nonce: nonce, secret: nil)
        XCTAssertThrowsError(try authority.authenticate(response: reconnect, nonce: nonce))
    }

    func testRemotePairingPublishesTailscaleEndpointForTenMinutes() {
        let endpoint = NomadEndpoint(
            magicDNSName: "mac-vibe.tail123.ts.net",
            ipv4Address: "100.101.22.8"
        )
        let startedAt = Date()
        let session = authority.beginPairing(
            macName: "Mac Test",
            serviceName: "VibeWalkie-Test",
            fingerprint: "empreinte",
            nomadEndpoint: endpoint,
            validity: VibeWalkieInfo.nomadPairingWindow
        )

        XCTAssertEqual(session.nomadEndpoint, endpoint)
        XCTAssertGreaterThanOrEqual(session.expiresAt.timeIntervalSince(startedAt), 599)
        XCTAssertLessThanOrEqual(session.expiresAt.timeIntervalSince(startedAt), 601)
        XCTAssertEqual(session.confirmationCode.count, 6)
    }

    private func responseForActivePairing() throws -> (
        response: PairingResponsePayload,
        nonce: Data,
        signer: Curve25519.Signing.PrivateKey
    ) {
        _ = authority.beginPairing(macName: "Mac Test", serviceName: "VibeWalkie-Test", fingerprint: "empreinte")
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
