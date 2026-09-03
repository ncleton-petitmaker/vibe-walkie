import SwiftUI
import ServiceManagement
import CoreGraphics
import AppKit
import ScreenCaptureKit
import RemoteCore

enum ScreenCaptureReadiness: Equatable {
    case unavailable
    case relaunchRequired
    case verifying
    case ready
    case failed
}

struct ScreenCaptureAuthorizationState: Equatable {
    private(set) var isGranted: Bool
    private(set) var readiness: ScreenCaptureReadiness

    var requiresRelaunch: Bool { readiness == .relaunchRequired }
    var isReady: Bool { readiness == .ready }

    init(isGrantedAtLaunch: Bool) {
        isGranted = isGrantedAtLaunch
        readiness = isGrantedAtLaunch ? .verifying : .unavailable
    }

    mutating func update(isGranted newValue: Bool) {
        if !isGranted, newValue {
            readiness = .relaunchRequired
        } else if !newValue {
            readiness = .unavailable
        }
        isGranted = newValue
    }

    mutating func beginVerification() {
        guard isGranted, !requiresRelaunch else { return }
        readiness = .verifying
    }

    mutating func completeVerification(succeeded: Bool) {
        guard isGranted, !requiresRelaunch else { return }
        readiness = succeeded ? .ready : .failed
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
    @Published private(set) var screenCaptureReadiness: ScreenCaptureReadiness
    @Published private(set) var hasRequestedScreenCapture: Bool

    private var pollingTask: Task<Void, Never>?
    private var screenCaptureVerificationTask: Task<Void, Never>?
    private var screenCaptureState: ScreenCaptureAuthorizationState
    private var isRelaunchingForScreenCapture = false
    private static let screenCaptureRequestKey = "vibe.walkie.mac.screen-capture.requested"
    private static let screenCaptureGrantPendingKey = "vibe.walkie.mac.screen-capture.grant-pending"
    static let screenCaptureResumeKey = "vibe.walkie.mac.onboarding.resume-after-screen-capture"

    init() {
        let initiallyGranted = CGPreflightScreenCaptureAccess()
        screenCaptureState = ScreenCaptureAuthorizationState(isGrantedAtLaunch: initiallyGranted)
        screenCaptureGranted = initiallyGranted
        screenCaptureReadiness = screenCaptureState.readiness
        hasRequestedScreenCapture = initiallyGranted
            || UserDefaults.standard.bool(forKey: Self.screenCaptureRequestKey)
        if initiallyGranted,
           UserDefaults.standard.bool(forKey: Self.screenCaptureGrantPendingKey) {
            UserDefaults.standard.set(true, forKey: Self.screenCaptureResumeKey)
        }
        refresh()
        if initiallyGranted {
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.verifyScreenCaptureReadiness()
            }
        }
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
        screenCaptureVerificationTask?.cancel()
        screenCaptureVerificationTask = nil
    }

    func refresh() {
        accessibilityGranted = AccessibilityClient.isTrusted
        updateScreenCaptureState(CGPreflightScreenCaptureAccess())
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }

    var screenCaptureReady: Bool {
        screenCaptureState.isReady
    }

    var screenCaptureRequiresRelaunch: Bool {
        screenCaptureState.requiresRelaunch
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
        UserDefaults.standard.set(true, forKey: Self.screenCaptureGrantPendingKey)
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
        UserDefaults.standard.set(true, forKey: Self.screenCaptureGrantPendingKey)
        openScreenCaptureSettingsPage()
    }

    /// ScreenCaptureKit exige une relance après une autorisation accordée
    /// pendant que le processus tourne. Le petit processus indépendant attend
    /// que Vibe Walkie ait libéré son port, puis rouvre exactement la même app.
    func relaunchToApplyScreenCapturePermission() {
        guard screenCaptureRequiresRelaunch, !isRelaunchingForScreenCapture else { return }
        isRelaunchingForScreenCapture = true

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
            UserDefaults.standard.set(true, forKey: Self.screenCaptureResumeKey)
            UserDefaults.standard.synchronize()
            NSApp.terminate(nil)
        } catch {
            isRelaunchingForScreenCapture = false
            // System errors can contain contextual paths or window details.
            // Diagnostics intentionally retain only a stable category.
            NSLog("[VibeWalkie] screen_capture_relaunch_failed")
        }
    }

    /// Après la relance exigée par TCC, une requête ScreenCaptureKit constitue
    /// la preuve que l'autorisation est réellement exploitable. Un simple
    /// `CGPreflightScreenCaptureAccess()` positif ne suffit pas à annoncer que
    /// le retour écran est prêt.
    func verifyScreenCaptureReadiness(force: Bool = false) {
        guard screenCaptureGranted, !screenCaptureRequiresRelaunch else { return }
        if !force, screenCaptureReadiness == .ready { return }
        if !force, screenCaptureReadiness == .verifying,
           screenCaptureVerificationTask != nil { return }

        screenCaptureVerificationTask?.cancel()
        screenCaptureState.beginVerification()
        publishScreenCaptureState()

        screenCaptureVerificationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false,
                    onScreenWindowsOnly: true
                )
                try Task.checkCancellation()
                self.screenCaptureState.completeVerification(
                    succeeded: !content.displays.isEmpty
                )
                if self.screenCaptureState.isReady {
                    UserDefaults.standard.set(false, forKey: Self.screenCaptureGrantPendingKey)
                }
            } catch is CancellationError {
                return
            } catch {
                NSLog("[VibeWalkie] screen_capture_readiness_failed")
                self.screenCaptureState.completeVerification(succeeded: false)
            }
            self.screenCaptureVerificationTask = nil
            self.publishScreenCaptureState()
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
        publishScreenCaptureState()
    }

    private func publishScreenCaptureState() {
        screenCaptureGranted = screenCaptureState.isGranted
        screenCaptureReadiness = screenCaptureState.readiness
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
            NSLog("[VibeWalkie] launch_at_login_update_failed")
        }
        refresh()
    }
}
