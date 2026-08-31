import SwiftUI
import CoreImage.CIFilterBuiltins
import RemoteCore

struct MenuBarView: View {
    private static let qrImageCache = NSCache<NSString, NSImage>()

    @EnvironmentObject private var server: MacConnectionServer
    @EnvironmentObject private var permissions: PermissionCoordinator
    @EnvironmentObject private var authority: PairingAuthority
    @EnvironmentObject private var peers: ApprovedPeersStore
    @EnvironmentObject private var tailscale: TailscaleCoordinator
    @EnvironmentObject private var updates: UpdateController
    @State private var showResetConfirmation = false
    @State private var showControlConfigurator = false
    @State private var showNomadSetup = false

    var body: some View {
        ScrollView {
            content
        }
        .frame(width: 340)
        .frame(maxHeight: 600)
        .background(Color.remoteBackground)
        .preferredColorScheme(.dark)
        .onChange(of: permissions.accessibilityGranted) { _, _ in beginFirstPairingIfReady() }
        .onChange(of: server.isListening) { _, _ in beginFirstPairingIfReady() }
        .task {
            beginFirstPairingIfReady()
            if NomadFeatureFlag.isEnabled {
                await tailscale.refresh()
                server.setNomadEndpoint(tailscale.activeEndpoint)
            }
        }
        .onChange(of: tailscale.activeEndpoint) { _, endpoint in
            server.setNomadEndpoint(endpoint)
        }
        .confirmationDialog(
            "Réinitialiser Vibe Walkie ?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Réinitialiser les appairages et l’identité", role: .destructive) {
                server.resetEverything()
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Tous les iPhone devront être appairés à nouveau.")
        }
        .sheet(isPresented: $showControlConfigurator) {
            MacControlConfiguratorView()
                .environmentObject(server)
        }
        .sheet(isPresented: $showNomadSetup) {
            NomadSetupView()
                .environmentObject(tailscale)
                .environmentObject(server)
                .environmentObject(authority)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if !InstallationLocation.isSuitable {
                installationSection
            } else {
                if peers.peers.allSatisfy(\.isRevoked) { welcomeSection }
                permissionSection

                if let pending = authority.pendingApproval {
                    approvalSection(pending)
                } else if let session = authority.activeSession, !session.payload.isExpired {
                    pairingSection(session)
                }

                peersSection
                if NomadFeatureFlag.isEnabled { nomadSection }
                controlsSection
            }
            footer
        }
        .padding(14)
    }

    private var welcomeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bienvenue").font(.headline)
            Text(
                NomadFeatureFlag.isEnabled
                    ? "Aucun compte Vibe Walkie n’est nécessaire. Les commandes restent entre cet iPhone et ce Mac, en local ou via votre réseau Tailscale facultatif."
                    : "Aucun compte n’est nécessaire. Les commandes restent entre cet iPhone et ce Mac sur votre réseau local."
            )
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .remoteCard()
    }

    private var installationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Déplacez Vibe Walkie dans Applications", systemImage: "arrow.down.app.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("L’app a été ouverte depuis le disque d’installation. Glissez-la vers le raccourci Applications, puis ouvrez la copie installée.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Ouvrir Applications") { InstallationLocation.openApplicationsFolder() }
                .buttonStyle(.borderedProminent)
                .tint(Color.remoteBlue)
        }
        .remoteCard()
    }

    private func approvalSection(_ pending: PairingAuthority.PendingApproval) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Autoriser cet iPhone ?", systemImage: "iphone.badge.checkmark")
                .font(.headline)
            Text(pending.peer.name)
                .font(.title3.weight(.semibold))
            Text("Code \(pending.confirmationCode)")
                .font(.system(.title2, design: .monospaced).weight(.bold))
                .foregroundStyle(Color.remoteBlue)
            Text("Le contrôle du pointeur, du clavier et de l’écran ne sera accordé qu’après votre confirmation.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Autoriser") { server.approvePairing(pending.id) }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.remoteBlue)
                Button("Refuser", role: .destructive) { server.denyPairing(pending.id) }
                    .buttonStyle(.bordered)
            }
        }
        .remoteCard()
    }

    private var header: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.remoteBlue.gradient)
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("Vibe Walkie").font(.headline)
                HStack(spacing: 6) {
                    Circle().fill(statusColor).frame(width: 7, height: 7)
                    Text(statusText)
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.56))
            }
            Spacer()
        }
    }

    private var statusColor: Color {
        if !permissions.accessibilityGranted { return .orange }
        if server.connectedPeerName != nil { return .green }
        return server.isListening ? .blue : .red
    }

    private var statusText: String {
        if let error = server.lastError { return error }
        if !permissions.accessibilityGranted { return MacL10n.text("Accessibilité requise") }
        if let peer = server.connectedPeerName { return MacL10n.text("Connecté à \(peer)") }
        return server.isListening ? MacL10n.text("En attente d'un iPhone") : MacL10n.text("Service arrêté")
    }

    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(
                    "Contrôle du Mac",
                    systemImage: permissions.accessibilityGranted ? "checkmark.shield.fill" : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(permissions.accessibilityGranted ? .green : .orange)
                Spacer()
                Text(permissions.accessibilityGranted ? "Prêt" : "Requis")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if !permissions.accessibilityGranted {
                Text("Vibe Walkie a besoin de l'Accessibilité pour lire le champ actif, y écrire votre dictée et changer d'application.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Demander") { permissions.requestAccessibility() }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.remoteBlue)
                    Button("Ouvrir les Réglages") { permissions.openAccessibilitySettings() }
                        .buttonStyle(.bordered)
                }
            }

            if peers.peers.contains(where: { !$0.isRevoked }) {
                HStack {
                    Label(
                        "Retour écran",
                        systemImage: permissions.screenCaptureGranted ? "checkmark.rectangle.fill" : "rectangle.dashed.badge.record"
                    )
                    .foregroundStyle(permissions.screenCaptureGranted ? .green : .secondary)
                    Spacer()
                    Button {
                        permissions.openScreenCaptureSettings()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(.borderless)
                    .help("Réglages du retour écran")
                }
            }
        }
        .remoteCard()
    }

    private func pairingSection(_ session: PairingAuthority.PairingSession) -> some View {
        let payload = session.payload
        let isNomad = payload.nomadEndpoint != nil
        return VStack(alignment: .leading, spacing: 8) {
            Text(isNomad ? "Appairage Nomade" : "Appairage en cours").font(.subheadline.bold())
            if let image = qrImage(for: session.encodedPayload) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("QR code d'appairage")
            }
            Text("Code : \(payload.confirmationCode)")
                .font(.system(.title3, design: .monospaced))
                .foregroundStyle(Color.remoteBlue)
                .frame(maxWidth: .infinity)
            Text(
                isNomad
                    ? "Partagez le QR ou le code avec l’iPhone. Une personne devra confirmer ici dans les 60 secondes suivant sa connexion."
                    : "Scannez ce code avec Vibe Walkie sur l'iPhone. Il reste identique pendant 2 minutes."
            )
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                if isNomad {
                    Button("Copier le code") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(session.encodedPayload, forType: .string)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.remoteBlue)
                }
                Button("Annuler") { authority.endPairing() }
                    .buttonStyle(.bordered)
            }
        }
        .remoteCard()
    }

    private var peersSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("iPhone autorisés").font(.subheadline.bold())
                Spacer()
                Button {
                    beginPairing()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .disabled(server.certificateFingerprint == nil)
                .help("Appairer un iPhone")
            }

            if peers.peers.isEmpty {
                Text("Aucun iPhone appairé.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(peers.peers) { peer in
                    ApprovedPeerRow(peer: peer)
                }
            }

            if peers.peers.contains(where: { !$0.isRevoked }) {
                HStack {
                    Label(
                        tailscale.isEnabled ? "Connexion locale ou Nomade chiffrée" : "Connexion locale chiffrée",
                        systemImage: "lock.fill"
                    )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        Button("Tout révoquer", role: .destructive) {
                            for peer in peers.peers where !peer.isRevoked { server.disconnectPeer(peer.id) }
                            peers.revokeAll()
                        }
                        Button("Tout réinitialiser", role: .destructive) { showResetConfirmation = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }

            if server.lastError != nil {
                Button("Régénérer l’identité de sécurité") { server.regenerateTLSIdentity() }
                    .buttonStyle(.bordered)
            }

        }
        .remoteCard()
    }

    private var controlsSection: some View {
        Button {
            showControlConfigurator = true
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Label("Commandes de l’iPhone", systemImage: "rectangle.3.group.fill")
                        .font(.subheadline.bold())
                    Spacer()
                    Text("Modifier")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.remoteBlue)
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(Color.remoteBlue)
                }
                MacControlMiniPreview(configuration: server.controlConfiguration)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .remoteCard()
    }

    private var nomadSection: some View {
        Button {
            showNomadSetup = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tailscale.isEnabled ? "globe.badge.chevron.backward" : "globe")
                    .foregroundStyle(tailscale.isEnabled ? .green : Color.remoteBlue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mode Nomade").font(.subheadline.bold())
                    Text(tailscale.isEnabled ? "Compatible avec Tailscale · Activé" : "Contrôlez ce Mac hors du Wi‑Fi local")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(Color.remoteBlue)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .remoteCard()
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if server.hasCompletedFirstCommand {
                Toggle("Lancer à la connexion", isOn: Binding(
                    get: { permissions.launchesAtLogin },
                    set: { permissions.setLaunchAtLogin($0) }
                ))
                .toggleStyle(.checkbox)
                Text("Facultatif : gardez le compagnon prêt après l’ouverture de session.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text(Bundle.main.appVersion).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("Mises à jour…") { updates.checkForUpdates() }
                    .disabled(!updates.canCheckForUpdates)
                Button("Quitter") { NSApplication.shared.terminate(nil) }
            }
        }
    }

    private struct ApprovedPeerRow: View {
        let peer: ApprovedPeer
        @EnvironmentObject private var peers: ApprovedPeersStore
        @EnvironmentObject private var server: MacConnectionServer
        @State private var name: String

        init(peer: ApprovedPeer) {
            self.peer = peer
            _name = State(initialValue: peer.name)
        }

        var body: some View {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    TextField("Nom de l’iPhone", text: $name)
                        .textFieldStyle(.plain)
                        .onSubmit { peers.rename(peer.id, to: name) }
                    Text(peer.isRevoked ? "Révoqué" : "Autorisé")
                        .font(.caption2)
                        .foregroundStyle(peer.isRevoked ? .red : .secondary)
                }
                Spacer()
                if !peer.isRevoked {
                    Button("Révoquer") {
                        peers.revoke(peer.id)
                        server.disconnectPeer(peer.id)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private func beginPairing() {
        guard let fingerprint = server.certificateFingerprint else { return }
        let endpoint = tailscale.isEnabled ? tailscale.activeEndpoint : nil
        _ = authority.beginPairing(
            macName: Host.current().localizedName ?? "Mac",
            serviceName: server.serviceName,
            fingerprint: fingerprint,
            nomadEndpoint: endpoint,
            validity: endpoint == nil ? VibeWalkieInfo.pairingWindow : VibeWalkieInfo.nomadPairingWindow
        )
    }

    /// Le premier QR apparaît dès que l'identité TLS, le service local et
    /// l'autorisation Accessibilité sont prêts. Les lancements suivants ne
    /// rouvrent jamais l'appairage sans action de l'utilisateur.
    private func beginFirstPairingIfReady() {
        guard permissions.accessibilityGranted,
              server.isListening,
              peers.peers.isEmpty,
              !authority.isPairing,
              authority.pendingApproval == nil else { return }
        beginPairing()
    }

    private func qrImage(for encoded: String) -> NSImage? {
        guard !encoded.isEmpty else { return nil }
        let cacheKey = encoded as NSString
        if let cached = Self.qrImageCache.object(forKey: cacheKey) { return cached }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(encoded.utf8)
        // Le niveau L suffit pour un écran propre et réduit la densité du QR.
        filter.correctionLevel = "L"
        guard let output = filter.outputImage else { return nil }

        // Quatre modules blancs constituent la « quiet zone » recommandée.
        // Trois points par module donnent des arêtes nettes sur écran Retina.
        let quietZone: CGFloat = 4
        let extent = output.extent.integral
        let paddedExtent = extent.insetBy(dx: -quietZone, dy: -quietZone)
        let background = CIImage(color: CIColor.white).cropped(to: paddedExtent)
        let padded = output.composited(over: background)
        let moduleScale: CGFloat = 3
        let scaled = padded.transformed(by: CGAffineTransform(scaleX: moduleScale, y: moduleScale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        let image = NSImage(
            cgImage: cgImage,
            size: NSSize(width: scaled.extent.width, height: scaled.extent.height)
        )
        Self.qrImageCache.setObject(image, forKey: cacheKey)
        return image
    }
}

private struct NomadSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var tailscale: TailscaleCoordinator
    @EnvironmentObject private var server: MacConnectionServer
    @EnvironmentObject private var authority: PairingAuthority

    @State private var manualMagicDNSName = ""
    @State private var manualError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Mode Nomade").font(.title2.bold())
                    Text("Compatible avec Tailscale")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Fermer") { dismiss() }
            }

            Text("Tailscale relie directement cet iPhone et ce Mac. Vibe Walkie conserve son propre chiffrement TLS et son appairage.")
                .font(.callout)
                .foregroundStyle(.secondary)

            statusCard

            if tailscale.isEnabled, let endpoint = tailscale.activeEndpoint {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Mode Nomade activé", systemImage: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                        .font(.headline)
                    Text(endpoint.magicDNSName)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    Button("Appairer un iPhone à distance") {
                        beginRemotePairing(endpoint)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.remoteBlue)
                    Button("Désactiver le Mode Nomade", role: .destructive) {
                        tailscale.disable()
                        server.setNomadEndpoint(nil)
                    }
                    .buttonStyle(.bordered)
                }
                .remoteCard()
            }

            DisclosureGroup("Configuration manuelle") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Utilisez le nom complet affiché par Tailscale, par exemple mac.exemple.ts.net.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("mac.tailnet.ts.net", text: $manualMagicDNSName)
                    if let manualError {
                        Text(manualError).font(.caption).foregroundStyle(.orange)
                    }
                    Button("Utiliser ce nom") {
                        if tailscale.configureManually(magicDNSName: manualMagicDNSName) {
                            manualError = nil
                            server.setNomadEndpoint(tailscale.activeEndpoint)
                        } else {
                            manualError = MacL10n.text("Saisissez un nom MagicDNS complet se terminant par .ts.net.")
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 8)
            }

            Spacer()
        }
        .padding(22)
        .frame(width: 470, height: 530)
        .background(Color.remoteBackground)
        .preferredColorScheme(.dark)
        .task {
            await tailscale.refresh()
            server.setNomadEndpoint(tailscale.activeEndpoint)
        }
    }

    @ViewBuilder
    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch tailscale.state {
            case .idle, .checking:
                HStack { ProgressView(); Text("Vérification de Tailscale…") }
            case .missing:
                Label("Tailscale n’est pas installé", systemImage: "arrow.down.app")
                    .font(.headline)
                Text("Installez l’application officielle, connectez ce Mac à votre tailnet, puis relancez la vérification.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Télécharger Tailscale") {
                    NSWorkspace.shared.open(TailscaleCoordinator.macDownloadURL)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.remoteBlue)
            case .stopped:
                Label("Tailscale est déconnecté", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text("Ouvrez Tailscale et connectez ce Mac, puis réessayez.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .failed(let detail):
                Label("Tailscale est indisponible", systemImage: "xmark.octagon.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            case .ready(let endpoint):
                Label("Tailscale est prêt", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                Text(endpoint.magicDNSName)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                if !tailscale.isEnabled {
                    Button("Activer le Mode Nomade") {
                        tailscale.enableDetectedEndpoint()
                        server.setNomadEndpoint(tailscale.activeEndpoint)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.remoteBlue)
                }
            }

            Button("Vérifier à nouveau") {
                Task {
                    await tailscale.refresh()
                    server.setNomadEndpoint(tailscale.activeEndpoint)
                }
            }
            .buttonStyle(.bordered)
        }
        .remoteCard()
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
}

private struct MacControlMiniPreview: View {
    let configuration: ControlConfiguration

    var body: some View {
        HStack(spacing: 5) {
            ForEach(ControlZone.allCases) { zone in
                let button = configuration.button(in: zone)
                MenuBarControlIcon(icon: button.icon)
                    .frame(width: 15, height: 15)
                    .frame(maxWidth: .infinity, minHeight: 31)
                    .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
                    .help(button.title)
            }
            Image(systemName: "circle.grid.2x2.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.remoteBlue)
                .frame(maxWidth: .infinity, minHeight: 31)
                .background(Color.remoteBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .help("Global")
        }
    }
}

private struct MenuBarControlIcon: View {
    let icon: ControlButtonIcon

    var body: some View {
        switch icon {
        case .system(let name):
            Image(systemName: name)
                .resizable()
                .scaledToFit()
        case .customImage(let data):
            if let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                Image(systemName: "photo")
                    .resizable()
                    .scaledToFit()
            }
        }
    }
}

private extension View {
    func remoteCard() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(11)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.remoteCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(.white.opacity(0.07), lineWidth: 1)
                    )
            )
    }
}

private extension Color {
    static let remoteBackground = Color(red: 0.035, green: 0.038, blue: 0.042)
    static let remoteCard = Color(red: 0.12, green: 0.125, blue: 0.13)
    static let remoteBlue = Color(red: 0.02, green: 0.56, blue: 0.98)
}
