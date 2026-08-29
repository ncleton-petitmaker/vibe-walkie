import ApplicationServices
import AppKit
import RemoteCore

/// Cible capturée au début d'une dictée.
struct CapturedTarget {
    let token: String
    let element: AXUIElement?
    let window: AXUIElement?
    let processIdentifier: pid_t
    let applicationName: String
    let bundleIdentifier: String?
    let windowTitle: String?
    let accessibilityIdentifier: String?
    let role: String?
    let subrole: String?
    let expiresAt: Date

    var isExpired: Bool { Date() >= expiresAt }
}

/// Fige puis revalide l'endroit où le texte sera écrit.
///
/// C'est la garantie centrale du produit. L'utilisateur parle pendant plusieurs
/// secondes ; s'il change de fenêtre entre-temps, ou si le système déplace le
/// focus, écrire « à l'endroit actuel » enverrait une phrase privée dans la
/// mauvaise application. On préfère refuser et laisser le texte sur l'iPhone.
@MainActor
final class TargetTracker {

    private var captured: CapturedTarget?

    /// Capture la cible courante et retourne un jeton à usage unique.
    func capture() throws -> CapturedTarget {
        guard AccessibilityClient.isTrusted else {
            throw RemoteErrorPayload(code: .permissionAccessibilityDenied)
        }
        guard !AccessibilityClient.isSecureInputEnabled else {
            throw RemoteErrorPayload(code: .secureField)
        }

        let element = AccessibilityClient.focusedElement()
        let pid: pid_t
        if let element,
           let elementPID = AccessibilityClient.processIdentifier(of: element) {
            pid = elementPID
        } else if let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            pid = frontmostPID
        } else {
            throw RemoteErrorPayload(code: .noFocusedTarget)
        }
        if let element, AccessibilityClient.isSecure(element) {
            throw RemoteErrorPayload(code: .secureField)
        }

        let app = NSRunningApplication(processIdentifier: pid)
        let window = element.flatMap { AccessibilityClient.element($0, kAXWindowAttribute) }
            ?? AccessibilityClient.focusedWindow(processIdentifier: pid)
        guard window != nil else {
            throw RemoteErrorPayload(code: .noFocusedTarget)
        }
        let target = CapturedTarget(
            token: UUID().uuidString,
            element: element,
            window: window,
            processIdentifier: pid,
            applicationName: app?.localizedName ?? "Application",
            bundleIdentifier: app?.bundleIdentifier,
            windowTitle: window.flatMap { AccessibilityClient.string($0, kAXTitleAttribute) },
            accessibilityIdentifier: element.flatMap { AccessibilityClient.string($0, kAXIdentifierAttribute) },
            role: element.flatMap { AccessibilityClient.string($0, kAXRoleAttribute) },
            subrole: element.flatMap { AccessibilityClient.string($0, kAXSubroleAttribute) },
            expiresAt: Date().addingTimeInterval(VibeRemoteInfo.targetTokenLifetime)
        )
        captured = target
        return target
    }

    /// Revalide le jeton et rend la cible si elle est toujours d'actualité.
    func resolve(token: String) throws -> CapturedTarget {
        guard let target = captured, target.token == token else {
            throw RemoteErrorPayload(code: .targetExpired)
        }
        guard !target.isExpired else {
            captured = nil
            throw RemoteErrorPayload(code: .targetExpired)
        }

        guard !AccessibilityClient.isSecureInputEnabled else {
            throw RemoteErrorPayload(code: .secureField)
        }

        // Repli pour les applications qui exposent leur fenêtre mais aucun
        // élément interne (notamment certaines vues web). La sécurité repose
        // alors sur l'identité exacte de l'application et de la fenêtre.
        guard target.element != nil else {
            guard let currentPID = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
                throw RemoteErrorPayload(code: .noFocusedTarget)
            }
            let currentWindow = AccessibilityClient.focusedWindow(processIdentifier: currentPID)
            let isSameWindow: Bool = {
                guard let capturedWindow = target.window, let currentWindow else { return false }
                return CFEqual(capturedWindow, currentWindow)
            }()
            try TargetMatchPolicy.validateWindowFallback(
                capturedProcessIdentifier: target.processIdentifier,
                currentProcessIdentifier: currentPID,
                isSameWindow: isSameWindow,
                secureInputEnabled: AccessibilityClient.isSecureInputEnabled
            )
            return CapturedTarget(
                token: target.token,
                element: nil,
                window: currentWindow,
                processIdentifier: currentPID,
                applicationName: target.applicationName,
                bundleIdentifier: target.bundleIdentifier,
                windowTitle: target.windowTitle,
                accessibilityIdentifier: nil,
                role: nil,
                subrole: nil,
                expiresAt: target.expiresAt
            )
        }

        guard let current = AccessibilityClient.focusedElement(),
              let currentPID = AccessibilityClient.processIdentifier(of: current) else {
            throw RemoteErrorPayload(code: .targetChanged)
        }
        let isExactElement = CFEqual(current, target.element)
        let currentWindow = AccessibilityClient.element(current, kAXWindowAttribute)
        let isSameWindow: Bool = {
            guard let capturedWindow = target.window, let currentWindow else { return false }
            return CFEqual(capturedWindow, currentWindow)
        }()
        let currentIdentifier = AccessibilityClient.string(current, kAXIdentifierAttribute)
        let currentRole = AccessibilityClient.string(current, kAXRoleAttribute)
        let currentSubrole = AccessibilityClient.string(current, kAXSubroleAttribute)

        // Certains navigateurs recréent l'objet AX d'un champ sans changer le
        // champ visible. Ce repli n'est accepté qu'avec un identifiant AX stable,
        // la même fenêtre et le même rôle. Le PID seul ne suffit jamais.
        try TargetMatchPolicy.validate(
            captured: .init(
                processIdentifier: target.processIdentifier,
                accessibilityIdentifier: target.accessibilityIdentifier,
                role: target.role,
                subrole: target.subrole
            ),
            current: .init(
                processIdentifier: currentPID,
                accessibilityIdentifier: currentIdentifier,
                role: currentRole,
                subrole: currentSubrole
            ),
            isExactElement: isExactElement,
            isSameWindow: isSameWindow,
            currentIsSecure: AccessibilityClient.isSecure(current) || AccessibilityClient.isSecureInputEnabled
        )

        return CapturedTarget(
            token: target.token,
            element: current,
            window: currentWindow,
            processIdentifier: currentPID,
            applicationName: target.applicationName,
            bundleIdentifier: target.bundleIdentifier,
            windowTitle: target.windowTitle,
            accessibilityIdentifier: currentIdentifier,
            role: currentRole,
            subrole: currentSubrole,
            expiresAt: target.expiresAt
        )
    }

    /// Invalide le jeton après usage ou annulation.
    func consume() {
        captured = nil
    }
}
