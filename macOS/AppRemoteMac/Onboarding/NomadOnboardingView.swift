import SwiftUI
import AppKit
import CoreImage.CIFilterBuiltins
import RemoteCore

/// Assistant volontairement détaillé pour les personnes qui n'ont jamais
/// configuré de VPN. Chaque écran ne demande qu'une seule décision et les
/// vérifications possibles sont effectuées par Vibe Walkie.
struct NomadSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var tailscale: TailscaleCoordinator
    @EnvironmentObject private var server: MacConnectionServer
    @EnvironmentObject private var authority: PairingAuthority

    @State private var step = 0
    @State private var iPhoneConfirmed = false
    @State private var manualMagicDNSName = ""
    @State private var manualError: String?

    private let lastStep = 5

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(.white.opacity(0.08))
            VStack(alignment: .leading, spacing: 0) {
                header
                ScrollView {
                    stepContent
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(28)
                }
                Divider().overlay(.white.opacity(0.08))
                navigation
            }
        }
        .frame(width: 820, height: 650)
        .background(Color.remoteBackground)
        .preferredColorScheme(.dark)
        .task(id: step) {
            guard step == 1 || step == 2 || step == 4 else { return }
            while !Task.isCancelled {
                await refreshTailscale()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("mac.remote.mode.6c2b26c", systemImage: "globe.badge.chevron.backward")
                .font(.title2.bold())
                .foregroundStyle(Color.remoteBlue)

            VStack(alignment: .leading, spacing: 7) {
                sidebarRow(0, title: "Tailscale", icon: "questionmark.circle")
                sidebarRow(1, title: "Mac", icon: "desktopcomputer")
                sidebarRow(2, title: "Tailscale", icon: "person.crop.circle.badge.checkmark")
                sidebarRow(3, title: "iPhone", icon: "iphone")
                sidebarRow(4, title: "Mac + iPhone", icon: "checkmark.icloud")
                sidebarRow(5, title: "Vibe Walkie", icon: "checkmark.shield")
            }
            Spacer()
            Text("Tailscale")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Text("WireGuard®")
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(width: 225, alignment: .topLeading)
        .background(.white.opacity(0.025))
    }

    private func sidebarRow(_ index: Int, title: String, icon: String) -> some View {
        Button {
            guard index <= furthestAvailableStep else { return }
            withAnimation(.easeInOut) { step = index }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(step == index ? Color.remoteBlue : .white.opacity(0.08))
                        .frame(width: 30, height: 30)
                    if index < step {
                        Image(systemName: "checkmark")
                    } else {
                        Image(systemName: icon)
                    }
                }
                .font(.caption.bold())
                VStack(alignment: .leading, spacing: 1) {
                    Text(String(format: "%02d", index + 1))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(title).font(.subheadline.weight(.semibold))
                }
            }
            .foregroundStyle(step == index ? .white : .secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(index > furthestAvailableStep)
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .help("mac.close.711e5f2")
            Spacer()
            Text("\(step + 1) / \(lastStep + 1)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0: explanationStep
        case 1: installMacStep
        case 2: connectMacStep
        case 3: installIPhoneStep
        case 4: verifyDevicesStep
        default: activateStep
        }
    }

    private var explanationStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            localizedStepTitle("mac.remote.mode.6c2b26c", icon: "globe.badge.chevron.backward")
            Text("mac.nomad.discovery.body.f6e2a71")
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 22) {
                deviceBubble("Mac", icon: "desktopcomputer")
                Image(systemName: "lock.fill")
                    .font(.title)
                    .foregroundStyle(.green)
                deviceBubble("iPhone", icon: "iphone")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)

            Text("mac.tailscale.directly.connects.this.iphone.and.mac.vibe.walkie.keeps.1572430")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            linkGrid([
                ("Tailscale · Documentation", "book", TailscaleCoordinator.whatIsTailscaleURL),
                ("Tailscale · Security", "lock.shield", TailscaleCoordinator.securityURL),
                ("Tailscale · Privacy", "hand.raised", TailscaleCoordinator.privacyURL)
            ])
        }
    }

    private var installMacStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            localizedStepTitle("mac.download.tailscale.ae8b630", icon: "arrow.down.app.fill")
            Text("mac.install.the.official.app.connect.this.mac.to.your.tailnet.e0ccba5")
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)

            numberedInstruction(1, text: "mac.download.tailscale.ae8b630")
            linkGrid([
                ("Tailscale.com · macOS", "shippingbox", TailscaleCoordinator.macStandaloneDownloadURL),
                ("Mac App Store", "apple.logo", TailscaleCoordinator.macAppStoreURL),
                ("Tailscale · Installation macOS", "book", TailscaleCoordinator.macInstallGuideURL)
            ])
            detectionCard
        }
    }

    private var connectMacStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            localizedStepTitle("mac.works.with.tailscale.4861eb6", icon: "person.crop.circle.badge.checkmark")
            Text("mac.nomad.tutorial.mac.connect.details.8a01c91")
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button { TailscaleCoordinator.openMacApplication() } label: {
                    Label("Tailscale", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.remoteBlue)
                Link(destination: TailscaleCoordinator.devicesURL) {
                    Label("login.tailscale.com", systemImage: "person.crop.circle")
                }
                .buttonStyle(.bordered)
            }
            detectionCard
        }
    }

    private var installIPhoneStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            literalStepTitle("iPhone + Tailscale", icon: "iphone")
            Text("mac.nomad.tutorial.iphone.details.2bcf5c1")
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 28) {
                if let qr = qrImage(for: TailscaleCoordinator.iOSAppStoreURL.absoluteString) {
                    Image(nsImage: qr)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: 180, height: 180)
                        .accessibilityLabel("Tailscale iPhone App Store QR code")
                }
                Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                    .font(.system(size: 76, weight: .light))
                    .foregroundStyle(Color.remoteBlue)
            }
            linkGrid([
                ("iPhone App Store", "apple.logo", TailscaleCoordinator.iOSAppStoreURL),
                ("Tailscale.com · iPhone", "iphone", TailscaleCoordinator.iOSDownloadURL),
                ("Tailscale · Installation iOS", "book", TailscaleCoordinator.iOSInstallGuideURL)
            ])
        }
    }

    private var verifyDevicesStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            literalStepTitle("Mac + iPhone", icon: "checkmark.icloud.fill")
            Text("mac.nomad.tutorial.verify.details.94f40e2")
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 14) {
                verificationRow(
                    title: "Mac",
                    detail: macDetectionDetail,
                    complete: isTailscaleReady,
                    icon: "desktopcomputer"
                )
                Toggle(isOn: $iPhoneConfirmed) {
                    Label("mac.nomad.tutorial.iphone.confirmed.79ca12e", systemImage: "iphone")
                        .font(.headline)
                }
                .toggleStyle(.checkbox)
            }
            .remoteCard()

            HStack {
                Link(destination: TailscaleCoordinator.devicesURL) {
                    Label("Tailscale · Devices", systemImage: "rectangle.3.group")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.remoteBlue)
                Button("mac.check.again.72912f6") { Task { await refreshTailscale() } }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var activateStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            localizedStepTitle("mac.enable.remote.mode.ed6a27f", icon: "checkmark.shield.fill")
            Text("mac.nomad.tutorial.activate.details.12a49ab")
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)

            if tailscale.isEnabled, let endpoint = tailscale.activeEndpoint {
                VStack(alignment: .leading, spacing: 10) {
                    Label("mac.remote.mode.enabled.66dd627", systemImage: "checkmark.circle.fill")
                        .font(.title2.bold())
                        .foregroundStyle(.green)
                    Text(endpoint.magicDNSName)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
                .remoteCard()
            } else {
                Button("mac.enable.remote.mode.ed6a27f") { enableNomadMode() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(Color.remoteBlue)
                    .disabled(!isTailscaleReady)
            }

            if tailscale.isEnabled, let endpoint = tailscale.activeEndpoint {
                Button("mac.pair.an.iphone.remotely.cee2216") { beginRemotePairing(endpoint) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(Color.remoteBlue)
                Text("mac.pointer.keyboard.and.screen.control.will.be.granted.only.after.fd007ac")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            DisclosureGroup("mac.manual.setup.17eaa7e") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("mac.use.the.full.name.shown.by.tailscale.such.as.mac.c6f500e")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("mac.tailnet.ts.net", text: $manualMagicDNSName)
                    if let manualError { Text(manualError).font(.caption).foregroundStyle(.orange) }
                    Button("mac.use.this.name.9db2787") { configureManually() }
                        .buttonStyle(.bordered)
                }
                .padding(.top, 8)
            }
        }
    }

    private var navigation: some View {
        HStack {
            if step > 0 {
                Button { withAnimation(.easeInOut) { step -= 1 } } label: {
                    Image(systemName: "chevron.left").frame(width: 30, height: 22)
                }
                .buttonStyle(.bordered)
            }
            Spacer()
            if step < lastStep {
                Button {
                    withAnimation(.easeInOut) { step += 1 }
                } label: {
                    Label("mac.continue.0f4bb2d", systemImage: "chevron.right")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.remoteBlue)
                .disabled(!canContinue)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
    }

    private var canContinue: Bool {
        switch step {
        case 1: return TailscaleCoordinator.isMacApplicationInstalled || isTailscaleReady
        case 2: return isTailscaleReady
        case 4: return isTailscaleReady && iPhoneConfirmed
        default: return true
        }
    }

    private var furthestAvailableStep: Int {
        if tailscale.isEnabled { return lastStep }
        if isTailscaleReady { return max(step, 4) }
        return max(step, 2)
    }

    private var isTailscaleReady: Bool {
        if case .ready = tailscale.state { return true }
        return false
    }

    private var macDetectionDetail: String {
        switch tailscale.state {
        case .ready(let endpoint): return endpoint.magicDNSName
        case .checking: return MacL10n.text("mac.checking.tailscale.213070b")
        case .missing: return MacL10n.text("mac.tailscale.is.not.installed.36b3fc8")
        case .stopped: return MacL10n.text("mac.tailscale.is.disconnected.aa3ce54")
        case .failed(let detail): return detail
        case .idle: return MacL10n.text("mac.checking.tailscale.213070b")
        }
    }

    private var detectionCard: some View {
        verificationRow(
            title: "Mac",
            detail: macDetectionDetail,
            complete: isTailscaleReady,
            icon: "desktopcomputer"
        )
        .remoteCard()
    }

    private func localizedStepTitle(_ key: LocalizedStringKey, icon: String) -> some View {
        Label(key, systemImage: icon)
            .font(.title.bold())
            .foregroundStyle(.primary)
    }

    private func literalStepTitle(_ literal: String, icon: String) -> some View {
        Label(literal, systemImage: icon)
            .font(.title.bold())
            .foregroundStyle(.primary)
    }

    private func deviceBubble(_ name: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 36)).foregroundStyle(Color.remoteBlue)
            Text(name).font(.headline)
        }
        .frame(width: 130, height: 100)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
    }

    private func numberedInstruction(_ number: Int, text: LocalizedStringKey) -> some View {
        instructionRow(number, content: Text(text))
    }

    private func instructionRow(_ number: Int, content: Text) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.remoteBlue, in: Circle())
            content.fixedSize(horizontal: false, vertical: true)
        }
    }

    private func verificationRow(title: String, detail: String, complete: Bool, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: complete ? "checkmark.circle.fill" : icon)
                .font(.title2)
                .foregroundStyle(complete ? .green : Color.remoteBlue)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Spacer()
            if !complete { ProgressView().controlSize(.small) }
        }
    }

    private func linkGrid(_ links: [(String, String, URL)]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], spacing: 10) {
            ForEach(links, id: \.2) { title, icon, url in
                Link(destination: url) {
                    Label(title, systemImage: icon)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func refreshTailscale() async {
        await tailscale.refresh()
        server.setNomadEndpoint(tailscale.activeEndpoint)
    }

    private func enableNomadMode() {
        tailscale.enableDetectedEndpoint()
        server.setNomadEndpoint(tailscale.activeEndpoint)
    }

    private func configureManually() {
        if tailscale.configureManually(magicDNSName: manualMagicDNSName) {
            manualError = nil
            server.setNomadEndpoint(tailscale.activeEndpoint)
        } else {
            manualError = MacL10n.text("mac.enter.a.full.magicdns.name.ending.in.ts.net.ab833ea")
        }
    }

    private func beginRemotePairing(_ endpoint: NomadEndpoint) {
        guard let fingerprint = server.certificateFingerprint else { return }
        _ = authority.beginPairing(
            macName: Host.current().localizedName ?? "Mac",
            serviceName: server.serviceName,
            fingerprint: fingerprint,
            nomadEndpoint: endpoint,
            validity: VibeWalkieInfo.nomadPairingWindow
        )
        dismiss()
    }

    private func qrImage(for encoded: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(encoded.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let padded = output.composited(over: CIImage(color: .white).cropped(to: output.extent.insetBy(dx: -4, dy: -4)))
        let scaled = padded.transformed(by: .init(scaleX: 5, y: 5))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
    }
}
