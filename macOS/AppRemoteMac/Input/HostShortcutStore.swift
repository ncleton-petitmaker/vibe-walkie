import Foundation
import RemoteCore

/// Les combinaisons matérielles ne quittent jamais le compagnon. Les mobiles
/// ne voient que `HostShortcutReference` et ne peuvent donc pas fabriquer un
/// keycode arbitraire.
@MainActor
final class HostShortcutStore {
    private static let defaultsKey = "hostShortcutDefinitions.v4"

    private let defaults: UserDefaults
    private var definitions: [String: HostShortcutDefinition]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let stored = try? RemoteCoding.decoder.decode([HostShortcutDefinition].self, from: data) {
            definitions = Dictionary(uniqueKeysWithValues: stored.compactMap { definition in
                guard definition.platform == .macOS, definition.isValid, definition.keyCode <= 127 else { return nil }
                return (definition.id, definition)
            })
        } else {
            definitions = [:]
        }
    }

    func register(_ definition: HostShortcutDefinition) -> HostShortcutReference? {
        guard definition.platform == .macOS, definition.isValid, definition.keyCode <= 127 else { return nil }
        definitions[definition.id] = definition
        persist()
        return definition.reference
    }

    func definition(for id: String) -> HostShortcutDefinition? {
        definitions[id]
    }

    var references: [HostShortcutReference] {
        definitions.values.sorted { $0.id < $1.id }.map(\.reference)
    }

    func migrate(_ configuration: ControlConfiguration) -> ControlConfiguration {
        var migrated = configuration
        migrated.buttons = migrated.buttons.map { button in
            var result = button
            if case .macShortcut(let legacy) = result.action,
               let reference = register(legacy.migratedDefinition) {
                result.action = .hostShortcut(reference)
            }
            return result
        }
        migrated.globalButtons = migrated.globalButtons.map { button in
            var result = button
            if case .macShortcut(let legacy) = result.action,
               let reference = register(legacy.migratedDefinition) {
                result.action = .hostShortcut(reference)
            }
            return result
        }
        return migrated
    }

    private func persist() {
        let values = definitions.values.sorted { $0.id < $1.id }
        guard let data = try? RemoteCoding.encoder.encode(values) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
