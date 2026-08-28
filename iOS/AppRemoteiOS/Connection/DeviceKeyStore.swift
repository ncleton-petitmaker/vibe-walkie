import Foundation
import CryptoKit
import Security
import UIKit
import RemoteCore

/// Identité durable de cet iPhone.
///
/// La clé privée reste dans le Trousseau et ne sort jamais : le Mac ne connaît
/// que la clé publique. Un Mac compromis ne permet donc pas d'usurper le
/// téléphone ailleurs.
enum DeviceKeyStore {

    private static let account = "device-signing-key"
    private static let identifierKey = "com.nicolascleton.viberemote.deviceIdentifier"

    static var deviceIdentifier: String {
        if let existing = UserDefaults.standard.string(forKey: identifierKey) {
            return existing
        }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: identifierKey)
        return generated
    }

    @MainActor static var deviceName: String {
        UIDevice.current.name
    }

    static func loadOrCreatePrivateKey() throws -> Curve25519.Signing.PrivateKey {
        if let data = try loadRaw() {
            return try Curve25519.Signing.PrivateKey(rawRepresentation: data)
        }
        let key = Curve25519.Signing.PrivateKey()
        try store(key.rawRepresentation)
        return key
    }

    /// Efface l'identité. Utilisé quand l'utilisateur oublie un Mac : la même
    /// clé ne doit pas resservir après une révocation.
    static func reset() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: VibeRemoteInfo.keychainService,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func loadRaw() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: VibeRemoteInfo.keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    private static func store(_ data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: VibeRemoteInfo.keychainService,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            // Protégé quand l'iPhone est verrouillé, et non transférable vers
            // un autre appareil par une sauvegarde.
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}

/// Mac appairé, mémorisé côté iPhone.
struct PairedMac: Codable, Equatable {
    let name: String
    let serviceName: String
    let certificateFingerprint: String

    init(
        name: String,
        serviceName: String,
        certificateFingerprint: String
    ) {
        self.name = name
        self.serviceName = serviceName
        self.certificateFingerprint = certificateFingerprint
    }

    private static let key = "com.nicolascleton.viberemote.pairedMac"

    static func load() -> PairedMac? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? RemoteCoding.decoder.decode(PairedMac.self, from: data)
    }

    func save() {
        guard let data = try? RemoteCoding.encoder.encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }

    static func forget() {
        UserDefaults.standard.removeObject(forKey: key)
        DeviceKeyStore.reset()
    }
}
