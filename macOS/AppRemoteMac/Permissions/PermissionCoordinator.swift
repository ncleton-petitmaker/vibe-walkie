import SwiftUI
import ServiceManagement
import CoreGraphics
import AppKit
import RemoteCore

/// Suit l'état réel des autorisations.
///
/// L'état est relu périodiquement plutôt que mémorisé : l'utilisateur peut
/// retirer l'Accessibilité dans les Réglages à tout moment, et une interface
/// qui affiche « accordé » alors que les commandes échouent est pire
/// qu'inutile.
@MainActor
final class PermissionCoordinator: ObservableObject {
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var launchesAtLogin = false
    @Published private(set) var screenCaptureGranted = false

    private var pollingTask: Task<Void, Never>?

    init() {
        refresh()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                await MainActor.run { self.refresh() }
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func refresh() {
        accessibilityGranted = AccessibilityClient.isTrusted
        screenCaptureGranted = CGPreflightScreenCaptureAccess()
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }

    func requestAccessibility() {
        AccessibilityClient.requestTrust()
    }

    func openAccessibilitySettings() {
        AccessibilityClient.openAccessibilitySettings()
    }

    func requestScreenCapture() {
        _ = CGRequestScreenCaptureAccess()
        refresh()
    }

    func openScreenCaptureSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Proposé seulement après une première insertion réussie : demander au
    /// premier écran, avant toute valeur démontrée, se solde par un refus.
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("[VibeWalkie] Lancement à la connexion : %@", error.localizedDescription)
        }
        refresh()
    }
}
