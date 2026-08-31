import SwiftUI
import RemoteCore

/// Sélecteur court accessible depuis le bouton en haut à gauche de la
/// télécommande. Il ferme la feuille dès qu'une nouvelle cible est choisie.
struct MacSwitcherView: View {
    @EnvironmentObject private var client: MacConnectionClient
    @Environment(\.dismiss) private var dismiss
    @State private var showScanner = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(client.pairedMacs) { mac in
                        Button {
                            guard mac.id != client.selectedMacID else {
                                dismiss()
                                return
                            }
                            HapticFeedback.shared.tick()
                            client.selectMac(mac.id)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "desktopcomputer")
                                    .font(.title3)
                                    .foregroundStyle(
                                        mac.id == client.selectedMacID ? Color.remoteBlue : .secondary
                                    )
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(mac.name)
                                        .foregroundStyle(.primary)
                                    Text(mac.id == client.selectedMacID ? selectedStatusText : AppL10n.text("Appairé"))
                                        .font(.caption)
                                        .foregroundStyle(
                                            mac.id == client.selectedMacID && client.state.isReady ? .green : .secondary
                                        )
                                }

                                Spacer()
                                if mac.id == client.selectedMacID {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.remoteBlue)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Choisir un Mac")
                } footer: {
                    Text("La télécommande ne contrôle qu’un Mac à la fois.")
                }

                Section {
                    Button {
                        showScanner = true
                    } label: {
                        Label("Ajouter un Mac", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("Mes Macs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .sheet(isPresented: $showScanner) {
                PairingScannerView().environmentObject(client)
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
    }

    private var selectedStatusText: String {
        switch client.state {
        case .ready: return AppL10n.text("Connecté")
        case .connecting: return AppL10n.text("Connexion…")
        case .pairing: return AppL10n.text("Appairage…")
        case .awaitingApproval: return AppL10n.text("Autorisation requise")
        case .searching: return AppL10n.text("Recherche…")
        case .failed: return AppL10n.text("Inaccessible")
        case .idle: return AppL10n.text("Déconnecté")
        }
    }
}

struct SettingsSheet: View {
    @EnvironmentObject private var client: MacConnectionClient
    @Environment(\.dismiss) private var dismiss

    @State private var showScanner = false
    @AppStorage("trackpadSensitivity") private var trackpadSensitivity: Double = TrackpadSettings.defaultPointerSpeed
    @AppStorage("scrollSensitivity") private var scrollSensitivity: Double = TrackpadSettings.defaultScrollSpeed
    @AppStorage("screenQuality") private var screenQuality: Double = 0.45
    @AppStorage("screenFrameRate") private var screenFrameRate: Double = 10
    @AppStorage(KeyboardInputMode.storageKey) private var keyboardInputMode: KeyboardInputMode = .direct
    @AppStorage(RemoteScreenPTTSide.storageKey) private var remoteScreenPTTSide: RemoteScreenPTTSide = .right
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system
    @AppStorage(DictationLanguage.storageKey) private var dictationLanguage: DictationLanguage = .automatic
    @State private var dictationLocaleIsSupported: Bool?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(client.pairedMacs) { mac in
                        Button {
                            client.selectMac(mac.id)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "desktopcomputer")
                                    .foregroundStyle(mac.id == client.selectedMacID ? Color.remoteBlue : .secondary)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mac.name)
                                        .foregroundStyle(.primary)
                                    if mac.id == client.selectedMacID {
                                        Text(macStatusText)
                                            .font(.caption)
                                            .foregroundStyle(client.state.isReady ? .green : .secondary)
                                    }
                                }
                                Spacer()
                                if mac.id == client.selectedMacID {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.remoteBlue)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button("Oublier", role: .destructive) {
                                client.forgetMac(mac.id)
                            }
                        }
                    }

                    Button {
                        showScanner = true
                    } label: {
                        Label("Ajouter un Mac", systemImage: "plus")
                    }
                } header: {
                    Text("Mes Macs")
                } footer: {
                    Text("Touchez un Mac pour basculer la télécommande. Chaque compagnon doit être appairé une fois.")
                }

                Section("Connexion") {
                    LabeledContent("État", value: statusText)
                    LabeledContent("Trajet") {
                        Label(routeText, systemImage: routeSymbol)
                            .foregroundStyle(routeColor)
                    }
                    if !client.accessibilityGranted {
                        Label("Accessibilité désactivée sur le Mac", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.footnote)
                    }
                    if client.isPaired {
                        if client.isNomadModeEnabled {
                            NavigationLink {
                                NomadSettingsView()
                                    .environmentObject(client)
                            } label: {
                                Label("Mode Nomade", systemImage: "network")
                            }
                        }
                        Button("Oublier le Mac sélectionné", role: .destructive) { client.forgetMac() }
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("Vitesse du curseur") {
                            Text("\(trackpadSensitivity, specifier: "%.2g")×")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $trackpadSensitivity, in: TrackpadSettings.pointerRange, step: 0.1) {
                            Text("Vitesse du curseur")
                        } minimumValueLabel: {
                            Image(systemName: "tortoise")
                        } maximumValueLabel: {
                            Image(systemName: "hare")
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("Vitesse du défilement") {
                            Text("\(scrollSensitivity, specifier: "%.2g")×")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $scrollSensitivity, in: TrackpadSettings.scrollRange, step: 0.1) {
                            Text("Vitesse du défilement")
                        } minimumValueLabel: {
                            Image(systemName: "tortoise")
                        } maximumValueLabel: {
                            Image(systemName: "hare")
                        }
                    }
                } header: {
                    Text("Pavé tactile")
                } footer: {
                    Text("Le curseur et le défilement se règlent indépendamment, jusqu’à 6× et 5×.")
                }

                Section {
                    NavigationLink {
                        ControlConfiguratorView()
                            .environmentObject(client)
                    } label: {
                        Label("Configurer le bloc de boutons", systemImage: "rectangle.3.group")
                    }
                } header: {
                    Text("Commandes")
                } footer: {
                    Text("Sept zones personnalisables entourent le bouton Push‑to‑Talk central.")
                }

                Section {
                    Picker("Mode de saisie", selection: $keyboardInputMode) {
                        ForEach(KeyboardInputMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    keyboardModeDescription(
                        .direct,
                        text: "Chaque touche est envoyée immédiatement. Idéal pour les commandes, les recherches et les petites modifications."
                    )

                    keyboardModeDescription(
                        .corrected,
                        text: "Le texte reste visible sur l’iPhone avec le correcteur natif. Idéal pour relire un message ou un long texte avant de l’envoyer."
                    )
                } header: {
                    Text("Clavier")
                } footer: {
                    Text("En mode Correcteur, le brouillon reste sur l’iPhone jusqu’à son envoi ou la fermeture du clavier. Il n’est jamais enregistré dans un historique.")
                }

                Section {
                    LabeledContent("Connexion actuelle") {
                        Label(
                            routeText,
                            systemImage: routeSymbol
                        )
                        .foregroundStyle(client.state.isReady ? .green : .secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("Qualité de l’écran") {
                            Text("\(Int(screenQuality * 100)) %")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $screenQuality, in: 0.25...0.7, step: 0.05)
                    }

                    Picker("Fluidité", selection: $screenFrameRate) {
                        Text("Économie · 6 i/s").tag(6.0)
                        Text("Équilibré · 10 i/s").tag(10.0)
                        Text("Fluide · 15 i/s").tag(15.0)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Position du bouton PTT")
                            .font(.subheadline)
                        Picker("Position du bouton PTT", selection: $remoteScreenPTTSide) {
                            ForEach(RemoteScreenPTTSide.allCases) { side in
                                Text(side.title).tag(side)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                } header: {
                    Text("Retour écran")
                } footer: {
                    Text("Le retour écran reste chiffré entre l’iPhone et le Mac et sa qualité s’adapte au réseau. Le bouton PTT est placé à droite par défaut et peut être déplacé à gauche.")
                }

                Section {
                    Picker("Langue de l’interface", selection: $appLanguage) {
                        Text("Langue de l’appareil").tag(AppLanguage.system)
                        Text("Français").tag(AppLanguage.french)
                        Text("English").tag(AppLanguage.english)
                    }

                    Picker("Langue de la dictée", selection: $dictationLanguage) {
                        Text("Langue de l’appareil").tag(DictationLanguage.automatic)
                        Text("Français (France)").tag(DictationLanguage.french)
                        Text("English (United States)").tag(DictationLanguage.english)
                    }

                    if let dictationLocaleIsSupported {
                        Label(
                            dictationLocaleIsSupported
                                ? "Dictée locale disponible"
                                : "Dictée locale indisponible sur cet appareil",
                            systemImage: dictationLocaleIsSupported
                                ? "checkmark.circle.fill"
                                : "exclamationmark.triangle.fill"
                        )
                        .font(.footnote)
                        .foregroundStyle(dictationLocaleIsSupported ? .green : .orange)
                    } else {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Vérification de la dictée locale…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Langues")
                } footer: {
                    Text("La voix est analysée sur cet iPhone avec les modèles Apple. Aucun audio n’est envoyé dans le cloud.")
                }

            }
            .navigationTitle("Vibe Walkie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
            .sheet(isPresented: $showScanner) {
                PairingScannerView().environmentObject(client)
            }
        }
        .preferredColorScheme(.dark)
        .task(id: dictationLanguage) {
            dictationLocaleIsSupported = nil
            guard #available(iOS 26.0, *) else {
                dictationLocaleIsSupported = false
                return
            }
            dictationLocaleIsSupported = await AppleSpeechAnalyzerEngine.supportsLocale(
                identifier: dictationLanguage.localeIdentifier
            )
        }
    }

    private var statusText: String {
        switch client.state {
        case .ready(let name): return AppL10n.text("Connecté à \(name)")
        case .connecting(let name): return AppL10n.text("Connexion à \(name)…")
        case .pairing(let name, let code): return AppL10n.text("Appairage \(name) · \(code)")
        case .awaitingApproval(let name, let code): return AppL10n.text("Autorisez \(name) sur le Mac · \(code)")
        case .searching: return AppL10n.text("Recherche…")
        case .failed(let code): return AppL10n.remoteError(code)
        case .idle: return AppL10n.text("Aucun Mac appairé")
        }
    }

    private var macStatusText: String {
        switch client.state {
        case .ready: return AppL10n.text("Connecté")
        case .connecting: return AppL10n.text("Connexion…")
        case .pairing: return AppL10n.text("Appairage…")
        case .awaitingApproval: return AppL10n.text("Autorisation requise")
        case .searching: return AppL10n.text("Recherche…")
        case .failed: return AppL10n.text("Inaccessible")
        case .idle: return AppL10n.text("Déconnecté")
        }
    }

    private var routeText: String {
        if client.state.isReady {
            return client.connectionRoute == .local ? AppL10n.text("Local") : AppL10n.text("Nomade · Tailscale")
        }
        return client.nomadEndpoint == nil ? AppL10n.text("Tailscale désactivé") : AppL10n.text("Mac inaccessible")
    }

    private var routeSymbol: String {
        if client.state.isReady {
            return client.connectionRoute == .local ? "wifi" : "network"
        }
        return client.nomadEndpoint == nil ? "network.slash" : "exclamationmark.icloud"
    }

    private var routeColor: Color {
        client.state.isReady ? .green : .secondary
    }

    private func keyboardModeDescription(_ mode: KeyboardInputMode, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: mode.systemImage)
                .foregroundStyle(keyboardInputMode == mode ? Color.remoteBlue : .secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(mode.title)
                        .font(.subheadline.weight(.semibold))
                    if keyboardInputMode == mode {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.remoteBlue)
                    }
                }
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

}

private struct NomadSettingsView: View {
    @EnvironmentObject private var client: MacConnectionClient

    var body: some View {
        List {
            Section {
                LabeledContent("État") {
                    Label(statusText, systemImage: statusSymbol)
                        .foregroundStyle(statusColor)
                }
                if let endpoint = client.nomadEndpoint {
                    LabeledContent("Mac", value: endpoint.magicDNSName)
                        .font(.footnote)
                }
            } header: {
                Text("Connexion")
            } footer: {
                Text("Vibe Walkie essaie toujours le réseau local en premier, puis Tailscale après 750 ms si nécessaire.")
            }

            Section("Configuration sur l’iPhone") {
                NomadStep(
                    number: 1,
                    title: "Installer et connecter Tailscale",
                    detail: "Tailscale reste une application séparée et facultative."
                )
                Link(destination: URL(string: "https://tailscale.com/download/ios")!) {
                    Label("Télécharger Tailscale", systemImage: "arrow.up.right.square")
                }

                NomadStep(
                    number: 2,
                    title: "Rejoindre le même tailnet",
                    detail: "Utilisez le même compte Tailscale, ou faites partager ce Mac à votre compte."
                )

                NomadStep(
                    number: 3,
                    title: "VPN On Demand (facultatif)",
                    detail: "Dans Tailscale, activez l’activation automatique pour les domaines *.ts.net."
                )
                Link(destination: URL(string: "https://tailscale.com/docs/features/client/ios-vpn-on-demand")!) {
                    Label("Voir le guide officiel", systemImage: "arrow.up.right.square")
                }
            }

            Section {
                Button {
                    client.reconnectNow()
                } label: {
                    Label("Tester la connexion", systemImage: "bolt.horizontal.circle")
                }
                .disabled(!client.isPaired)
            } footer: {
                Text("La connexion reste directe vers le Mac. Aucun compte, jeton Tailscale ou secret durable n’est transmis à Vibe Walkie.")
            }
        }
        .navigationTitle("Mode Nomade")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var statusText: String {
        if client.state.isReady {
            return client.connectionRoute == .local ? AppL10n.text("Local") : AppL10n.text("Nomade · Tailscale")
        }
        return client.nomadEndpoint == nil ? AppL10n.text("Tailscale désactivé") : AppL10n.text("Mac inaccessible")
    }

    private var statusSymbol: String {
        if client.state.isReady {
            return client.connectionRoute == .local ? "wifi" : "network"
        }
        return client.nomadEndpoint == nil ? "network.slash" : "exclamationmark.icloud"
    }

    private var statusColor: Color {
        client.state.isReady ? .green : .orange
    }
}

private struct NomadStep: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.remoteBlue, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
