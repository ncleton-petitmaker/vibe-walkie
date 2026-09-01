import Foundation
import AppKit
import RemoteCore

enum NomadFeatureFlag {
    static var isEnabled: Bool {
        let rawValue = Bundle.main.object(forInfoDictionaryKey: "VibeWalkieNomadModeEnabled")
        if let value = rawValue as? Bool { return value }
        guard let value = rawValue as? String else { return false }
        return ["1", "true", "yes"].contains(value.lowercased())
    }
}

enum TailscaleDetectionState: Equatable, Sendable {
    case idle
    case checking
    case missing
    case stopped
    case ready(NomadEndpoint)
    case failed(String)
}

private struct TailscaleStatusDocument: Decodable {
    struct SelfNode: Decodable {
        let dnsName: String
        let tailscaleIPs: [String]

        enum CodingKeys: String, CodingKey {
            case dnsName = "DNSName"
            case tailscaleIPs = "TailscaleIPs"
        }
    }

    let backendState: String
    let selfNode: SelfNode?

    enum CodingKeys: String, CodingKey {
        case backendState = "BackendState"
        case selfNode = "Self"
    }
}

private enum TailscaleDetectionResult: Sendable {
    case missing
    case stopped
    case ready(NomadEndpoint)
    case failed(String)
}

/// Détecte le client Tailscale déjà installé sans modifier le tailnet, ses ACL
/// ou sa configuration. La commande est lancée directement avec `Process` :
/// aucun shell ni terminal n'est impliqué.
@MainActor
final class TailscaleCoordinator: ObservableObject {
    static let macDownloadURL = URL(string: "https://tailscale.com/download/mac")!
    static let macStandaloneDownloadURL = URL(string: "https://pkgs.tailscale.com/stable/Tailscale-latest-macos.pkg")!
    static let macAppStoreURL = URL(string: "https://apps.apple.com/app/tailscale/id1475387142?mt=12")!
    static let iOSDownloadURL = URL(string: "https://tailscale.com/download/ios")!
    static let iOSAppStoreURL = URL(string: "https://apps.apple.com/app/tailscale/id1470499037")!
    static let macInstallGuideURL = URL(string: "https://tailscale.com/docs/install/mac")!
    static let iOSInstallGuideURL = URL(string: "https://tailscale.com/docs/install/ios")!
    static let whatIsTailscaleURL = URL(string: "https://tailscale.com/docs/concepts/what-is-tailscale")!
    static let devicesURL = URL(string: "https://login.tailscale.com/admin/machines")!
    static let securityURL = URL(string: "https://tailscale.com/security")!
    static let privacyURL = URL(string: "https://tailscale.com/privacy-policy")!
    static let macApplicationURL = URL(fileURLWithPath: "/Applications/Tailscale.app")

    static var isMacApplicationInstalled: Bool {
        FileManager.default.fileExists(atPath: macApplicationURL.path)
    }

    static func openMacApplication() {
        guard isMacApplicationInstalled else {
            NSWorkspace.shared.open(macDownloadURL)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(
            at: macApplicationURL,
            configuration: configuration,
            completionHandler: nil
        )
    }

    @Published private(set) var state: TailscaleDetectionState = .idle
    @Published private(set) var activeEndpoint: NomadEndpoint?
    @Published private(set) var isEnabled: Bool

    private static let enabledKey = "com.nicolascleton.viberemote.nomad.enabled"
    private static let endpointKey = "com.nicolascleton.viberemote.nomad.endpoint"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = NomadFeatureFlag.isEnabled && defaults.bool(forKey: Self.enabledKey)
        if isEnabled,
           let data = defaults.data(forKey: Self.endpointKey),
           let endpoint = try? RemoteCoding.decoder.decode(NomadEndpoint.self, from: data),
           endpoint.isValid {
            activeEndpoint = endpoint
        } else {
            activeEndpoint = nil
        }
    }

    func refresh() async {
        guard NomadFeatureFlag.isEnabled else {
            state = .idle
            activeEndpoint = nil
            return
        }
        state = .checking
        let result = await Task.detached(priority: .userInitiated) {
            Self.detect()
        }.value

        switch result {
        case .missing:
            state = .missing
        case .stopped:
            state = .stopped
        case .failed(let detail):
            state = .failed(detail)
        case .ready(let endpoint):
            state = .ready(endpoint)
            if isEnabled { persist(endpoint) }
        }
    }

    func enableDetectedEndpoint() {
        guard NomadFeatureFlag.isEnabled, case .ready(let endpoint) = state else { return }
        isEnabled = true
        defaults.set(true, forKey: Self.enabledKey)
        persist(endpoint)
    }

    @discardableResult
    func configureManually(magicDNSName: String) -> Bool {
        guard NomadFeatureFlag.isEnabled else { return false }
        let endpoint = NomadEndpoint(magicDNSName: magicDNSName)
        guard endpoint.isValid else { return false }
        state = .ready(endpoint)
        isEnabled = true
        defaults.set(true, forKey: Self.enabledKey)
        persist(endpoint)
        return true
    }

    func disable() {
        isEnabled = false
        activeEndpoint = nil
        defaults.set(false, forKey: Self.enabledKey)
        defaults.removeObject(forKey: Self.endpointKey)
    }

    private func persist(_ endpoint: NomadEndpoint) {
        guard endpoint.isValid else { return }
        activeEndpoint = endpoint
        if let data = try? RemoteCoding.encoder.encode(endpoint) {
            defaults.set(data, forKey: Self.endpointKey)
        }
    }

    /// Exposé au module de tests pour verrouiller le contrat exact du JSON
    /// renvoyé par `tailscale status --json`, sans lancer de processus.
    nonisolated static func endpoint(fromStatusJSON data: Data) throws -> NomadEndpoint? {
        let document = try JSONDecoder().decode(TailscaleStatusDocument.self, from: data)
        guard document.backendState == "Running", let node = document.selfNode else { return nil }
        let ipv4 = node.tailscaleIPs.first(where: NomadEndpoint.isValidTailscaleIPv4)
        let endpoint = NomadEndpoint(magicDNSName: node.dnsName, ipv4Address: ipv4)
        return endpoint.isValid ? endpoint : nil
    }

    nonisolated private static func detect() -> TailscaleDetectionResult {
        let candidates = [
            "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
            "/opt/homebrew/bin/tailscale",
            "/usr/local/bin/tailscale"
        ]
        guard let executable = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            return .missing
        }

        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["status", "--json"]
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let detail = String(decoding: errorData, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return detail.isEmpty ? .stopped : .failed(detail)
            }

            let document = try JSONDecoder().decode(TailscaleStatusDocument.self, from: data)
            guard document.backendState == "Running" else { return .stopped }
            guard document.selfNode != nil else {
                return .failed("Tailscale ne fournit aucune identité pour ce Mac.")
            }
            guard let endpoint = try endpoint(fromStatusJSON: data) else {
                return .failed("Le nom MagicDNS Tailscale est invalide ou indisponible.")
            }
            return .ready(endpoint)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
