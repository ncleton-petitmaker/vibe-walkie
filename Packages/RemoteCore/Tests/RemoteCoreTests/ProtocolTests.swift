import Foundation
import CryptoKit
import Testing
@testable import RemoteCore

@Suite("Cadrage des messages")
struct MessageFramerTests {

    @Test("Un message encadré est restitué intact")
    func roundTrip() throws {
        var framer = MessageFramer()
        let payload = Data("bonjour".utf8)
        let framed = try MessageFramer.frame(payload)
        let messages = try framer.append(framed)
        #expect(messages == [payload])
    }

    @Test("Un message arrivé en plusieurs morceaux est reconstitué")
    func splitDelivery() throws {
        var framer = MessageFramer()
        let payload = Data(repeating: 0x41, count: 500)
        let framed = try MessageFramer.frame(payload)

        let firstChunk = framed.prefix(10)
        let secondChunk = framed.dropFirst(10)

        let partial = try framer.append(Data(firstChunk))
        let completed = try framer.append(Data(secondChunk))
        #expect(partial.isEmpty)
        #expect(completed == [payload])
    }

    @Test("Plusieurs messages dans un même paquet sont séparés")
    func multipleMessages() throws {
        var framer = MessageFramer()
        var stream = Data()
        stream.append(try MessageFramer.frame(Data("un".utf8)))
        stream.append(try MessageFramer.frame(Data("deux".utf8)))

        let messages = try framer.append(stream)
        #expect(messages.count == 2)
        #expect(String(data: messages[1], encoding: .utf8) == "deux")
    }

    @Test("Une longueur au-delà de la limite est rejetée sans allouer")
    func oversizedFrameRejected() throws {
        var framer = MessageFramer()
        var header = Data()
        var length = UInt32(ProtocolLimits.maxFrameBytes + 1).bigEndian
        withUnsafeBytes(of: &length) { header.append(contentsOf: $0) }

        #expect(throws: MessageFramer.FramingError.self) {
            _ = try framer.append(header)
        }
    }

    @Test("Encoder une charge utile trop grande échoue")
    func oversizedPayloadRejected() {
        let payload = Data(repeating: 0, count: ProtocolLimits.maxFrameBytes + 1)
        #expect(throws: MessageFramer.FramingError.self) {
            _ = try MessageFramer.frame(payload)
        }
    }
}

@Suite("Enveloppe")
struct EnvelopeTests {

    @Test("Le réseau local est toujours préféré au Mode Nomade")
    func localRoutePriority() {
        #expect(ConnectionRoute.local.isPreferred(over: .nomad))
        #expect(!ConnectionRoute.nomad.isPreferred(over: .local))
        #expect(!ConnectionRoute.local.isPreferred(over: .local))
    }

    @Test("La charge utile typée survit à l'aller-retour")
    func payloadRoundTrip() throws {
        let payload = InsertTextPayload(targetToken: "abc", text: "Bonjour, ça va ?", dictationID: UUID())
        let envelope = try RemoteEnvelope.make(
            type: .insertText,
            sessionID: "s1",
            sequence: 1,
            payload: payload
        )

        let data = try RemoteCoding.encoder.encode(envelope)
        let decoded = try RemoteCoding.decoder.decode(RemoteEnvelope.self, from: data)
        let decodedPayload = try decoded.decodePayload(InsertTextPayload.self)

        #expect(decoded.type == .insertText)
        #expect(decodedPayload.text == "Bonjour, ça va ?")
    }

    @Test("Une image d’écran survit à l’aller-retour")
    func screenFrameRoundTrip() throws {
        let payload = ScreenFramePayload(
            jpegData: Data(repeating: 0x42, count: 1_024),
            width: 1_280,
            height: 800
        )
        let envelope = try RemoteEnvelope.make(
            type: .screenFrame,
            sessionID: "screen",
            sequence: 2,
            payload: payload
        )

        let data = try RemoteCoding.encoder.encode(envelope)
        let decoded = try RemoteCoding.decoder.decode(RemoteEnvelope.self, from: data)
        let frame = try decoded.decodePayload(ScreenFramePayload.self)
        #expect(frame.jpegData == payload.jpegData)
        #expect(frame.width == 1_280)
        #expect(frame.height == 800)
    }

    @Test("Une demande d'approbation d'appairage survit à l'aller-retour")
    func pairingPendingRoundTrip() throws {
        let payload = PairingPendingPayload(
            requestID: UUID(),
            deviceName: "iPhone de test",
            confirmationCode: "123456",
            expiresAt: Date().addingTimeInterval(60)
        )
        let data = try RemoteCoding.encoder.encode(payload)
        let decoded = try RemoteCoding.decoder.decode(PairingPendingPayload.self, from: data)

        #expect(decoded.requestID == payload.requestID)
        #expect(decoded.deviceName == payload.deviceName)
        #expect(decoded.confirmationCode == payload.confirmationCode)
        #expect(abs(decoded.expiresAt.timeIntervalSince(payload.expiresAt)) < 1)
    }

    @Test("Tous les types de message ont une valeur brute stable")
    func messageTypesStable() {
        #expect(RemoteMessageType.insertText.rawValue == "insert_text")
        #expect(RemoteMessageType.activateWindow.rawValue == "activate_window")
        #expect(RemoteMessageType.pairingPending.rawValue == "pairing_pending")
        #expect(RemoteMessageType.allCases.count == 27)
        #expect(ProtocolVersion.current == 3)
    }

    @Test("La commande du switcher d'app conserve sa valeur réseau")
    func applicationSwitcherKeyIsStable() throws {
        #expect(RemoteKey.applicationSwitcher.rawValue == "application_switcher")
        let payload = try RemoteCoding.decoder.decode(
            KeyPressPayload.self,
            from: Data(#"{"key":"application_switcher"}"#.utf8)
        )
        #expect(payload.key == .applicationSwitcher)
    }

    @Test("La commande de conversation suivante conserve sa valeur réseau")
    func nextConversationKeyIsStable() throws {
        #expect(RemoteKey.nextConversation.rawValue == "next_conversation")
        let payload = try RemoteCoding.decoder.decode(
            KeyPressPayload.self,
            from: Data(#"{"key":"next_conversation"}"#.utf8)
        )
        #expect(payload.key == .nextConversation)
    }

    @Test("La configuration du bloc et un raccourci Mac survivent à l’encodage")
    func controlConfigurationRoundTrip() throws {
        let shortcut = MacKeyboardShortcut(
            keyCode: 40,
            modifiers: [.command, .shift],
            displayName: "⌘⇧K"
        )
        var configuration = ControlConfiguration.standard
        configuration.setButton(ControlButtonConfiguration(
            zone: .upperLeft,
            title: "Mon raccourci",
            icon: .system("command"),
            action: .macShortcut(shortcut)
        ))
        let available = configuration.availableGlobalButtons
        let rightArrow = try #require(available.first(where: { $0.id == "standard.right" }))
        configuration.setAvailableGlobalButtonOrder([rightArrow] + available.filter { $0.id != rightArrow.id })

        let data = try RemoteCoding.encoder.encode(ControlConfigurationPayload(configuration: configuration))
        let decoded = try RemoteCoding.decoder.decode(ControlConfigurationPayload.self, from: data)

        #expect(decoded.configuration.button(in: .upperLeft).title == "Mon raccourci")
        #expect(decoded.configuration.button(in: .upperLeft).action == .macShortcut(shortcut))
        #expect(decoded.configuration.availableGlobalButtons.first?.id == "standard.right")
        #expect(decoded.configuration.availableGlobalButtons.allSatisfy { candidate in
            !decoded.configuration.buttons.contains { $0.action == candidate.action }
        })
        #expect(ControlZone.allCases.count == 7)
    }

    @Test("Une ancienne configuration reçoit automatiquement l’ordre Global par défaut")
    func legacyControlConfigurationGetsGlobalOrder() throws {
        let encoded = try RemoteCoding.encoder.encode(ControlConfiguration.standard)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "globalButtons")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try RemoteCoding.decoder.decode(ControlConfiguration.self, from: legacyData)

        #expect(decoded.globalButtons == ControlConfiguration.standardGlobalButtons)
        #expect(decoded.availableGlobalButtons.count == 9)
    }
}

@Suite("Anti-rejeu")
struct SequenceValidatorTests {

    private func envelope(sequence: UInt64, id: UUID = UUID()) -> RemoteEnvelope {
        RemoteEnvelope(type: .keyPress, messageID: id, sessionID: "s", sequence: sequence)
    }

    @Test("Une séquence croissante est acceptée")
    func increasingAccepted() {
        var validator = SequenceValidator()
        let first = validator.validate(envelope(sequence: 1))
        let second = validator.validate(envelope(sequence: 2))
        #expect(first == .accepted)
        #expect(second == .accepted)
    }

    @Test("Une séquence ancienne est un rejeu")
    func staleSequenceIsReplay() {
        var validator = SequenceValidator()
        _ = validator.validate(envelope(sequence: 5))
        let verdict = validator.validate(envelope(sequence: 3))
        #expect(verdict == .replay)
    }

    @Test("Un identifiant déjà vu est un doublon, pas une seconde exécution")
    func duplicateDetected() {
        var validator = SequenceValidator()
        let id = UUID()
        let first = validator.validate(envelope(sequence: 1, id: id))
        let second = validator.validate(envelope(sequence: 2, id: id))
        #expect(first == .accepted)
        #expect(second == .duplicate(id))
    }
}

@Suite("Limitation de débit")
struct RateLimiterTests {

    @Test("La rafale est bornée par la capacité")
    func burstIsCapped() {
        var limiter = RateLimiter(capacity: 3, refillPerSecond: 1)
        let results = (0..<4).map { _ in limiter.allow() }
        #expect(results == [true, true, true, false])
    }

    @Test("Les jetons se rechargent avec le temps")
    func refills() {
        let start = Date()
        var limiter = RateLimiter(capacity: 2, refillPerSecond: 10, now: start)
        let first = limiter.allow(now: start)
        let second = limiter.allow(now: start)
        let exhausted = limiter.allow(now: start)
        let afterRefill = limiter.allow(now: start.addingTimeInterval(0.5))
        #expect([first, second, exhausted, afterRefill] == [true, true, false, true])
    }
}

@Suite("Appairage")
struct PairingTests {

    private func makePayload(
        expires: Date = Date().addingTimeInterval(120),
        nomadEndpoint: NomadEndpoint? = nil
    ) -> PairingQRPayload {
        PairingQRPayload(
            macName: "Mac de Nicolas",
            serviceName: "appremote-1234",
            certificateFingerprint: SecureRandom.bytes(32).base64EncodedString(),
            pairingSecret: SecureRandom.bytes(16).base64EncodedString(),
            expiresAt: expires,
            nomadEndpoint: nomadEndpoint
        )
    }

    @Test("Le QR Nomade conserve le point d'accès Tailscale")
    func nomadQRRoundTrip() throws {
        let endpoint = NomadEndpoint(
            magicDNSName: "MacBook-Pro.tail1234.ts.net.",
            ipv4Address: "100.105.79.12"
        )
        let payload = makePayload(nomadEndpoint: endpoint)
        let decoded = try PairingQRPayload.decode(try payload.encoded())
        #expect(decoded.nomadEndpoint == endpoint)
        #expect(decoded.nomadEndpoint?.isValid == true)
    }

    @Test("Le QR survit à l'encodage base64")
    func qrRoundTrip() throws {
        let payload = makePayload()
        let decoded = try PairingQRPayload.decode(try payload.encoded())
        // L'égalité stricte n'est pas testée sur la date : l'encodage ISO 8601
        // arrondit à la seconde. Sans effet ici (la fenêtre d'appairage dure
        // deux minutes), mais il ne faut pas prétendre à une identité binaire.
        #expect(decoded.macName == payload.macName)
        #expect(decoded.serviceName == payload.serviceName)
        #expect(decoded.certificateFingerprint == payload.certificateFingerprint)
        #expect(decoded.pairingSecret == payload.pairingSecret)
        #expect(decoded.confirmationCode == payload.confirmationCode)
        #expect(abs(decoded.expiresAt.timeIntervalSince(payload.expiresAt)) < 1)
    }

    @Test("Le QR reste strictement identique entre deux rendus")
    func qrEncodingIsStable() throws {
        let payload = makePayload()
        let encodings = try (0..<20).map { _ in try payload.encoded() }
        #expect(Set(encodings).count == 1)
    }

    @Test("L'ancien format QR reste lisible")
    func legacyQRStillDecodes() throws {
        let payload = makePayload()
        let legacy = try RemoteCoding.encoder.encode(payload).base64EncodedString()
        let decoded = try PairingQRPayload.decode(legacy)
        #expect(decoded.macName == payload.macName)
        #expect(decoded.confirmationCode == payload.confirmationCode)
    }

    @Test("Le QR compact est plus court que l'ancien format")
    func compactQRIsShorter() throws {
        let payload = makePayload()
        let legacy = try RemoteCoding.encoder.encode(payload).base64EncodedString()
        #expect(try payload.encoded().count < legacy.count)
    }

    @Test("Le code de confirmation fait six chiffres et est déterministe")
    func confirmationCode() {
        let payload = makePayload()
        #expect(payload.confirmationCode.count == 6)
        #expect(payload.confirmationCode == payload.confirmationCode)
    }

    @Test("Deux QR différents donnent des codes différents")
    func confirmationCodesDiffer() {
        #expect(makePayload().confirmationCode != makePayload().confirmationCode)
    }

    @Test("Un QR périmé est détecté")
    func expiryDetected() {
        #expect(makePayload(expires: Date().addingTimeInterval(-1)).isExpired)
        #expect(makePayload().isExpired == false)
    }

    @Test("Un QR illisible échoue explicitement")
    func invalidQRThrows() {
        #expect(throws: RemoteErrorPayload.self) {
            _ = try PairingQRPayload.decode("pas du base64 !!!")
        }
    }
}

@Suite("Signature du défi")
struct ChallengeSignerTests {

    @Test("Une signature valide est acceptée")
    func validSignature() throws {
        let key = Curve25519.Signing.PrivateKey()
        let nonce = SecureRandom.bytes(32)
        let signature = try ChallengeSigner.sign(
            nonce: nonce,
            deviceIdentifier: "iphone-1",
            pairingSecret: nil,
            privateKey: key
        )

        #expect(ChallengeSigner.verify(
            signature: signature,
            nonce: nonce,
            deviceIdentifier: "iphone-1",
            pairingSecret: nil,
            publicKeyRepresentation: key.publicKey.rawRepresentation
        ))
    }

    @Test("Une signature rejouée avec un autre nonce est refusée")
    func replayedNonceRejected() throws {
        let key = Curve25519.Signing.PrivateKey()
        let signature = try ChallengeSigner.sign(
            nonce: SecureRandom.bytes(32),
            deviceIdentifier: "iphone-1",
            pairingSecret: nil,
            privateKey: key
        )

        #expect(ChallengeSigner.verify(
            signature: signature,
            nonce: SecureRandom.bytes(32),
            deviceIdentifier: "iphone-1",
            pairingSecret: nil,
            publicKeyRepresentation: key.publicKey.rawRepresentation
        ) == false)
    }

    @Test("La clé d'un autre appareil ne valide pas la signature")
    func otherKeyRejected() throws {
        let key = Curve25519.Signing.PrivateKey()
        let attacker = Curve25519.Signing.PrivateKey()
        let nonce = SecureRandom.bytes(32)
        let signature = try ChallengeSigner.sign(
            nonce: nonce,
            deviceIdentifier: "iphone-1",
            pairingSecret: nil,
            privateKey: key
        )

        #expect(ChallengeSigner.verify(
            signature: signature,
            nonce: nonce,
            deviceIdentifier: "iphone-1",
            pairingSecret: nil,
            publicKeyRepresentation: attacker.publicKey.rawRepresentation
        ) == false)
    }

    @Test("Un identifiant d'appareil substitué invalide la signature")
    func identitySubstitutionRejected() throws {
        let key = Curve25519.Signing.PrivateKey()
        let nonce = SecureRandom.bytes(32)
        let signature = try ChallengeSigner.sign(
            nonce: nonce,
            deviceIdentifier: "iphone-1",
            pairingSecret: nil,
            privateKey: key
        )

        #expect(ChallengeSigner.verify(
            signature: signature,
            nonce: nonce,
            deviceIdentifier: "iphone-2",
            pairingSecret: nil,
            publicKeyRepresentation: key.publicKey.rawRepresentation
        ) == false)
    }
}

@Suite("Politique de reconnexion")
struct RetryPolicyTests {

    @Test("Le délai croît puis plafonne")
    func backoffGrowsAndCaps() {
        var policy = RetryPolicy(base: 1, maximum: 10)
        let first = policy.nextDelay()
        var last = first
        for _ in 0..<10 { last = policy.nextDelay() }
        #expect(first < 3)
        #expect(last <= 10)
    }

    @Test("Une connexion réussie remet le compteur à zéro")
    func resetClearsAttempts() {
        var policy = RetryPolicy()
        _ = policy.nextDelay()
        _ = policy.nextDelay()
        policy.reset()
        #expect(policy.attemptCount == 0)
    }
}
