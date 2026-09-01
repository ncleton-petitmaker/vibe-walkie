import SwiftUI
import ServiceManagement
import CoreGraphics
import AppKit
import RemoteCore

struct ScreenCaptureAuthorizationState: Equatable {
    private(set) var isGranted: Bool
    private(set) var requiresRelaunch = false

    init(isGrantedAtLaunch: Bool) {
        isGranted = isGrantedAtLaunch
    }

    mutating func update(isGranted newValue: Bool) {
        if !isGranted, newValue {
            requiresRelaunch = true
        } else if !newValue {
            requiresRelaunch = false
        }
        isGranted = newValue
    }
}

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
    @Published private(set) var screenCaptureGranted: Bool
    @Published private(set) var screenCaptureRequiresRelaunch = false
    @Published private(set) var hasRequestedScreenCapture: Bool

    private var pollingTask: Task<Void, Never>?
    private var screenCaptureState: ScreenCaptureAuthorizationState
    private static let screenCaptureRequestKey = "vibe.walkie.mac.screen-capture.requested"

    init() {
        let initiallyGranted = CGPreflightScreenCaptureAccess()
        screenCaptureState = ScreenCaptureAuthorizationState(isGrantedAtLaunch: initiallyGranted)
        screenCaptureGranted = initiallyGranted
        hasRequestedScreenCapture = initiallyGranted
            || UserDefaults.standard.bool(forKey: Self.screenCaptureRequestKey)
        refresh()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval: Duration = self.hasRequestedScreenCapture && !self.screenCaptureGranted
                    ? .milliseconds(500)
                    : .seconds(2)
                try? await Task.sleep(for: interval)
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
        updateScreenCaptureState(CGPreflightScreenCaptureAccess())
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }

    var screenCaptureReady: Bool {
        screenCaptureGranted && !screenCaptureRequiresRelaunch
    }

    func requestAccessibility() {
        AccessibilityClient.requestTrust()
    }

    /// Explique d'abord l'usage dans l'onboarding, puis déclenche la demande
    /// système et place l'utilisateur directement sur la bonne sous-page. Le
    /// léger délai laisse macOS enregistrer l'app avant d'afficher sa ligne.
    func guideAccessibilityAccess() {
        AccessibilityClient.requestTrust()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            AccessibilityClient.openAccessibilitySettings()
        }
    }

    func openAccessibilitySettings() {
        AccessibilityClient.openAccessibilitySettings()
    }

    func requestScreenCapture() {
        NSApp.activate(ignoringOtherApps: true)
        hasRequestedScreenCapture = true
        UserDefaults.standard.set(true, forKey: Self.screenCaptureRequestKey)
        guard !CGPreflightScreenCaptureAccess() else {
            refresh()
            return
        }
        let granted = CGRequestScreenCaptureAccess()
        updateScreenCaptureState(granted || CGPreflightScreenCaptureAccess())
    }

    /// Enregistre d'abord Vibe Walkie auprès de TCC. L'ouverture des Réglages
    /// reste une action séparée et explicite : les superposer à la demande
    /// native place la fenêtre utile derrière les Réglages Système.
    func guideScreenCaptureAccess() {
        requestScreenCapture()
    }

    func openScreenCaptureSettings() {
        openScreenCaptureSettingsPage()
    }

    /// ScreenCaptureKit exige une relance après une autorisation accordée
    /// pendant que le processus tourne. Le petit processus indépendant attend
    /// que Vibe Walkie ait libéré son port, puis rouvre exactement la même app.
    func relaunchToApplyScreenCapturePermission() {
        guard screenCaptureRequiresRelaunch else { return }

        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = [
            "-c",
            "sleep 0.8; exec /usr/bin/open -n \"$1\"",
            "vibe-walkie-relaunch",
            Bundle.main.bundleURL.path
        ]

        do {
            try helper.run()
            NSApp.terminate(nil)
        } catch {
            NSLog("[VibeWalkie] Relance après autorisation écran impossible : %@", error.localizedDescription)
        }
    }

    private func openScreenCaptureSettingsPage() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.apple.systempreferences"
            ).first?.activate(options: [.activateAllWindows])
        }
    }

    private func updateScreenCaptureState(_ granted: Bool) {
        screenCaptureState.update(isGranted: granted)
        screenCaptureGranted = screenCaptureState.isGranted
        screenCaptureRequiresRelaunch = screenCaptureState.requiresRelaunch
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
