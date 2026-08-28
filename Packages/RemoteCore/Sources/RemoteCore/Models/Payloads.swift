import Foundation

// MARK: - Poignée de main

public struct HelloPayload: Codable, Sendable {
    public let deviceName: String
    public let deviceIdentifier: String
    public let appVersion: String
    public let protocolVersion: Int

    public init(deviceName: String, deviceIdentifier: String, appVersion: String, protocolVersion: Int = ProtocolVersion.current) {
        self.deviceName = deviceName
        self.deviceIdentifier = deviceIdentifier
        self.appVersion = appVersion
        self.protocolVersion = protocolVersion
    }
}

/// Défi envoyé par le Mac à chaque connexion.
///
/// Le nonce est régénéré à chaque fois : une signature capturée sur le réseau
/// ne vaut rien à la connexion suivante.
public struct PairingChallengePayload: Codable, Sendable {
    public let nonce: Data
    public let requiresPairingSecret: Bool

    public init(nonce: Data, requiresPairingSecret: Bool) {
        self.nonce = nonce
        self.requiresPairingSecret = requiresPairingSecret
    }
}

public struct PairingResponsePayload: Codable, Sendable {
    public let deviceIdentifier: String
    public let deviceName: String
    public let publicKey: Data
    public let signature: Data
    /// Présent uniquement lors du tout premier appairage, il prouve que
    /// l'utilisateur a physiquement scanné le QR affiché sur le Mac.
    public let pairingSecret: Data?

    public init(deviceIdentifier: String, deviceName: String, publicKey: Data, signature: Data, pairingSecret: Data?) {
        self.deviceIdentifier = deviceIdentifier
        self.deviceName = deviceName
        self.publicKey = publicKey
        self.signature = signature
        self.pairingSecret = pairingSecret
    }
}

/// État envoyé immédiatement après la vérification cryptographique d'un nouvel
/// iPhone. Aucune commande n'est acceptée avant le clic humain sur le Mac.
public struct PairingPendingPayload: Codable, Sendable, Equatable {
    public let requestID: UUID
    public let deviceName: String
    public let confirmationCode: String
    public let expiresAt: Date

    public init(requestID: UUID, deviceName: String, confirmationCode: String, expiresAt: Date) {
        self.requestID = requestID
        self.deviceName = deviceName
        self.confirmationCode = confirmationCode
        self.expiresAt = expiresAt
    }
}

// MARK: - Dictée

public struct RecordingStartedPayload: Codable, Sendable {
    public let locale: String
    public let dictationID: UUID

    public init(locale: String, dictationID: UUID) {
        self.locale = locale
        self.dictationID = dictationID
    }
}

/// Cible figée au moment du contact sur le bouton.
///
/// Sans ce jeton, une phrase dictée pendant un changement de fenêtre pourrait
/// atterrir dans une autre application. Le jeton est à usage unique et expire.
public struct TargetToken: Codable, Sendable, Equatable {
    public let token: String
    public let applicationName: String
    public let bundleIdentifier: String?
    public let windowTitle: String?
    public let expiresAt: Date

    public init(token: String, applicationName: String, bundleIdentifier: String?, windowTitle: String?, expiresAt: Date) {
        self.token = token
        self.applicationName = applicationName
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.expiresAt = expiresAt
    }
}

public struct InsertTextPayload: Codable, Sendable {
    public let targetToken: String
    public let text: String
    public let dictationID: UUID

    public init(targetToken: String, text: String, dictationID: UUID) {
        self.targetToken = targetToken
        self.text = text
        self.dictationID = dictationID
    }
}

/// Méthode réellement employée pour écrire le texte.
///
/// Elle remonte jusqu'à l'iPhone parce qu'un collage et une écriture AX n'ont
/// pas les mêmes garanties : le premier peut être avalé par une application
/// qui lit le presse-papiers en retard.
public enum InsertionMethod: String, Codable, Sendable {
    case axSelectedText = "ax_selected_text"
    case axRange = "ax_range"
    case paste
    case keyboardEvents = "keyboard_events"
}

public struct InsertionResult: Codable, Sendable {
    public let method: InsertionMethod
    public let verified: Bool
    public let pasteboardRestored: Bool?
    public let applicationName: String

    public init(method: InsertionMethod, verified: Bool, pasteboardRestored: Bool?, applicationName: String) {
        self.method = method
        self.verified = verified
        self.pasteboardRestored = pasteboardRestored
        self.applicationName = applicationName
    }
}

public struct CancelPayload: Codable, Sendable {
    public let dictationID: UUID

    public init(dictationID: UUID) {
        self.dictationID = dictationID
    }
}

// MARK: - Applications et fenêtres

public struct RemoteWindow: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let isMain: Bool
    public let isMinimized: Bool

    public init(id: String, title: String, isMain: Bool, isMinimized: Bool) {
        self.id = id
        self.title = title
        self.isMain = isMain
        self.isMinimized = isMinimized
    }
}

public struct RemoteApplication: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let bundleIdentifier: String?
    public let isActive: Bool
    /// PNG redimensionné côté Mac. Plafonné pour ne jamais saturer le canal
    /// de commande avec une icône de plusieurs mégaoctets.
    public let iconPNG: Data?
    public let windows: [RemoteWindow]

    public init(id: String, name: String, bundleIdentifier: String?, isActive: Bool, iconPNG: Data?, windows: [RemoteWindow]) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.isActive = isActive
        self.iconPNG = iconPNG
        self.windows = windows
    }
}

public struct WindowsSnapshotPayload: Codable, Sendable {
    public let applications: [RemoteApplication]
    public let activeApplicationID: String?
    public let capturedAt: Date

    public init(applications: [RemoteApplication], activeApplicationID: String?, capturedAt: Date = Date()) {
        self.applications = applications
        self.activeApplicationID = activeApplicationID
        self.capturedAt = capturedAt
    }
}

public struct ListWindowsPayload: Codable, Sendable {
    public let includeIcons: Bool

    public init(includeIcons: Bool = true) {
        self.includeIcons = includeIcons
    }
}

public struct ActivateWindowPayload: Codable, Sendable {
    public let applicationID: String
    public let windowID: String?

    public init(applicationID: String, windowID: String?) {
        self.applicationID = applicationID
        self.windowID = windowID
    }
}

// MARK: - Clavier

/// Touches autorisées. Une énumération fermée, jamais un keycode brut : le
/// réseau ne doit pas pouvoir composer un raccourci arbitraire sur le Mac.
public enum RemoteKey: String, Codable, Sendable, CaseIterable {
    case enter
    case escape
    case tab
    case backspace
    case delete
    case arrowUp = "arrow_up"
    case arrowDown = "arrow_down"
    case arrowLeft = "arrow_left"
    case arrowRight = "arrow_right"
    case space
}

public struct KeyPressPayload: Codable, Sendable {
    public let key: RemoteKey

    public init(key: RemoteKey) {
        self.key = key
    }
}

public struct KeyboardTextPayload: Codable, Sendable {
    public let text: String
    /// Vrai quand l'utilisateur a explicitement ouvert le clavier distant.
    /// C'est la seule condition qui autorise la frappe dans un champ sécurisé,
    /// et jamais pour la dictée.
    public let userInitiated: Bool

    public init(text: String, userInitiated: Bool) {
        self.text = text
        self.userInitiated = userInitiated
    }
}

// MARK: - Pointeur

public enum PointerButton: String, Codable, Sendable {
    case left
    case right
}

public struct PointerMovePayload: Codable, Sendable {
    public let deltaX: Double
    public let deltaY: Double

    public init(deltaX: Double, deltaY: Double) {
        self.deltaX = deltaX
        self.deltaY = deltaY
    }
}

/// Position dans l'écran diffusé, normalisée entre 0 et 1. Le Mac transforme
/// ces valeurs en coordonnées de son écran principal après les avoir bornées.
public struct PointerAbsolutePayload: Codable, Sendable {
    public let normalizedX: Double
    public let normalizedY: Double

    public init(normalizedX: Double, normalizedY: Double) {
        self.normalizedX = normalizedX
        self.normalizedY = normalizedY
    }
}

public struct PointerClickPayload: Codable, Sendable {
    public let button: PointerButton
    public let clickCount: Int

    public init(button: PointerButton, clickCount: Int) {
        self.button = button
        self.clickCount = clickCount
    }
}

public enum DragPhase: String, Codable, Sendable {
    case began
    case moved
    case ended
}

public struct PointerDragPayload: Codable, Sendable {
    public let phase: DragPhase
    public let deltaX: Double
    public let deltaY: Double

    public init(phase: DragPhase, deltaX: Double, deltaY: Double) {
        self.phase = phase
        self.deltaX = deltaX
        self.deltaY = deltaY
    }
}

public struct ScrollPayload: Codable, Sendable {
    public let deltaX: Double
    public let deltaY: Double

    public init(deltaX: Double, deltaY: Double) {
        self.deltaX = deltaX
        self.deltaY = deltaY
    }
}

// MARK: - Écran distant

public struct ScreenStreamRequestPayload: Codable, Sendable {
    public let enabled: Bool
    public let maxWidth: Int
    public let framesPerSecond: Int
    public let jpegQuality: Double

    public init(enabled: Bool, maxWidth: Int = 1_280, framesPerSecond: Int = 10, jpegQuality: Double = 0.45) {
        self.enabled = enabled
        self.maxWidth = maxWidth
        self.framesPerSecond = framesPerSecond
        self.jpegQuality = jpegQuality
    }
}

public struct ScreenStreamStatusPayload: Codable, Sendable {
    public let isStreaming: Bool
    public let permissionGranted: Bool
    public let detail: String?

    public init(isStreaming: Bool, permissionGranted: Bool, detail: String? = nil) {
        self.isStreaming = isStreaming
        self.permissionGranted = permissionGranted
        self.detail = detail
    }
}

public struct ScreenFramePayload: Codable, Sendable {
    public let jpegData: Data
    public let width: Int
    public let height: Int
    public let capturedAt: Date

    public init(jpegData: Data, width: Int, height: Int, capturedAt: Date = Date()) {
        self.jpegData = jpegData
        self.width = width
        self.height = height
        self.capturedAt = capturedAt
    }
}

// MARK: - Accusés et erreurs

public struct AcknowledgementPayload: Codable, Sendable {
    public let ok: Bool
    public let targetToken: TargetToken?
    public let insertion: InsertionResult?

    public init(ok: Bool, targetToken: TargetToken? = nil, insertion: InsertionResult? = nil) {
        self.ok = ok
        self.targetToken = targetToken
        self.insertion = insertion
    }
}

public struct ConnectionStatusPayload: Codable, Sendable {
    public let accessibilityGranted: Bool
    public let macName: String
    public let companionVersion: String

    public init(
        accessibilityGranted: Bool,
        macName: String,
        companionVersion: String
    ) {
        self.accessibilityGranted = accessibilityGranted
        self.macName = macName
        self.companionVersion = companionVersion
    }
}
