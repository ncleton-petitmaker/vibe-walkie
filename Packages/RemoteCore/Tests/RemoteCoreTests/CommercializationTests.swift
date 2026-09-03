import Foundation
import Testing
@testable import RemoteCore

@Suite("Contrat de commercialisation V1")
struct CommercializationTests {
    @Test("Le service Bonjour de travail est cohérent")
    func bonjourIdentity() {
        #expect(VibeWalkieInfo.bonjourServiceType == "_viberemote._tcp")
        #expect(VibeWalkieInfo.controlPort == 54_389)
    }

    @Test("Les identifiants de travail sont cohérents")
    func bundleIdentifiers() {
        #expect(VibeWalkieInfo.iosBundleIdentifier == "com.nicolascleton.viberemote")
        #expect(VibeWalkieInfo.macBundleIdentifier == "com.nicolascleton.viberemote.mac")
    }

    @Test("Les fenêtres d'appairage sont bornées")
    func pairingWindows() {
        #expect(VibeWalkieInfo.pairingWindow == 120)
        #expect(VibeWalkieInfo.nomadPairingWindow == 600)
        #expect(VibeWalkieInfo.pairingApprovalWindow == 60)
    }

    @Test("Hello annonce toujours le protocole V4 et la plateforme cliente")
    func helloDefaultsToV4() {
        let hello = HelloPayload(deviceName: "iPhone", deviceIdentifier: "test", appVersion: "1")
        #expect(hello.protocolVersion == 4)
        #expect(hello.clientPlatform == .iOS)
    }

    @Test("L'état de connexion transporte uniquement une route Tailscale bornée")
    func connectionStatusHasBoundedNomadRoute() throws {
        let endpoint = NomadEndpoint(magicDNSName: "mac.tail1234.ts.net", ipv4Address: "100.64.0.1")
        let payload = ConnectionStatusPayload(
            accessibilityGranted: true,
            macName: "Mac",
            companionVersion: "1",
            nomadEndpoint: endpoint
        )
        let json = String(decoding: try RemoteCoding.encoder.encode(payload), as: UTF8.self)
        #expect(!json.contains("remoteHost"))
        #expect(!json.contains("remotePort"))
        #expect(json.contains("mac.tail1234.ts.net"))
        #expect(endpoint.isValid)
    }

    @Test("Le QR compact ne transporte aucun relais ni compte")
    func qrHasNoRelayOrAccount() throws {
        let qr = PairingQRPayload(
            macName: "Mac",
            serviceName: "VibeWalkie-Mac",
            certificateFingerprint: "fingerprint",
            pairingSecret: "secret",
            expiresAt: Date().addingTimeInterval(120),
            nomadEndpoint: NomadEndpoint(
                magicDNSName: "mac.tail1234.ts.net",
                ipv4Address: "100.105.79.12"
            )
        )
        let data = try #require(Data(base64Encoded: qr.encoded()))
        let decoded = String(decoding: data, as: UTF8.self)
        #expect(!decoded.contains("remoteHost"))
        #expect(!decoded.contains("remotePort"))
        #expect(!decoded.lowercased().contains("oauth"))
        #expect(!decoded.lowercased().contains("relay"))
    }

    @Test("Les points d'accès Nomade sont strictement validés")
    func nomadEndpointValidation() {
        #expect(NomadEndpoint(magicDNSName: "mac.tail1234.ts.net", ipv4Address: "100.127.255.254").isValid)
        #expect(!NomadEndpoint(magicDNSName: "mac.local", ipv4Address: "100.105.79.12").isValid)
        #expect(!NomadEndpoint(magicDNSName: "mac.tail1234.ts.net", ipv4Address: "192.168.1.10").isValid)
        #expect(!NomadEndpoint(magicDNSName: "mac.tail1234.ts.net", port: 22).isValid)
    }

    @Test("Seul l'état prêt est opérationnel")
    func readyState() {
        #expect(ConnectionState.ready(hostName: "Mac").isReady)
        #expect(!ConnectionState.searching.isReady)
        #expect(!ConnectionState.awaitingApproval(hostName: "Mac", confirmationCode: "123456").isReady)
    }

    @Test("L'attente d'autorisation conserve le nom du Mac")
    func pendingApprovalMacName() {
        let state = ConnectionState.awaitingApproval(hostName: "Mac Studio", confirmationCode: "123456")
        #expect(state.macName == "Mac Studio")
    }

    @Test("Le refus d'appairage propose une action compréhensible")
    func pairingDeniedMessage() {
        #expect(RemoteErrorCode.pairingDenied.localizedMessage.contains("refusé"))
    }

    @Test("L'expiration d'approbation demande un nouveau scan")
    func pairingExpiredMessage() {
        #expect(RemoteErrorCode.pairingApprovalExpired.localizedMessage.contains("Scannez"))
    }

    @Test("L'incompatibilité demande la mise à jour des deux apps")
    func protocolMismatchMessage() {
        let message = RemoteErrorCode.protocolMismatch.localizedMessage
        #expect(message.contains("deux appareils"))
    }

    @Test("Une trame vide reste une trame valide et distincte")
    func emptyFrameRoundTrip() throws {
        var framer = MessageFramer()
        #expect(try framer.append(MessageFramer.frame(Data())) == [Data()])
    }

    @Test("La remise à zéro jette une trame partielle")
    func resetDropsPartialFrame() throws {
        var framer = MessageFramer()
        let full = try MessageFramer.frame(Data("ancien".utf8))
        _ = try framer.append(Data(full.prefix(5)))
        framer.reset()
        #expect(try framer.append(MessageFramer.frame(Data("nouveau".utf8))) == [Data("nouveau".utf8)])
    }

    @Test("Le secret d'appairage est lié à la preuve signée")
    func signingMessageBindsSecret() {
        let nonce = Data(repeating: 1, count: 32)
        let withoutSecret = ChallengeSigner.message(nonce: nonce, deviceIdentifier: "iphone", pairingSecret: nil)
        let withSecret = ChallengeSigner.message(nonce: nonce, deviceIdentifier: "iphone", pairingSecret: Data([2]))
        #expect(withSecret != withoutSecret)
    }

    @Test("La révocation d'un pair survit à la persistance")
    func revokedPeerRoundTrip() throws {
        let peer = ApprovedPeer(
            id: "iphone",
            name: "iPhone",
            publicKey: Data(repeating: 3, count: 32),
            pairedAt: Date(),
            isRevoked: true
        )
        let encoded = try RemoteCoding.encoder.encode(peer)
        let decoded = try RemoteCoding.decoder.decode(ApprovedPeer.self, from: encoded)
        #expect(decoded.isRevoked)
        #expect(decoded.publicKey == peer.publicKey)
    }
}
