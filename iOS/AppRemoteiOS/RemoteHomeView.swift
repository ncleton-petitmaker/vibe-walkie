import SwiftUI
import RemoteCore

/// Écran principal.
///
/// Une pilule de cible reste en haut, une grande surface tactile occupe le
/// centre et les commandes essentielles restent accessibles au pouce.
/// Le bouton de dictée est centré et dimensionné pour être maintenu au pouce
/// sans regarder l'écran.
struct RemoteHomeView: View {
    @EnvironmentObject private var client: MacConnectionClient
    @EnvironmentObject private var history: TranscriptHistoryStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var dictation: DictationController

    @State private var showSwitcher = false
    @State private var showKeyboard = false
    @State private var showSettings = false
    @State private var showScreen = false

    init(client: MacConnectionClient, history: TranscriptHistoryStore) {
        _dictation = StateObject(wrappedValue: DictationController(client: client, history: history))
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                topRow

                VStack(spacing: 12) {
                    TrackpadView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(alignment: .bottom) {
                            statusStrip
                                .padding(.horizontal, 16)
                                .padding(.bottom, 8)
                                .allowsHitTesting(false)
                        }
                    dictationBar
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)

            }
        }
        .preferredColorScheme(.dark)
        .task {
            client.connectIfPossible()
#if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--marketing-home") {
                dictation.configureMarketingRecording()
                return
            }
            if arguments.contains("--marketing-home-delivered") {
                dictation.configureMarketingDelivered()
                return
            }
            if arguments.contains("--marketing-home-idle") { return }
#endif
            // Le test écran ne dépend ni du micro ni de la transcription.
            // Le lancer en premier évite qu'une initialisation Speech lente
            // suspende la validation réseau sur un appareil physique.
            if ProcessInfo.processInfo.arguments.contains("--smoke-test-screen") {
                await runScreenSmokeTestIfRequested()
                return
            }
            await dictation.prepareEngine()
            await runPTTSmokeTestIfRequested()
        }
        .task(id: client.state.isReady) {
            await monitorActiveApplication()
        }
        .sheet(isPresented: $showSwitcher) {
            AppSwitcherView().environmentObject(client)
        }
        .sheet(isPresented: $showKeyboard) {
            RemoteKeyboardView().environmentObject(client)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(dictation: dictation)
                .environmentObject(client)
                .environmentObject(history)
        }
        .fullScreenCover(isPresented: $showScreen) {
            RemoteScreenView(dictation: dictation)
                .environmentObject(client)
        }
    }

    /// Maintient la pilule du haut alignée sur l'app réellement au premier
    /// plan sur le Mac. La requête légère n'embarque pas les icônes ; la grille
    /// complète continue de les demander uniquement lorsqu'elle est ouverte.
    private func monitorActiveApplication() async {
        guard client.state.isReady else { return }
        while !Task.isCancelled && client.state.isReady {
            if !showSwitcher {
                _ = try? await client.send(
                    type: .listWindows,
                    payload: ListWindowsPayload(includeIcons: false)
                )
            }
            try? await Task.sleep(for: .milliseconds(750))
        }
    }

    /// Utilisé uniquement par l'installation de validation sur un iPhone
    /// physique. Le lancement normal ne contient jamais cet argument.
    private func runPTTSmokeTestIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("--smoke-test-ptt") else { return }

        // Attend la reconnexion puis vérifie le trajet complet de la grille
        // d'apps (requête, sérialisation des icônes et réponse).
        for _ in 0..<50 where !client.state.isReady {
            try? await Task.sleep(for: .milliseconds(100))
        }

        var applicationCount: Int?
        var applicationError: String?
        do {
            let response = try await client.send(
                type: .listWindows,
                payload: ListWindowsPayload(includeIcons: true)
            )
            let snapshot = try response.decodePayload(WindowsSnapshotPayload.self)
            applicationCount = snapshot.applications.count
        } catch {
            applicationError = error.localizedDescription
        }

        try? await Task.sleep(for: .milliseconds(500))
        dictation.pressBegan()
        try? await Task.sleep(for: .seconds(2))
        dictation.pressEnded()
        try? await Task.sleep(for: .seconds(3))

        let report: [String: Any] = [
            "applications": applicationCount.map { $0 as Any } ?? NSNull(),
            "applicationsError": applicationError.map { $0 as Any } ?? NSNull(),
            "processAliveAfterPTT": true,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted]),
           let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? data.write(to: documents.appendingPathComponent("viberemote-smoke-test.json"), options: .atomic)
        }
    }

    /// Validation de bout en bout sur l’iPhone physique : demande réellement
    /// le flux au compagnon Mac et conserve les dimensions de la première
    /// image reçue dans le conteneur de l’app.
    private func runScreenSmokeTestIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("--smoke-test-screen") else { return }

        for _ in 0..<100 where !client.state.isReady {
            try? await Task.sleep(for: .milliseconds(100))
        }

        client.startScreenStream(maxWidth: 1_280, framesPerSecond: 10, jpegQuality: 0.45)
        for _ in 0..<120 where client.latestScreenFrame == nil {
            try? await Task.sleep(for: .milliseconds(100))
        }

        let frame = client.latestScreenFrame
        let report: [String: Any] = [
            "connected": client.state.isReady,
            "connection": "local",
            "screenPermissionGranted": client.screenStreamStatus.permissionGranted,
            "screenStreaming": client.screenStreamStatus.isStreaming,
            "screenError": client.screenStreamStatus.detail ?? NSNull(),
            "frameBytes": frame?.jpegData.count ?? 0,
            "frameWidth": frame?.width ?? 0,
            "frameHeight": frame?.height ?? 0,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted]),
           let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? data.write(to: documents.appendingPathComponent("viberemote-screen-smoke-test.json"), options: .atomic)
        }
        client.stopScreenStream()
    }

    private var topRow: some View {
        HStack(spacing: 12) {
            CircularControlButton(
                systemImage: client.state.isReady ? "escape" : "arrow.clockwise",
                size: 44,
                iconSize: 15,
                accessibilityText: client.state.isReady ? "Échap" : "Reconnecter le Mac"
            ) {
                HapticFeedback.shared.tick()
                if client.state.isReady {
                    client.sendFireAndForget(type: .keyPress, payload: KeyPressPayload(key: .escape))
                } else {
                    client.reconnectNow()
                }
            }

            TargetPill { showSwitcher = true }

            CircularControlButton(
                systemImage: "arrow.up.left.and.arrow.down.right",
                size: 44,
                iconSize: 15,
                accessibilityText: "Afficher l’écran du Mac"
            ) {
                HapticFeedback.shared.tick()
                showScreen = true
            }
            .disabled(!client.state.isReady)

            CircularControlButton(
                systemImage: "list.bullet",
                size: 44,
                iconSize: 15,
                accessibilityText: "Connexion et réglages"
            ) {
                showSettings = true
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.appChrome)
    }

    /// Bandeau d'état : la transcription en direct et le résultat de l'envoi.
    /// Il garde une hauteur fixe pour que le trackpad ne bouge jamais sous le
    /// doigt quand un message apparaît.
    private var statusStrip: some View {
        Group {
            switch dictation.phase {
            case .recording, .armedForCancel:
                Text(dictation.partialText.isEmpty ? "Parlez…" : dictation.partialText)
                    .foregroundStyle(dictation.phase == .armedForCancel ? .red : .white)
            case .finalizing:
                Text("Transcription…").foregroundStyle(.white.opacity(0.6))
            case .sending:
                Text("Envoi…").foregroundStyle(.white.opacity(0.6))
            case .delivered(let message):
                Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .sentUnverified(let message):
                Label(message, systemImage: "arrow.up.circle.fill").foregroundStyle(.orange)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.circle.fill").foregroundStyle(.orange)
            case .idle:
                Text(" ").foregroundStyle(.clear)
            }
        }
        .font(.footnote)
        .lineLimit(2)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .center)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: dictation.phase)
    }

    private var dictationBar: some View {
        ZStack {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(dictation.isRecording ? "Je vous écoute…" : "Maintenez pour dicter")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Relâchez pour envoyer au Mac")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.68))
                }
                .frame(maxWidth: 88, alignment: .leading)

                Spacer()

                VStack(spacing: 8) {
                    CircularControlButton(
                        systemImage: "arrow.left.arrow.right",
                        size: 52,
                        iconSize: 18,
                        accessibilityText: "Revenir à l’application précédente"
                    ) {
                        sendKey(.applicationSwitcher)
                    }

                    CircularControlButton(
                        systemImage: "return",
                        size: 52,
                        iconSize: 20,
                        isProminent: true,
                        accessibilityText: "Entrée"
                    ) {
                        sendKey(.enter)
                    }
                }
            }

            VStack(spacing: 0) {
                PTTButton(dictation: dictation)

                HStack(spacing: 6) {
                    quickActionButton("Saisie", systemImage: "keyboard") {
                        showKeyboard = true
                    }
                    quickKeyButton("Effacer", systemImage: "delete.left", key: .backspace)
                    quickKeyButton("Espace", systemImage: "space", key: .space)
                }
                .offset(y: -4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        // La zone de commandes gagne un peu de hauteur pour accueillir le
        // switcher au-dessus d'Entrée ; le pavé tactile cède naturellement
        // cet espace sans déplacer les commandes essentielles.
        .frame(minHeight: 190)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.controlSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private func quickKeyButton(
        _ title: String,
        systemImage: String,
        key: RemoteKey
    ) -> some View {
        Button {
            sendKey(key)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .minimumScaleFactor(0.8)
                .frame(width: 72)
                .frame(minHeight: 44)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func quickActionButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticFeedback.shared.tick()
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .minimumScaleFactor(0.8)
                .frame(width: 72)
                .frame(minHeight: 44)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func sendKey(_ key: RemoteKey) {
        HapticFeedback.shared.tick()
        client.sendFireAndForget(type: .keyPress, payload: KeyPressPayload(key: key))
    }

}
