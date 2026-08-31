import Foundation

public struct EmptyPayload: Codable, Sendable {
    public init() {}
}

/// Emplacements disponibles autour du bouton Push-to-Talk central.
///
/// Les identifiants sont stables car la disposition est partagée par l'iPhone
/// et le compagnon Mac, puis persistée entre les lancements.
public enum ControlZone: String, Codable, Sendable, CaseIterable, Identifiable {
    case upperLeft = "upper_left"
    case lowerLeft = "lower_left"
    case upperRight = "upper_right"
    case lowerRight = "lower_right"
    case bottomLeft = "bottom_left"
    case bottomCenter = "bottom_center"
    case bottomRight = "bottom_right"

    public var id: String { rawValue }
}

public enum ShortcutModifier: String, Codable, Sendable, CaseIterable {
    case command
    case option
    case control
    case shift
    case function
}

/// Raccourci matériel enregistré directement sur le Mac.
///
/// Le keycode est borné et n'est accepté qu'après l'authentification d'un
/// iPhone approuvé. Le libellé est purement visuel : seule la combinaison
/// keycode/modificateurs est exécutée.
public struct MacKeyboardShortcut: Codable, Sendable, Equatable {
    public let keyCode: UInt16
    public let modifiers: [ShortcutModifier]
    public let displayName: String

    public init(keyCode: UInt16, modifiers: [ShortcutModifier], displayName: String) {
        self.keyCode = keyCode
        self.modifiers = Array(Set(modifiers)).sorted { $0.rawValue < $1.rawValue }
        self.displayName = String(displayName.prefix(40))
    }

    public var isValid: Bool {
        keyCode <= 127 && !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public enum ControlButtonAction: Codable, Sendable, Equatable {
    case none
    case standardKey(RemoteKey)
    case macShortcut(MacKeyboardShortcut)
    case showKeyboard
}

public enum ControlButtonIcon: Codable, Sendable, Equatable {
    case system(String)
    case customImage(Data)
}

public struct ControlButtonConfiguration: Codable, Sendable, Equatable, Identifiable {
    public let zone: ControlZone
    public var title: String
    public var icon: ControlButtonIcon
    public var action: ControlButtonAction

    public var id: ControlZone { zone }

    public init(
        zone: ControlZone,
        title: String,
        icon: ControlButtonIcon,
        action: ControlButtonAction
    ) {
        self.zone = zone
        self.title = String(title.prefix(24))
        self.icon = icon
        self.action = action
    }
}

/// Commande disponible dans la bulle « Global » lorsqu'elle n'est pas déjà
/// placée dans l'une des sept zones visibles.
public struct GlobalButtonConfiguration: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var title: String
    public var icon: ControlButtonIcon
    public var action: ControlButtonAction

    public init(id: String, title: String, icon: ControlButtonIcon, action: ControlButtonAction) {
        self.id = String(id.prefix(80))
        self.title = String(title.prefix(24))
        self.icon = icon
        self.action = action
    }
}

public struct ControlConfiguration: Codable, Sendable, Equatable {
    public var buttons: [ControlButtonConfiguration]
    /// Bibliothèque ordonnée des commandes de débordement. Les commandes dont
    /// l'action est déjà visible sont automatiquement masquées de la bulle.
    public var globalButtons: [GlobalButtonConfiguration]
    public var revision: UInt64
    public var updatedAt: Date

    public init(
        buttons: [ControlButtonConfiguration],
        globalButtons: [GlobalButtonConfiguration] = ControlConfiguration.standardGlobalButtons,
        revision: UInt64 = 0,
        updatedAt: Date = Date()
    ) {
        self.buttons = buttons
        self.globalButtons = Self.normalizedGlobalButtons(globalButtons)
        self.revision = revision
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case buttons
        case globalButtons
        case revision
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        buttons = try container.decode([ControlButtonConfiguration].self, forKey: .buttons)
        var storedButtons = try container.decodeIfPresent([GlobalButtonConfiguration].self, forKey: .globalButtons)
            ?? []
        let storedIDs = Set(storedButtons.map(\.id))
        storedButtons.append(contentsOf: Self.standardGlobalButtons.filter { !storedIDs.contains($0.id) })
        globalButtons = Self.normalizedGlobalButtons(storedButtons)
        revision = try container.decodeIfPresent(UInt64.self, forKey: .revision) ?? 0
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date(timeIntervalSince1970: 0)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(buttons, forKey: .buttons)
        try container.encode(globalButtons, forKey: .globalButtons)
        try container.encode(revision, forKey: .revision)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    public var availableGlobalButtons: [GlobalButtonConfiguration] {
        globalButtons.filter { candidate in
            !buttons.contains { $0.action == candidate.action }
        }
    }

    public mutating func setAvailableGlobalButtonOrder(_ order: [GlobalButtonConfiguration]) {
        let available = availableGlobalButtons
        let availableIDs = Set(available.map(\.id))
        var seen = Set<String>()
        var reordered = order.filter { availableIDs.contains($0.id) && seen.insert($0.id).inserted }
        reordered.append(contentsOf: available.filter { seen.insert($0.id).inserted })
        reordered.append(contentsOf: globalButtons.filter { !availableIDs.contains($0.id) })
        globalButtons = Self.normalizedGlobalButtons(reordered)
    }

    public static func normalizedGlobalButtons(_ buttons: [GlobalButtonConfiguration]) -> [GlobalButtonConfiguration] {
        var seen = Set<String>()
        return buttons.prefix(32).filter { !$0.id.isEmpty && seen.insert($0.id).inserted }
    }

    public static let standardGlobalButtons: [GlobalButtonConfiguration] = [
        GlobalButtonConfiguration(id: "standard.next", title: "Suivant", icon: .system("arrow.right.to.line"), action: .standardKey(.nextConversation)),
        GlobalButtonConfiguration(id: "standard.keyboard", title: "Clavier", icon: .system("keyboard"), action: .showKeyboard),
        GlobalButtonConfiguration(id: "standard.switcher", title: "App précédente", icon: .system("arrow.left.arrow.right"), action: .standardKey(.applicationSwitcher)),
        GlobalButtonConfiguration(id: "standard.enter", title: "Entrée", icon: .system("return"), action: .standardKey(.enter)),
        GlobalButtonConfiguration(id: "standard.backspace", title: "Effacer", icon: .system("delete.left"), action: .standardKey(.backspace)),
        GlobalButtonConfiguration(id: "standard.space", title: "Espace", icon: .system("space"), action: .standardKey(.space)),
        GlobalButtonConfiguration(id: "standard.tab", title: "Tabulation", icon: .system("arrow.right.to.line.compact"), action: .standardKey(.tab)),
        GlobalButtonConfiguration(id: "standard.escape", title: "Échap", icon: .system("escape"), action: .standardKey(.escape)),
        GlobalButtonConfiguration(id: "standard.delete", title: "Supprimer", icon: .system("delete.right"), action: .standardKey(.delete)),
        GlobalButtonConfiguration(id: "standard.up", title: "Haut", icon: .system("arrow.up"), action: .standardKey(.arrowUp)),
        GlobalButtonConfiguration(id: "standard.down", title: "Bas", icon: .system("arrow.down"), action: .standardKey(.arrowDown)),
        GlobalButtonConfiguration(id: "standard.left", title: "Gauche", icon: .system("arrow.left"), action: .standardKey(.arrowLeft)),
        GlobalButtonConfiguration(id: "standard.right", title: "Droite", icon: .system("arrow.right"), action: .standardKey(.arrowRight)),
        GlobalButtonConfiguration(id: "standard.copy", title: "Copier", icon: .system("doc.on.doc"), action: .standardKey(.copy)),
        GlobalButtonConfiguration(id: "standard.paste", title: "Coller", icon: .system("doc.on.clipboard"), action: .standardKey(.paste)),
        GlobalButtonConfiguration(id: "standard.cut", title: "Couper", icon: .system("scissors"), action: .standardKey(.cut))
    ]

    public func button(in zone: ControlZone) -> ControlButtonConfiguration {
        buttons.first(where: { $0.zone == zone })
            ?? ControlButtonConfiguration(
                zone: zone,
                title: "Ajouter",
                icon: .system("plus"),
                action: .none
            )
    }

    public mutating func setButton(_ button: ControlButtonConfiguration) {
        buttons.removeAll { $0.zone == button.zone }
        buttons.append(button)
        buttons.sort { lhs, rhs in
            guard let left = ControlZone.allCases.firstIndex(of: lhs.zone),
                  let right = ControlZone.allCases.firstIndex(of: rhs.zone) else { return false }
            return left < right
        }
    }

    public static let standard = ControlConfiguration(buttons: [
        ControlButtonConfiguration(
            zone: .upperLeft,
            title: "Suivant",
            icon: .system("arrow.right.to.line"),
            action: .standardKey(.nextConversation)
        ),
        ControlButtonConfiguration(
            zone: .lowerLeft,
            title: "Clavier",
            icon: .system("keyboard"),
            action: .showKeyboard
        ),
        ControlButtonConfiguration(
            zone: .upperRight,
            title: "App précédente",
            icon: .system("arrow.left.arrow.right"),
            action: .standardKey(.applicationSwitcher)
        ),
        ControlButtonConfiguration(
            zone: .lowerRight,
            title: "Entrée",
            icon: .system("return"),
            action: .standardKey(.enter)
        ),
        ControlButtonConfiguration(
            zone: .bottomLeft,
            title: "Effacer",
            icon: .system("delete.left"),
            action: .standardKey(.backspace)
        ),
        ControlButtonConfiguration(
            zone: .bottomCenter,
            title: "Espace",
            icon: .system("space"),
            action: .standardKey(.space)
        ),
        ControlButtonConfiguration(
            zone: .bottomRight,
            title: "Tabulation",
            icon: .system("arrow.right.to.line.compact"),
            action: .standardKey(.tab)
        )
    ], updatedAt: Date(timeIntervalSince1970: 0))
}

public struct ControlConfigurationPayload: Codable, Sendable {
    public let configuration: ControlConfiguration

    public init(configuration: ControlConfiguration) {
        self.configuration = configuration
    }
}

public struct MacShortcutPressPayload: Codable, Sendable {
    public let shortcut: MacKeyboardShortcut

    public init(shortcut: MacKeyboardShortcut) {
        self.shortcut = shortcut
    }
}
