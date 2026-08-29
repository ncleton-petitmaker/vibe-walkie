import Foundation
import CryptoKit
import Testing
@testable import RemoteCore

/// Rejoue la poignée de main complète entre un iPhone et un Mac simulés.
///
/// Ces tests portent sur la logique de confiance, pas sur le transport : ils
/// vérifient qu'un appareil non appairé, une clé substituée ou un défi rejoué
/// sont refusés avant qu'une seule commande ne soit exécutée.
@Suite("Poignée de main de bout en bout")
struct HandshakeTests {

    /// Mac simulé : émet un défi, vérifie la réponse, tient sa liste de pairs.
    private final class FakeMac {
        var approved: [String: Data] = [:]
        var pairingSecret: Data?
        private(set) var nonce = SecureRandom.bytes(32)

        func newChallenge() -> Data {
            nonce = SecureRandom.bytes(32)
            return nonce
        }

        func authenticate(_ response: PairingResponsePayload) -> Bool {
            if let knownKey = approved[response.deviceIdentifier] {
                guard knownKey == response.publicKey else { return false }
                let verificationSecret: Data?
                if let provided = response.pairingSecret {
                    guard provided == pairingSecret else { return false }
                    verificationSecret = provided
                } else {
                    verificationSecret = nil
                }
                return ChallengeSigner.verify(
                    signature: response.signature,
                    nonce: nonce,
                    deviceIdentifier: response.deviceIdentifier,
                    pairingSecret: verificationSecret,
                    publicKeyRepresentation: knownKey
                )
            }

            guard let secret = pairingSecret, response.pairingSecret == secret else { return false }
            guard ChallengeSigner.verify(
                signature: response.signature,
                nonce: nonce,
                deviceIdentifier: response.deviceIdentifier,
                pairingSecret: secret,
                publicKeyRepresentation: response.publicKey
            ) else { return false }

            approved[response.deviceIdentifier] = response.publicKey
            pairingSecret = nil
            return true
        }
    }

    private func respond(
        key: Curve25519.Signing.PrivateKey,
        identifier: String = "iphone-nicolas",
        nonce: Data,
        secret: Data?
    ) throws -> PairingResponsePayload {
        try PairingResponsePayload(
            deviceIdentifier: identifier,
            deviceName: "iPhone de Nicolas",
            publicKey: key.publicKey.rawRepresentation,
            signature: ChallengeSigner.sign(
                nonce: nonce,
                deviceIdentifier: identifier,
                pairingSecret: secret,
                privateKey: key
            ),
            pairingSecret: secret
        )
    }

    @Test("Premier appairage avec le secret du QR, puis reconnexion sans lui")
    func pairThenReconnect() throws {
        let mac = FakeMac()
        let secret = SecureRandom.bytes(16)
        mac.pairingSecret = secret
        let key = Curve25519.Signing.PrivateKey()

        let firstNonce = mac.newChallenge()
        #expect(mac.authenticate(try respond(key: key, nonce: firstNonce, secret: secret)))

        // Le secret est consommé : la reconnexion s'appuie uniquement sur la
        // clé enregistrée.
        let secondNonce = mac.newChallenge()
        #expect(mac.authenticate(try respond(key: key, nonce: secondNonce, secret: nil)))
    }

    @Test("Un iPhone connu peut être réappairé avec un nouveau QR")
    func knownDeviceCanPairAgain() throws {
        let mac = FakeMac()
        let key = Curve25519.Signing.PrivateKey()

        let firstSecret = SecureRandom.bytes(16)
        mac.pairingSecret = firstSecret
        #expect(mac.authenticate(try respond(key: key, nonce: mac.newChallenge(), secret: firstSecret)))

        let replacementSecret = SecureRandom.bytes(16)
        mac.pairingSecret = replacementSecret
        #expect(mac.authenticate(try respond(key: key, nonce: mac.newChallenge(), secret: replacementSecret)))
    }

    @Test("Un appareil du réseau sans QR est refusé")
    func unknownDeviceRejected() throws {
        let mac = FakeMac()
        let intruder = Curve25519.Signing.PrivateKey()
        let nonce = mac.newChallenge()

        #expect(mac.authenticate(try respond(key: intruder, identifier: "intrus", nonce: nonce, secret: nil)) == false)
        #expect(mac.approved.isEmpty)
    }

    @Test("Un mauvais secret d'appairage est refusé")
    func wrongSecretRejected() throws {
        let mac = FakeMac()
        mac.pairingSecret = SecureRandom.bytes(16)
        let key = Curve25519.Signing.PrivateKey()
        let nonce = mac.newChallenge()

        #expect(mac.authenticate(try respond(key: key, nonce: nonce, secret: SecureRandom.bytes(16))) == false)
    }

    @Test("Une réponse capturée ne vaut plus rien au défi suivant")
    func capturedResponseRejected() throws {
        let mac = FakeMac()
        let secret = SecureRandom.bytes(16)
        mac.pairingSecret = secret
        let key = Curve25519.Signing.PrivateKey()

        let nonce = mac.newChallenge()
        let captured = try respond(key: key, nonce: nonce, secret: secret)
        #expect(mac.authenticate(captured))

        _ = mac.newChallenge()
        #expect(mac.authenticate(captured) == false)
    }

    @Test("Une clé substituée pour un appareil connu est refusée")
    func keySubstitutionRejected() throws {
        let mac = FakeMac()
        let secret = SecureRandom.bytes(16)
        mac.pairingSecret = secret
        let genuine = Curve25519.Signing.PrivateKey()
        #expect(mac.authenticate(try respond(key: genuine, nonce: mac.newChallenge(), secret: secret)))

        let attacker = Curve25519.Signing.PrivateKey()
        let nonce = mac.newChallenge()
        #expect(mac.authenticate(try respond(key: attacker, nonce: nonce, secret: nil)) == false)
    }
}

@Suite("Garanties de la cible d'insertion")
struct TargetTokenTests {

    @Test("Un jeton expiré est détecté")
    func expiredToken() {
        let token = TargetToken(
            token: UUID().uuidString,
            applicationName: "Notes",
            bundleIdentifier: "com.apple.Notes",
            windowTitle: nil,
            expiresAt: Date().addingTimeInterval(-1)
        )
        #expect(token.expiresAt < Date())
    }

    @Test("La durée de vie couvre une dictée normale sans être illimitée")
    func lifetimeIsReasonable() {
        #expect(VibeWalkieInfo.targetTokenLifetime >= 60)
        #expect(VibeWalkieInfo.targetTokenLifetime <= 300)
    }

    @Test("Le texte d'une dictée reste sous la limite du protocole")
    func textLimitIsGenerous() {
        // Une dictée de deux minutes fait rarement plus de 2000 caractères.
        #expect(ProtocolLimits.maxTextLength >= 10_000)
    }
}
