import SwiftUI
import AppKit
import RemoteCore

/// Onboarding court et relançable du compagnon Mac.
///
/// L'Accessibilité est la seule autorisation bloquante. La capture d'écran est
/// présentée ensuite comme amélioration facultative, conformément au principe
/// de divulgation progressive des autorisations macOS.
struct CompanionOnboardingView: View {
    @EnvironmentObject private var permissions: PermissionCoordinator
    @EnvironmentObject private var server: MacConnectionServer
    @EnvironmentObject private var authority: PairingAuthority
    @EnvironmentObject private var tailscale: TailscaleCoordinator
    @Environment(\.dismiss) private var dismiss

    let onFinished: () -> Void
    @State private var step = 0
    @State private var pairedDeviceName: String?
    @State private var completionTask: Task<Void, Never>?
    @AppStorage("vibe.walkie.mac.onboarding.resume-after-screen-capture")
    private var resumeAfterScreenCapture = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(.white.opacity(0.08))
            detail
        }
        .frame(width: 720, height: 500)
        .background(Color(red: 0.035, green: 0.038, blue: 0.042))
        .preferredColorScheme(.dark)
        .onAppear {
            permissions.refresh()
            pairedDeviceName = server.connectedPeerName
            if resumeAfterScreenCapture {
                resumeAfterScreenCapture = false
                step = 2
                beginPairingIfNeeded()
            } else if permissions.accessibilityGranted, step == 0 {
                step = 1
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // TCC peut conserver l'ancienne valeur tant que Vibe Walkie est
            // en arrière-plan dans Réglages Système. Relire dès le retour
            // évite de laisser le bouton suivant désactivé après la coche.
            permissions.refresh()
            relaunchAfterScreenCaptureIfNeeded()
        }
        .onChange(of: permissions.accessibilityGranted) { _, granted in
            if granted, step == 0 { withAnimation(.easeInOut) { step = 1 } }
        }
        .onChange(of: step) { _, newStep in
            if newStep == 2 { beginPairingIfNeeded() }
        }
        .onChange(of: permissions.screenCaptureRequiresRelaunch) { _, requiresRelaunch in
            if requiresRelaunch, NSApp.isActive {
                relaunchAfterScreenCaptureIfNeeded()
            }
        }
        .onChange(of: server.isListening) { _, listening in
            if listening, step == 2 { beginPairingIfNeeded() }
        }
        .onChange(of: server.connectedPeerName) { _, deviceName in
            guard step == 2, let deviceName else { return }
            showPairingSuccess(deviceName)
        }
        .onChange(of: authority.activeSession?.payload.expiresAt) { _, expiresAt in
            if step == 2, expiresAt == nil { beginPairingIfNeeded() }
        }
        .onDisappear {
            completionTask?.cancel()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 62, height: 62)

            Text("mac.welcome.6121f20")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 8) {
                stepRow(0, title: "mac.mac.control.e859c34", icon: "hand.point.up.left.fill")
                stepRow(1, title: "mac.screen.view.b5645a8", icon: "rectangle.inset.filled")
                stepRow(2, title: "mac.pair.an.iphone.44c3c84", icon: "iphone.gen3.radiowaves.left.and.right")
            }

            Spacer()
        }
        .padding(26)
        .frame(width: 225, alignment: .topLeading)
        .background(.white.opacity(0.025))
    }

    private func stepRow(_ index: Int, title: LocalizedStringKey, icon: String) -> some View {
        Button {
            guard index != 1 || permissions.accessibilityGranted else { return }
            guard index != 2 || permissions.accessibilityGranted else { return }
            withAnimation(.easeInOut) { step = index }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(step == index ? Color.blue : .white.opacity(0.08))
                        .frame(width: 28, height: 28)
                    if index == 0, permissions.accessibilityGranted {
                        Image(systemName: "checkmark")
                    } else if index == 1, permissions.screenCaptureGranted {
                        Image(systemName: "checkmark")
                    } else {
                        Image(systemName: icon)
                    }
                }
                .font(.caption.bold())
                Text(title)
                    .font(.subheadline.weight(step == index ? .semibold : .regular))
                    .multilineTextAlignment(.leading)
            }
            .foregroundStyle(step == index ? .white : .secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .help("mac.close.711e5f2")
                Spacer()
                Text("\(step + 1) / 3")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Group {
                switch step {
                case 0: accessibilityStep
                case 1: screenCaptureStep
                default: pairingStep
                }
            }
            .transition(.opacity.combined(with: .move(edge: .trailing)))

            Spacer(minLength: 0)
            navigation
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var accessibilityStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("mac.mac.control.e859c34", systemImage: "checkmark.shield.fill")
                .font(.title.bold())
                .foregroundStyle(permissions.accessibilityGranted ? .green : .white)
            Text("mac.vibe.walkie.needs.accessibility.access.to.read.the.active.field.f7cd725")
                .foregroundStyle(.secondary)
            SettingsPermissionPreview(
                title: "mac.mac.control.e859c34",
                granted: permissions.accessibilityGranted,
                icon: "hand.point.up.left.fill"
            )
            HStack {
                Button("mac.open.settings.239783c") {
                    permissions.guideAccessibilityAccess()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(permissions.accessibilityGranted)

                if !permissions.accessibilityGranted {
                    Button("mac.check.again.72912f6") {
                        permissions.refresh()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var screenCaptureStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("mac.screen.view.b5645a8", systemImage: "rectangle.inset.filled")
                .font(.title.bold())
                .foregroundStyle(permissions.screenCaptureGranted ? .green : .white)
            Text("mac.allow.screen.recording.on.the.mac.then.relaunch.vibe.walkie.634232c")
                .foregroundStyle(.secondary)
            SettingsPermissionPreview(
                title: "mac.screen.view.b5645a8",
                granted: permissions.screenCaptureGranted,
                icon: "rectangle.dashed.badge.record"
            )
            HStack {
                if !permissions.screenCaptureGranted {
                    Button("mac.request.913c40f") {
                        permissions.requestScreenCapture()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }

                if permissions.hasRequestedScreenCapture,
                   !permissions.screenCaptureGranted {
                    Button("mac.open.settings.239783c") {
                        permissions.openScreenCaptureSettings()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var pairingStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("mac.pair.an.iphone.44c3c84", systemImage: "iphone.gen3.radiowaves.left.and.right")
                .font(.title.bold())
            Text("mac.pointer.keyboard.and.screen.control.will.be.granted.only.after.fd007ac")
                .foregroundStyle(.secondary)
            Text("mac.on.iphone.return.to.vibewalkie.app.tap.test.then.scan.this.qr.7ec6a1f")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)

            if let pairedDeviceName {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 76, weight: .semibold))
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, value: pairedDeviceName)
                    Text(MacL10n.format("mac.connected.to.value.421b271", pairedDeviceName))
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
                .transition(.scale.combined(with: .opacity))
            } else if let session = authority.activeSession,
               !session.payload.isExpired,
               let image = PairingQRCodeRenderer.image(for: session.encodedPayload) {
                HStack(spacing: 22) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: 190, height: 190)
                        .accessibilityLabel("mac.pairing.qr.code.77b59f3")
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "iphone.gen3")
                            .font(.system(size: 64, weight: .light))
                            .foregroundStyle(.blue)
                        Text(MacL10n.format("mac.code.value.18fbe57", session.payload.confirmationCode))
                            .font(.system(.title3, design: .monospaced).weight(.semibold))
                            .foregroundStyle(.blue)
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("mac.pairing.qr.code.77b59f3")
                        .foregroundStyle(.secondary)
                    Button("mac.check.again.72912f6") { beginPairingIfNeeded() }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, minHeight: 190)
            }
        }
        .task { beginPairingIfNeeded() }
    }

    private func beginPairingIfNeeded() {
        guard step == 2,
              pairedDeviceName == nil,
              !authority.isPairing,
              authority.pendingApproval == nil,
              server.isListening,
              let fingerprint = server.certificateFingerprint else { return }

        let endpoint = tailscale.isEnabled ? tailscale.activeEndpoint : nil
        _ = authority.beginPairing(
            macName: Host.current().localizedName ?? "Mac",
            serviceName: server.serviceName,
            fingerprint: fingerprint,
            nomadEndpoint: endpoint,
            validity: endpoint == nil ? VibeWalkieInfo.pairingWindow : VibeWalkieInfo.nomadPairingWindow
        )
    }

    private func relaunchAfterScreenCaptureIfNeeded() {
        guard step == 1, permissions.screenCaptureRequiresRelaunch else { return }
        resumeAfterScreenCapture = true
        permissions.relaunchToApplyScreenCapturePermission()
    }

    private func showPairingSuccess(_ deviceName: String) {
        guard pairedDeviceName == nil else { return }
        completionTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            pairedDeviceName = deviceName
        }
        completionTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            onFinished()
        }
    }

    private var navigation: some View {
        HStack {
            if step > 0 {
                Button {
                    withAnimation(.easeInOut) { step -= 1 }
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 28, height: 22)
                }
                .buttonStyle(.bordered)
            }
            Spacer()
            if step < 2 {
                Button {
                    withAnimation(.easeInOut) { step += 1 }
                } label: {
                    Label("mac.continue.0f4bb2d", systemImage: "chevron.right")
                    .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(step == 0 && !permissions.accessibilityGranted)
            }
        }
    }
}

/// Représentation stable des gestes à effectuer dans Réglages Système. Elle
/// reste lisible quand Apple déplace légèrement les panneaux et évite une
/// capture figée dans une seule langue ou une seule version de macOS.
private struct SettingsPermissionPreview: View {
    let title: LocalizedStringKey
    let granted: Bool
    let icon: String

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Label("mac.open.settings.239783c", systemImage: "gear")
                    .font(.caption.weight(.semibold))
                Spacer()
                Label(title, systemImage: icon)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(15)
            .frame(width: 145, alignment: .leading)
            .background(.white.opacity(0.035))

            VStack(alignment: .leading, spacing: 16) {
                Text(title).font(.headline)
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 38, height: 38)
                    Text("mac.vibe.walkie.111e6dd").font(.subheadline.weight(.semibold))
                    Spacer()
                    Toggle("", isOn: .constant(granted))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(.blue)
                        .allowsHitTesting(false)
                }
                .padding(12)
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(18)
        }
        .frame(height: 170)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
    }
}
