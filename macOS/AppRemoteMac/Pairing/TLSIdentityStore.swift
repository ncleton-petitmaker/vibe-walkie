import Foundation
import Security
import CryptoKit
import RemoteCore
import X509

/// Identité TLS persistante du Mac.
///
/// Le certificat est auto-signé et c'est assumé : il n'est pas validé par une
/// autorité mais par son empreinte, transmise à l'iPhone hors du réseau via le
/// QR. C'est ce transfert physique qui donne la confiance, pas une chaîne PKI.
enum TLSIdentityStore {

    struct Configuration: Sendable {
        let label: String
        let keyTag: Data

        static let live = Configuration(
            label: "Vibe Remote Local TLS",
            keyTag: Data("com.nicolascleton.viberemote.mac.tls-key".utf8)
        )
    }

    enum StoreError: LocalizedError, Equatable {
        case creationFailed(String)
        case notFound
        case partialState
        case corruptIdentity

        var errorDescription: String? {
            switch self {
            case .creationFailed(let detail):
                return "L’identité de sécurité n’a pas pu être créée : \(detail)"
            case .notFound:
                return "L’identité de sécurité est absente."
            case .partialState:
                return "L’identité de sécurité est incomplète dans le trousseau. Régénérez-la puis appairez à nouveau l’iPhone."
            case .corruptIdentity:
                return "L’identité de sécurité est endommagée. Régénérez-la puis appairez à nouveau l’iPhone."
            }
        }
    }

    /// Récupère l'identité existante ou en crée une nouvelle.
    static func loadOrCreate(configuration: Configuration = .live) throws -> SecIdentity {
        let certificate = try copyCertificate(configuration: configuration)
        let key = try copyPrivateKey(configuration: configuration)

        switch (certificate, key) {
        case (nil, nil):
            return try create(configuration: configuration)
        case (.some(let certificate), .some):
            return try identity(for: certificate)
        default:
            throw StoreError.partialState
        }
    }

    static func load(configuration: Configuration = .live) throws -> SecIdentity {
        guard let certificate = try copyCertificate(configuration: configuration),
              try copyPrivateKey(configuration: configuration) != nil else {
            throw StoreError.notFound
        }
        return try identity(for: certificate)
    }

    /// Supprime l'identité locale et en crée une nouvelle. L'appelant doit
    /// révoquer tous les appairages : leur empreinte TLS n'est plus valable.
    static func regenerate(configuration: Configuration = .live) throws -> SecIdentity {
        try deleteAll(configuration: configuration)
        return try create(configuration: configuration)
    }

    static func deleteAll(configuration: Configuration = .live) throws {
        for query in [certificateQuery(configuration: configuration), privateKeyQuery(configuration: configuration)] {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw StoreError.creationFailed(SecCopyErrorMessageString(status, nil) as String? ?? "erreur \(status)")
            }
        }
    }

    private static func copyCertificate(configuration: Configuration) throws -> SecCertificate? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: configuration.label,
            kSecReturnRef as String: true
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let item else {
            throw StoreError.creationFailed(SecCopyErrorMessageString(status, nil) as String? ?? "erreur \(status)")
        }
        return (item as! SecCertificate)
    }

    private static func copyPrivateKey(configuration: Configuration) throws -> SecKey? {
        var query = privateKeyQuery(configuration: configuration)
        query[kSecReturnRef as String] = true
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let item else {
            throw StoreError.creationFailed(SecCopyErrorMessageString(status, nil) as String? ?? "erreur \(status)")
        }
        return (item as! SecKey)
    }

    private static func identity(for certificate: SecCertificate) throws -> SecIdentity {
        var identity: SecIdentity?
        guard SecIdentityCreateWithCertificate(nil, certificate, &identity) == errSecSuccess,
              let identity else {
            throw StoreError.corruptIdentity
        }
        return identity
    }

    private static func create(configuration: Configuration) throws -> SecIdentity {
        var keyError: Unmanaged<CFError>?
        let keyAttributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrIsPermanent as String: true,
            kSecAttrApplicationTag as String: configuration.keyTag,
            kSecAttrLabel as String: configuration.label
        ]
        guard let secKey = SecKeyCreateRandomKey(keyAttributes as CFDictionary, &keyError) else {
            let detail = keyError?.takeRetainedValue().localizedDescription ?? "clé P-256 indisponible"
            throw StoreError.creationFailed(detail)
        }

        do {
            let privateKey = try Certificate.PrivateKey(secKey)
            let name = try DistinguishedName {
                // Le nom commun fait partie de l'identité de cette installation.
                // C'est aussi le libellé natif utilisé par le trousseau pour le
                // certificat, ce qui évite de récupérer le certificat d'un autre
                // profil de test ou d'une ancienne installation.
                CommonName(configuration.label)
                OrganizationName("Vibe Remote")
            }
            let now = Date()
            let certificate = try Certificate(
                version: .v3,
                serialNumber: .init(),
                publicKey: privateKey.publicKey,
                notValidBefore: now.addingTimeInterval(-300),
                notValidAfter: Calendar(identifier: .gregorian).date(byAdding: .year, value: 20, to: now)!,
                issuer: name,
                subject: name,
                signatureAlgorithm: .ecdsaWithSHA256,
                extensions: try Certificate.Extensions {
                    Critical(BasicConstraints.notCertificateAuthority)
                    Critical(KeyUsage(digitalSignature: true, keyAgreement: true))
                    try ExtendedKeyUsage([.serverAuth])
                    SubjectAlternativeNames([.dnsName("vibe-remote.local")])
                },
                issuerPrivateKey: privateKey
            )
            let secCertificate = try SecCertificate.makeWithCertificate(certificate)
            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassCertificate,
                kSecValueRef as String: secCertificate,
                kSecAttrLabel as String: configuration.label
            ]
            let status = SecItemAdd(addQuery as CFDictionary, nil)
            guard status == errSecSuccess else {
                throw StoreError.creationFailed(SecCopyErrorMessageString(status, nil) as String? ?? "erreur \(status)")
            }
            return try identity(for: secCertificate)
        } catch {
            SecItemDelete(privateKeyQuery(configuration: configuration) as CFDictionary)
            if let storeError = error as? StoreError { throw storeError }
            throw StoreError.creationFailed(error.localizedDescription)
        }
    }

    private static func certificateQuery(configuration: Configuration) -> [String: Any] {
        [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: configuration.label
        ]
    }

    private static func privateKeyQuery(configuration: Configuration) -> [String: Any] {
        [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrApplicationTag as String: configuration.keyTag
        ]
    }

    /// Empreinte SHA-256 du certificat, encodée en base64.
    ///
    /// C'est exactement cette valeur que l'iPhone épingle.
    static func fingerprint(of identity: SecIdentity) throws -> String {
        var certificate: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess,
              let certificate else {
            throw StoreError.notFound
        }
        let data = SecCertificateCopyData(certificate) as Data
        return Data(SHA256.hash(data: data)).base64EncodedString()
    }

    static func fingerprint(ofCertificateData data: Data) -> String {
        Data(SHA256.hash(data: data)).base64EncodedString()
    }
}
