import SwiftUI
import CoreImage.CIFilterBuiltins
import RemoteCore

struct MenuBarView: View {
    private static let qrImageCache = NSCache<NSString, NSImage>()

    @EnvironmentObject private var server: MacConnectionServer
    @EnvironmentObject private var permissions: PermissionCoordinator
    @EnvironmentObject private var authority: PairingAuthority
    @EnvironmentObject private var peers: ApprovedPeersStore
    @EnvironmentObject private var updates: UpdateController
    @State private var showResetConfirmation = false

    var body: some View {
        ScrollView {
            content
        }
        .frame(width: 380)
        .frame(maxHeight: 720)
        .background(Color.remoteBackground)
        .preferredColorScheme(.dark)
        .onChange(of: permissions.accessibilityGranted) { _, _ in beginFirstPairingIfReady() }
        .onChange(of: server.isListening) { _, _ in beginFirstPairingIfReady() }
        .task { beginFirstPairingIfReady() }
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
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
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
            }
            footer
        }
        .padding(18)
    }

    private var welcomeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bienvenue").font(.headline)
            Text("Aucun compte n’est nécessaire. Les commandes restent entre cet iPhone et ce Mac, sur votre réseau local.")
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
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.remoteBlue)
                .frame(width: 42, height: 42)
                .overlay(
                    Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("Vibe Walkie").font(.title3.bold())
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
        if !permissions.accessibilityGranted { return "Accessibilité requise" }
        if let peer = server.connectedPeerName { return "Connecté à \(peer)" }
        return server.isListening ? "En attente d'un iPhone" : "Service arrêté"
    }

    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                permissions.accessibilityGranted ? "Accessibilité accordée" : "Accessibilité refusée",
                systemImage: permissions.accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(permissions.accessibilityGranted ? .green : .orange)

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
                Divider().overlay(.white.opacity(0.08))
                Label(
                    permissions.screenCaptureGranted ? "Retour écran autorisé" : "Retour écran non autorisé",
                    systemImage: permissions.screenCaptureGranted ? "checkmark.circle.fill" : "rectangle.dashed.badge.record"
                )
                .foregroundStyle(permissions.screenCaptureGranted ? .green : .secondary)
                Text("Facultatif. macOS demandera cette autorisation uniquement lorsque vous activerez le retour écran sur l’iPhone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Réglages du retour écran") { permissions.openScreenCaptureSettings() }
                    .buttonStyle(.bordered)
            }
        }
        .remoteCard()
    }

    private func pairingSection(_ session: PairingAuthority.PairingSession) -> some View {
        let payload = session.payload
        return VStack(alignment: .leading, spacing: 8) {
            Text("Appairage en cours").font(.subheadline.bold())
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
            Text("Scannez ce code avec Vibe Walkie sur l'iPhone. Il reste identique pendant 2 minutes.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Annuler l'appairage") { authority.endPairing() }
                .buttonStyle(.bordered)
        }
        .remoteCard()
    }

    private var peersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Appareils autorisés").font(.subheadline.bold())

            if peers.peers.isEmpty {
                Text("Aucun iPhone appairé.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(peers.peers) { peer in
                    ApprovedPeerRow(peer: peer)
                }
            }

            Button("Appairer un iPhone") { beginPairing() }
                .disabled(server.certificateFingerprint == nil)
                .buttonStyle(.borderedProminent)
                .tint(Color.remoteBlue)
            Text("Connexion directe sur votre réseau local, sans compte ni serveur intermédiaire.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if peers.peers.contains(where: { !$0.isRevoked }) {
                Button("Tout révoquer", role: .destructive) {
                    for peer in peers.peers where !peer.isRevoked { server.disconnectPeer(peer.id) }
                    peers.revokeAll()
                }
                .buttonStyle(.borderless)
            }

            if server.lastError != nil {
                Button("Régénérer l’identité de sécurité") { server.regenerateTLSIdentity() }
                    .buttonStyle(.bordered)
            }

            Button("Tout réinitialiser", role: .destructive) { showResetConfirmation = true }
                .buttonStyle(.borderless)
        }
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
        _ = authority.beginPairing(
            macName: Host.current().localizedName ?? "Mac",
            serviceName: server.serviceName,
            fingerprint: fingerprint
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

private extension View {
    func remoteCard() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.remoteCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
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
