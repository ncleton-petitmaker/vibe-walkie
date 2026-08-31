import Foundation
import CryptoKit
import Security
import UIKit
import RemoteCore

enum NomadFeatureFlag {
    static var isEnabled: Bool {
        let rawValue = Bundle.main.object(forInfoDictionaryKey: "VibeWalkieNomadModeEnabled")
        if let value = rawValue as? Bool { return value }
        guard let value = rawValue as? String else { return false }
        return ["1", "true", "yes"].contains(value.lowercased())
    }
}

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
            kSecAttrService as String: VibeWalkieInfo.keychainService,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func loadRaw() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: VibeWalkieInfo.keychainService,
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
            kSecAttrService as String: VibeWalkieInfo.keychainService,
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
///
/// L'empreinte TLS sert d'identité stable : le nom Bonjour peut changer et
/// deux Macs peuvent avoir le même nom visible, mais ils ne partagent jamais
/// le même certificat.
struct PairedMac: Codable, Equatable, Identifiable {
    let name: String
    let serviceName: String
    let certificateFingerprint: String
    let nomadEndpoint: NomadEndpoint?

    var id: String { certificateFingerprint }

    init(
        name: String,
        serviceName: String,
        certificateFingerprint: String,
        nomadEndpoint: NomadEndpoint? = nil
    ) {
        self.name = name
        self.serviceName = serviceName
        self.certificateFingerprint = certificateFingerprint
        self.nomadEndpoint = nomadEndpoint?.isValid == true ? nomadEndpoint : nil
    }

}

/// Registre local des compagnons connus et de la cible sélectionnée.
///
/// La migration depuis le stockage mono-Mac est automatique et atomique : une
/// mise à jour de l'app retrouve donc le compagnon existant sans nouvel
/// appairage. Le registre ne contient aucun secret, seulement les informations
/// publiques déjà transportées par le QR.
struct PairedMacStore {
    struct State: Codable, Equatable {
        var macs: [PairedMac]
        var selectedMacID: String?

        var selectedMac: PairedMac? {
            guard let selectedMacID else { return macs.first }
            return macs.first { $0.id == selectedMacID } ?? macs.first
        }
    }

    private static let registryKey = "com.nicolascleton.viberemote.pairedMacs.v2"
    private static let legacyKey = "com.nicolascleton.viberemote.pairedMac"

    static func load(defaults: UserDefaults = .standard) -> State {
        if let data = defaults.data(forKey: registryKey),
           let stored = try? RemoteCoding.decoder.decode(State.self, from: data) {
            return normalized(stored)
        }

        guard let data = defaults.data(forKey: legacyKey),
              let legacy = try? RemoteCoding.decoder.decode(PairedMac.self, from: data) else {
            return State(macs: [], selectedMacID: nil)
        }

        let migrated = State(macs: [legacy], selectedMacID: legacy.id)
        persist(migrated, defaults: defaults)
        defaults.removeObject(forKey: legacyKey)
        return migrated
    }

    @discardableResult
    static func upsert(
        _ mac: PairedMac,
        select: Bool,
        defaults: UserDefaults = .standard
    ) -> State {
        var state = load(defaults: defaults)
        if let index = state.macs.firstIndex(where: { $0.id == mac.id }) {
            state.macs[index] = mac
        } else {
            state.macs.append(mac)
        }
        if select || state.selectedMac == nil {
            state.selectedMacID = mac.id
        }
        state = normalized(state)
        persist(state, defaults: defaults)
        return state
    }

    @discardableResult
    static func select(_ id: PairedMac.ID, defaults: UserDefaults = .standard) -> State {
        var state = load(defaults: defaults)
        guard state.macs.contains(where: { $0.id == id }) else { return state }
        state.selectedMacID = id
        persist(state, defaults: defaults)
        return state
    }

    @discardableResult
    static func remove(_ id: PairedMac.ID, defaults: UserDefaults = .standard) -> State {
        var state = load(defaults: defaults)
        state.macs.removeAll { $0.id == id }
        if state.selectedMacID == id {
            state.selectedMacID = state.macs.first?.id
        }
        state = normalized(state)
        persist(state, defaults: defaults)
        return state
    }

    private static func normalized(_ state: State) -> State {
        var seen = Set<String>()
        let macs = state.macs.filter { seen.insert($0.id).inserted }
        let selectedMacID = state.selectedMacID.flatMap { id in
            macs.contains(where: { $0.id == id }) ? id : nil
        } ?? macs.first?.id
        return State(macs: macs, selectedMacID: selectedMacID)
    }

    private static func persist(_ state: State, defaults: UserDefaults) {
        guard let data = try? RemoteCoding.encoder.encode(state) else { return }
        defaults.set(data, forKey: registryKey)
    }
}
