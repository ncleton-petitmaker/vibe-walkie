import Foundation
import CryptoKit

/// Contenu du QR affiché par un compagnon de bureau.
///
/// L'empreinte du certificat voyage hors du réseau, par la caméra. C'est ce
/// qui permet à l'iPhone d'épingler exactement ce Mac : un attaquant du même
/// Wi-Fi qui usurpe le service Bonjour présentera un autre certificat et sera
/// rejeté avant tout échange de commande.
public struct PairingQRPayload: Codable, Sendable, Equatable {
    public let version: Int
    public let hostName: String
    public let hostPlatform: HostPlatform
    public let serviceName: String
    /// SHA-256 du certificat TLS du Mac, encodé en base64.
    public let certificateFingerprint: String
    /// Secret aléatoire de 128 bits, à usage unique, encodé en base64.
    public let pairingSecret: String
    public let expiresAt: Date
    /// Point d'accès privé facultatif pour le Mode Nomade Tailscale.
    public let nomadEndpoint: NomadEndpoint?

    public init(
        version: Int = ProtocolVersion.current,
        hostName: String,
        hostPlatform: HostPlatform,
        serviceName: String,
        certificateFingerprint: String,
        pairingSecret: String,
        expiresAt: Date,
        nomadEndpoint: NomadEndpoint? = nil
    ) {
        self.version = version
        self.hostName = hostName
        self.hostPlatform = hostPlatform
        self.serviceName = serviceName
        self.certificateFingerprint = certificateFingerprint
        self.pairingSecret = pairingSecret
        self.expiresAt = expiresAt
        self.nomadEndpoint = nomadEndpoint
    }

    public init(
        version: Int = ProtocolVersion.current,
        macName: String,
        serviceName: String,
        certificateFingerprint: String,
        pairingSecret: String,
        expiresAt: Date,
        nomadEndpoint: NomadEndpoint? = nil
    ) {
        self.init(
            version: version,
            hostName: macName,
            hostPlatform: .macOS,
            serviceName: serviceName,
            certificateFingerprint: certificateFingerprint,
            pairingSecret: pairingSecret,
            expiresAt: expiresAt,
            nomadEndpoint: nomadEndpoint
        )
    }

    public var macName: String { hostName }

    private enum CodingKeys: String, CodingKey {
        case version
        case hostName
        case hostPlatform
        case macName
        case serviceName
        case certificateFingerprint
        case pairingSecret
        case expiresAt
        case nomadEndpoint
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        hostName = try container.decodeIfPresent(String.self, forKey: .hostName)
            ?? container.decode(String.self, forKey: .macName)
        hostPlatform = try container.decodeIfPresent(HostPlatform.self, forKey: .hostPlatform) ?? .macOS
        serviceName = try container.decode(String.self, forKey: .serviceName)
        certificateFingerprint = try container.decode(String.self, forKey: .certificateFingerprint)
        pairingSecret = try container.decode(String.self, forKey: .pairingSecret)
        expiresAt = try container.decode(Date.self, forKey: .expiresAt)
        nomadEndpoint = try container.decodeIfPresent(NomadEndpoint.self, forKey: .nomadEndpoint)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(hostName, forKey: .hostName)
        try container.encode(hostPlatform, forKey: .hostPlatform)
        try container.encode(serviceName, forKey: .serviceName)
        try container.encode(certificateFingerprint, forKey: .certificateFingerprint)
        try container.encode(pairingSecret, forKey: .pairingSecret)
        try container.encode(expiresAt, forKey: .expiresAt)
        try container.encodeIfPresent(nomadEndpoint, forKey: .nomadEndpoint)
    }

    public var isExpired: Bool { Date() >= expiresAt }

    /// Code court affiché des deux côtés pour la confirmation humaine.
    ///
    /// Il est dérivé de l'empreinte et du secret : si l'iPhone a scanné un
    /// autre QR ou parle à un autre Mac, les six chiffres ne correspondront pas.
    public var confirmationCode: String {
        var hasher = SHA256()
        hasher.update(data: Data(certificateFingerprint.utf8))
        hasher.update(data: Data(pairingSecret.utf8))
        let digest = hasher.finalize()
        let value = digest.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return String(format: "%06u", value % 1_000_000)
    }

    public func encoded() throws -> String {
        // Le format compact diminue sensiblement le nombre de modules du QR.
        // `decode` conserve la lecture de l'ancien format aux clés longues.
        let data = try RemoteCoding.encoder.encode(CompactPairingQRPayload(self))
        return data.base64EncodedString()
    }

    /// Rejects malformed camera input before it can enter a pairing attempt.
    /// The certificate pin is SHA-256 (32 bytes) and the one-time secret is
    /// 128 bits (16 bytes); accepting arbitrary strings here would create
    /// platform-dependent failures later in TLS or signature verification.
    public func validate() throws {
        guard version == ProtocolVersion.current else {
            throw RemoteErrorPayload(code: .versionMismatch)
        }
        guard !isExpired else {
            throw RemoteErrorPayload(code: .pairingApprovalExpired)
        }
        guard !hostName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !serviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              Data(base64Encoded: certificateFingerprint)?.count == 32,
              Data(base64Encoded: pairingSecret)?.count == 16,
              nomadEndpoint?.isValid != false else {
            throw RemoteErrorPayload(code: .protocolMismatch, detail: "QR invalide")
        }
    }

    public static func decode(_ string: String) throws -> PairingQRPayload {
        guard let data = Data(base64Encoded: string) else {
            throw RemoteErrorPayload(code: .protocolMismatch, detail: "QR illisible")
        }
        if let compact = try? RemoteCoding.decoder.decode(CompactPairingQRPayload.self, from: data) {
            let payload = compact.expanded
            try payload.validate()
            return payload
        }
        let payload = try RemoteCoding.decoder.decode(PairingQRPayload.self, from: data)
        try payload.validate()
        return payload
    }
}

/// Représentation dédiée au QR. Le modèle public reste explicite et lisible
/// dans le reste du protocole ; seules les clés transportées par la caméra
/// sont raccourcies.
private struct CompactPairingQRPayload: Codable {
    let version: Int
    let hostName: String
    let hostPlatform: HostPlatform?
    let serviceName: String
    let certificateFingerprint: String
    let pairingSecret: String
    let expiresAt: Date
    let nomadEndpoint: NomadEndpoint?

    enum CodingKeys: String, CodingKey {
        case version = "v"
        case hostName = "m"
        case hostPlatform = "p"
        case serviceName = "s"
        case certificateFingerprint = "f"
        case pairingSecret = "k"
        case expiresAt = "e"
        case nomadEndpoint = "n"
    }

    init(_ payload: PairingQRPayload) {
        version = payload.version
        hostName = payload.hostName
        hostPlatform = payload.hostPlatform
        serviceName = payload.serviceName
        certificateFingerprint = payload.certificateFingerprint
        pairingSecret = payload.pairingSecret
        expiresAt = payload.expiresAt
        nomadEndpoint = payload.nomadEndpoint
    }

    var expanded: PairingQRPayload {
        PairingQRPayload(
            version: version,
            hostName: hostName,
            hostPlatform: hostPlatform ?? .macOS,
            serviceName: serviceName,
            certificateFingerprint: certificateFingerprint,
            pairingSecret: pairingSecret,
            expiresAt: expiresAt,
            nomadEndpoint: nomadEndpoint
        )
    }
}

/// Identité cryptographique d'un iPhone appairé, telle que le Mac la stocke.
public struct ApprovedPeer: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public var name: String
    public let publicKey: Data
    public let pairedAt: Date
    public var lastSeenAt: Date?
    public var isRevoked: Bool
    public let clientPlatform: ClientPlatform

    public init(
        id: String,
        name: String,
        publicKey: Data,
        pairedAt: Date,
        lastSeenAt: Date? = nil,
        isRevoked: Bool = false,
        clientPlatform: ClientPlatform = .iOS
    ) {
        self.id = id
        self.name = name
        self.publicKey = publicKey
        self.pairedAt = pairedAt
        self.lastSeenAt = lastSeenAt
        self.isRevoked = isRevoked
        self.clientPlatform = clientPlatform
    }


    private enum CodingKeys: String, CodingKey {
        case id, name, publicKey, pairedAt, lastSeenAt, isRevoked, clientPlatform
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        publicKey = try container.decode(Data.self, forKey: .publicKey)
        pairedAt = try container.decode(Date.self, forKey: .pairedAt)
        lastSeenAt = try container.decodeIfPresent(Date.self, forKey: .lastSeenAt)
        isRevoked = try container.decodeIfPresent(Bool.self, forKey: .isRevoked) ?? false
        clientPlatform = try container.decodeIfPresent(ClientPlatform.self, forKey: .clientPlatform) ?? .iOS
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(publicKey, forKey: .publicKey)
        try container.encode(pairedAt, forKey: .pairedAt)
        try container.encodeIfPresent(lastSeenAt, forKey: .lastSeenAt)
        try container.encode(isRevoked, forKey: .isRevoked)
        try container.encode(clientPlatform, forKey: .clientPlatform)
    }
}

/// Signature et vérification du défi de connexion.
///
/// Ed25519 plutôt qu'un simple secret partagé : la clé privée ne quitte jamais
/// le Trousseau de l'iPhone, et le Mac n'a donc rien de réutilisable à voler.
public enum ChallengeSigner {
    public static func message(nonce: Data, deviceIdentifier: String, pairingSecret: Data?) -> Data {
        var message = Data()
        message.append(nonce)
        message.append(Data(deviceIdentifier.utf8))
        if let pairingSecret { message.append(pairingSecret) }
        return message
    }

    public static func sign(nonce: Data, deviceIdentifier: String, pairingSecret: Data?, privateKey: Curve25519.Signing.PrivateKey) throws -> Data {
        try privateKey.signature(for: message(nonce: nonce, deviceIdentifier: deviceIdentifier, pairingSecret: pairingSecret))
    }

    public static func verify(
        signature: Data,
        nonce: Data,
        deviceIdentifier: String,
        pairingSecret: Data?,
        publicKeyRepresentation: Data
    ) -> Bool {
        guard let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyRepresentation) else {
            return false
        }
        return publicKey.isValidSignature(
            signature,
            for: message(nonce: nonce, deviceIdentifier: deviceIdentifier, pairingSecret: pairingSecret)
        )
    }
}

public enum SecureRandom {
    public static func bytes(_ count: Int) -> Data {
        var data = Data(count: count)
        _ = data.withUnsafeMutableBytes { pointer in
            SecRandomCopyBytes(kSecRandomDefault, count, pointer.baseAddress!)
        }
        return data
    }
}
