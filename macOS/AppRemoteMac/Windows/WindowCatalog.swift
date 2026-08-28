import AppKit
import ApplicationServices
import RemoteCore

/// Inventaire des applications et de leurs fenêtres.
///
/// Les titres viennent de l'API d'accessibilité et non de CGWindowList : cette
/// dernière masque les noms de fenêtres sans autorisation d'enregistrement de
/// l'écran, et demander cette permission pour afficher une liste serait
/// disproportionné.
@MainActor
final class WindowCatalog {

    /// Icônes redimensionnées puis mises en cache : sans cela, chaque
    /// rafraîchissement renverrait plusieurs mégaoctets sur le canal de commande.
    private var iconCache: [String: Data] = [:]
    // 40 pt reste net sur l'iPhone et maintient même une trentaine d'icônes
    // sous la limite de 512 Ko du protocole après encodage JSON/base64.
    private static let iconSide: CGFloat = 40

    func snapshot(includeIcons: Bool) -> WindowsSnapshotPayload {
        let running = NSWorkspace.shared.runningApplications.filter {
            !$0.isTerminated
                // Seules les vraies apps visibles dans le Dock intéressent
                // l'utilisateur. Les agents de menu et helpers gonflaient la
                // réponse avec des dizaines d'icônes jusqu'au timeout.
                && $0.activationPolicy == .regular
                && $0.bundleIdentifier != VibeRemoteInfo.macBundleIdentifier
        }
        let frontmost = NSWorkspace.shared.frontmostApplication

        let applications: [RemoteApplication] = running.compactMap { app in
            guard let name = app.localizedName else { return nil }
            let id = String(app.processIdentifier)
            return RemoteApplication(
                id: id,
                name: name,
                bundleIdentifier: app.bundleIdentifier,
                isActive: app.processIdentifier == frontmost?.processIdentifier,
                iconPNG: includeIcons ? icon(for: app) : nil,
                // Sans icônes, l'iPhone effectue un suivi léger de l'app au
                // premier plan. Inutile d'interroger toutes les fenêtres AX
                // quatre-vingts fois par minute pour ce seul libellé.
                windows: includeIcons ? windows(for: app) : []
            )
        }
        .sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive { return lhs.isActive }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        return WindowsSnapshotPayload(
            applications: applications,
            activeApplicationID: frontmost.map { String($0.processIdentifier) }
        )
    }

    /// Active une application et, si demandé, lève une fenêtre précise.
    ///
    /// Le succès n'est annoncé qu'après vérification : macOS peut accepter la
    /// demande sans changer le premier plan, notamment lorsque la fenêtre vit
    /// sur un autre bureau.
    func activate(applicationID: String, windowID: String?) throws {
        guard let pid = pid_t(applicationID),
              let app = NSRunningApplication(processIdentifier: pid) else {
            throw RemoteErrorPayload(code: .applicationNotFound)
        }

        // Depuis macOS 14, `activateIgnoringOtherApps` est sans effet et
        // déprécié. `activateAllWindows` conserve le comportement utile.
        app.activate(options: [.activateAllWindows])

        if let windowID {
            guard AccessibilityClient.isTrusted else {
                throw RemoteErrorPayload(code: .permissionAccessibilityDenied)
            }
            let axApp = AXUIElementCreateApplication(pid)
            let windows = AccessibilityClient.elements(axApp, kAXWindowsAttribute)
            guard let index = Int(windowID), index >= 0, index < windows.count else {
                throw RemoteErrorPayload(code: .windowUnavailableOnSpace)
            }
            let window = windows[index]
            AccessibilityClient.setValue(window, kAXMainAttribute, kCFBooleanTrue)
            AccessibilityClient.perform(window, kAXRaiseAction)
        }

        // Court délai avant vérification : l'activation est asynchrone.
        Thread.sleep(forTimeInterval: 0.15)
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
            throw RemoteErrorPayload(code: .windowUnavailableOnSpace)
        }
    }

    // MARK: - Détail

    private func windows(for app: NSRunningApplication) -> [RemoteWindow] {
        guard AccessibilityClient.isTrusted else { return [] }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        let elements = AccessibilityClient.elements(axApp, kAXWindowsAttribute)

        return elements.enumerated().compactMap { index, window in
            let title = AccessibilityClient.string(window, kAXTitleAttribute) ?? ""
            let minimized = AccessibilityClient.bool(window, kAXMinimizedAttribute) ?? false
            let main = AccessibilityClient.bool(window, kAXMainAttribute) ?? false
            // Une fenêtre sans titre est presque toujours un panneau technique.
            guard !title.isEmpty else { return nil }
            return RemoteWindow(id: String(index), title: title, isMain: main, isMinimized: minimized)
        }
    }

    private func icon(for app: NSRunningApplication) -> Data? {
        let key = app.bundleIdentifier ?? String(app.processIdentifier)
        if let cached = iconCache[key] { return cached }
        guard let icon = app.icon else { return nil }

        let size = NSSize(width: Self.iconSide, height: Self.iconSide)
        let resized = NSImage(size: size)
        resized.lockFocus()
        icon.draw(in: NSRect(origin: .zero, size: size))
        resized.unlockFocus()

        guard let tiff = resized.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        iconCache[key] = png
        return png
    }
}
