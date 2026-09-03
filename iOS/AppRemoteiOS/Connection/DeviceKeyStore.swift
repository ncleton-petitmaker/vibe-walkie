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
    private static let identifierAccount = "device-identifier"
    private static let identifierKey = "com.nicolascleton.viberemote.deviceIdentifier"

    static var deviceIdentifier: String {
        if let data = try? loadRaw(account: identifierAccount),
           let identifier = String(data: data, encoding: .utf8),
           !identifier.isEmpty {
            // Maintient la valeur historique pour les versions antérieures de
            // l'app, sans en faire à nouveau la source de vérité.
            UserDefaults.standard.set(identifier, forKey: identifierKey)
            return identifier
        }

        if let existing = UserDefaults.standard.string(forKey: identifierKey) {
            try? store(Data(existing.utf8), account: identifierAccount)
            return existing
        }

        let generated = UUID().uuidString
        try? store(Data(generated.utf8), account: identifierAccount)
        UserDefaults.standard.set(generated, forKey: identifierKey)
        return generated
    }

    @MainActor static var deviceName: String {
        UIDevice.current.name
    }

    static func loadOrCreatePrivateKey() throws -> Curve25519.Signing.PrivateKey {
        if let data = try loadRaw(account: account) {
            return try Curve25519.Signing.PrivateKey(rawRepresentation: data)
        }
        let key = Curve25519.Signing.PrivateKey()
        try store(key.rawRepresentation, account: account)
        return key
    }

    /// Efface l'identité. Utilisé quand l'utilisateur oublie un Mac : la même
    /// clé ne doit pas resservir après une révocation.
    static func reset() {
        delete(account: account)
        delete(account: identifierAccount)
        UserDefaults.standard.removeObject(forKey: identifierKey)
    }

    private static func loadRaw(account: String) throws -> Data? {
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

    private static func store(_ data: Data, account: String) throws {
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

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: VibeWalkieInfo.keychainService,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Compagnon appairé, mémorisé côté mobile.
/// L'empreinte TLS reste l'identité stable sur macOS comme sur Windows.
struct PairedHost: Codable, Equatable, Identifiable {
    let name: String
    let platform: HostPlatform
    let serviceName: String
    let certificateFingerprint: String
    let nomadEndpoint: NomadEndpoint?

    var id: String { certificateFingerprint }

    init(
        name: String,
        platform: HostPlatform = .macOS,
        serviceName: String,
        certificateFingerprint: String,
        nomadEndpoint: NomadEndpoint? = nil
    ) {
        self.name = name
        self.platform = platform
        self.serviceName = serviceName
        self.certificateFingerprint = certificateFingerprint
        self.nomadEndpoint = nomadEndpoint?.isValid == true ? nomadEndpoint : nil
    }

    private enum CodingKeys: String, CodingKey {
        case name, platform, serviceName, certificateFingerprint, nomadEndpoint
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        platform = try container.decodeIfPresent(HostPlatform.self, forKey: .platform) ?? .macOS
        serviceName = try container.decode(String.self, forKey: .serviceName)
        certificateFingerprint = try container.decode(String.self, forKey: .certificateFingerprint)
        let endpoint = try container.decodeIfPresent(NomadEndpoint.self, forKey: .nomadEndpoint)
        nomadEndpoint = endpoint?.isValid == true ? endpoint : nil
    }
}

/// Registre local des compagnons connus et de la cible sélectionnée.
///
/// La migration depuis le stockage mono-Mac est automatique et atomique : une
/// mise à jour de l'app retrouve donc le compagnon existant sans nouvel
/// appairage. Le registre ne contient aucun secret, seulement les informations
/// publiques déjà transportées par le QR.
struct PairedHostStore {
    struct State: Codable, Equatable {
        var hosts: [PairedHost]
        var selectedHostID: String?

        var selectedHost: PairedHost? {
            guard let selectedHostID else { return hosts.first }
            return hosts.first { $0.id == selectedHostID } ?? hosts.first
        }

        /// Compatibilité de source temporaire pour les tests et extensions V3.
        var macs: [PairedHost] { hosts }

        init(hosts: [PairedHost], selectedHostID: String?) {
            self.hosts = hosts
            self.selectedHostID = selectedHostID
        }

        init(macs: [PairedHost], selectedMacID: String?) {
            self.init(hosts: macs, selectedHostID: selectedMacID)
        }

        private enum CodingKeys: String, CodingKey {
            case hosts, selectedHostID, macs, selectedMacID
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            hosts = try container.decodeIfPresent([PairedHost].self, forKey: .hosts)
                ?? container.decodeIfPresent([PairedHost].self, forKey: .macs)
                ?? []
            selectedHostID = try container.decodeIfPresent(String.self, forKey: .selectedHostID)
                ?? container.decodeIfPresent(String.self, forKey: .selectedMacID)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(hosts, forKey: .hosts)
            try container.encodeIfPresent(selectedHostID, forKey: .selectedHostID)
        }
    }

    private static let registryKey = "com.nicolascleton.viberemote.pairedHosts.v3"
    private static let v2RegistryKey = "com.nicolascleton.viberemote.pairedHosts.v2"
    private static let legacyKey = "com.nicolascleton.viberemote.pairedHost"

    static func load(defaults: UserDefaults = .standard) -> State {
        if let data = defaults.data(forKey: registryKey),
           let stored = try? RemoteCoding.decoder.decode(State.self, from: data) {
            return normalized(stored)
        }

        if let data = defaults.data(forKey: v2RegistryKey),
           let stored = try? RemoteCoding.decoder.decode(State.self, from: data) {
            let migrated = normalized(stored)
            persist(migrated, defaults: defaults)
            defaults.removeObject(forKey: v2RegistryKey)
            return migrated
        }

        guard let data = defaults.data(forKey: legacyKey),
              let legacy = try? RemoteCoding.decoder.decode(PairedHost.self, from: data) else {
            return State(hosts: [], selectedHostID: nil)
        }

        let migrated = State(hosts: [legacy], selectedHostID: legacy.id)
        persist(migrated, defaults: defaults)
        defaults.removeObject(forKey: legacyKey)
        return migrated
    }

    @discardableResult
    static func upsert(
        _ host: PairedHost,
        select: Bool,
        defaults: UserDefaults = .standard
    ) -> State {
        var state = load(defaults: defaults)
        if let index = state.hosts.firstIndex(where: { $0.id == host.id }) {
            state.hosts[index] = host
        } else {
            state.hosts.append(host)
        }
        if select || state.selectedHost == nil {
            state.selectedHostID = host.id
        }
        state = normalized(state)
        persist(state, defaults: defaults)
        return state
    }

    @discardableResult
    static func select(_ id: PairedHost.ID, defaults: UserDefaults = .standard) -> State {
        var state = load(defaults: defaults)
        guard state.hosts.contains(where: { $0.id == id }) else { return state }
        state.selectedHostID = id
        persist(state, defaults: defaults)
        return state
    }

    @discardableResult
    static func remove(_ id: PairedHost.ID, defaults: UserDefaults = .standard) -> State {
        var state = load(defaults: defaults)
        state.hosts.removeAll { $0.id == id }
        if state.selectedHostID == id {
            state.selectedHostID = state.hosts.first?.id
        }
        state = normalized(state)
        persist(state, defaults: defaults)
        return state
    }

    private static func normalized(_ state: State) -> State {
        var seen = Set<String>()
        let hosts = state.hosts.filter { seen.insert($0.id).inserted }
        let selectedHostID = state.selectedHostID.flatMap { id in
            hosts.contains(where: { $0.id == id }) ? id : nil
        } ?? hosts.first?.id
        return State(hosts: hosts, selectedHostID: selectedHostID)
    }

    private static func persist(_ state: State, defaults: UserDefaults) {
        guard let data = try? RemoteCoding.encoder.encode(state) else { return }
        defaults.set(data, forKey: registryKey)
    }
}

/// Alias de source pour les extensions V3 restantes. Les données sur disque
/// restent migrées vers les clés génériques `hosts` / `selectedHostID`.
typealias PairedMac = PairedHost
typealias PairedMacStore = PairedHostStore
