import SwiftUI
import UIKit
import RemoteCore

/// Mode écran distant : l’image sert de retour visuel et le pavé reste la
/// surface de contrôle principale. On évite ainsi de masquer le pointeur sous
/// le doigt et on conserve exactement les gestes du pavé habituel.
struct RemoteScreenView: View {
    @EnvironmentObject private var client: MacConnectionClient
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var dictation: DictationController

    @AppStorage("screenQuality") private var screenQuality = 0.45
    @AppStorage("screenFrameRate") private var screenFrameRate = 10.0
    @State private var showKeyboard = false

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 8) {
                screenPreview
                    .frame(
                        width: proxy.size.width,
                        height: min(320, proxy.size.height * 0.34 + proxy.safeAreaInsets.top)
                    )
                    .overlay(alignment: .top) { screenHeader(topInset: proxy.safeAreaInsets.top) }

                TrackpadView()
                    .environmentObject(client)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 10)

                commandBar
                    .padding(.horizontal, 10)
                    .padding(.bottom, max(8, proxy.safeAreaInsets.bottom))
            }
            // L’image commence réellement au bord supérieur et passe derrière
            // la Dynamic Island afin de ne perdre aucune hauteur utile.
            .ignoresSafeArea(edges: [.top, .bottom])
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .task(id: client.state.isReady) {
            guard client.state.isReady else { return }
            await maintainScreenStream()
        }
        .onAppear {
            // Une télécommande posée près du Mac ne doit pas verrouiller son
            // écran en plein contrôle : iOS suspendrait alors le réseau et le
            // flux semblerait « couper » au bout du délai de veille.
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            client.stopScreenStream()
        }
        .sheet(isPresented: $showKeyboard) {
            RemoteKeyboardView()
                .environmentObject(client)
                .presentationDetents([.medium])
        }
    }

    /// Redemande le flux si ScreenCaptureKit s'est arrêté sans faire tomber
    /// la session TLS. Sans cette surveillance, l'interface pouvait afficher
    /// une image puis rester figée après un verrouillage ou un changement
    /// d'écran côté Mac.
    private func maintainScreenStream() async {
        var lastRequestAt = Date.distantPast

        func requestStream() {
            lastRequestAt = Date()
            client.startScreenStream(
                maxWidth: 1_280,
                framesPerSecond: Int(screenFrameRate),
                jpegQuality: screenQuality
            )
        }

        requestStream()
        while !Task.isCancelled && client.state.isReady {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, client.state.isReady else { return }

            let frameIsStale: Bool
            if let lastFrameAt = client.lastScreenFrameAt {
                frameIsStale = Date().timeIntervalSince(lastFrameAt) > 5
            } else {
                frameIsStale = Date().timeIntervalSince(lastRequestAt) > 5
            }

            if frameIsStale,
               client.screenStreamStatus.permissionGranted,
               Date().timeIntervalSince(lastRequestAt) > 5 {
                requestStream()
            }
        }
    }

    @ViewBuilder
    private var screenPreview: some View {
        ZStack {
            Color.black
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--marketing-screen") {
                MarketingDesktopPreview()
            } else {
                liveScreenPreview
            }
#else
            liveScreenPreview
#endif
        }
        .clipped()
    }

    @ViewBuilder
    private var liveScreenPreview: some View {
        if let frame = client.latestScreenFrame,
           let image = UIImage(data: frame.jpegData) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.low)
                    .aspectRatio(contentMode: .fit)
        } else if !client.screenStreamStatus.permissionGranted {
            VStack(spacing: 8) {
                Image(systemName: "rectangle.dashed.badge.record")
                    .font(.system(size: 30))
                    .foregroundStyle(.orange)
                Text("Autorisez l’écran sur le Mac")
                    .font(.footnote.weight(.semibold))
                Text(client.screenStreamStatus.detail ?? "Ouvrez Vibe Remote sur le Mac puis autorisez l’enregistrement de l’écran.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 46)
            }
        } else {
            ProgressView("Connexion à l’écran du Mac…")
                .font(.caption)
                .tint(.white)
        }
    }

#if DEBUG
    private struct MarketingDesktopPreview: View {
        var body: some View {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.12, green: 0.17, blue: 0.24), Color(red: 0.23, green: 0.14, blue: 0.24)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 10) {
                        Spacer().frame(height: 34)
                        Text("Notes")
                            .font(.caption.bold())
                            .foregroundStyle(.white.opacity(0.9))
                        ForEach(["Idées", "Brief", "À relire"], id: \.self) { item in
                            Text(item)
                                .font(.system(size: 9, weight: item == "Brief" ? .semibold : .regular))
                                .foregroundStyle(item == "Brief" ? .white : .white.opacity(0.55))
                        }
                        Spacer()
                    }
                    .padding(14)
                    .frame(width: 112)
                    .background(.black.opacity(0.28))

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Brief lancement")
                            .font(.headline.bold())
                        Text("Vibe Remote me permet de dicter, viser le bon champ et piloter mon Mac depuis l’iPhone — sans envoyer ma voix dans le cloud.")
                            .font(.caption)
                            .lineSpacing(3)
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.remoteBlue)
                            .frame(width: 2, height: 18)
                        Spacer()
                    }
                    .foregroundStyle(.white)
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.black.opacity(0.12))
                }
                // La zone utile commence sous la Dynamic Island : aucun titre
                // ni texte de la fausse fenêtre Mac n'est masqué sur la capture.
                .padding(.top, 54)
            }
        }
    }
#endif

    private func screenHeader(topInset: CGFloat) -> some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }

            Spacer()

            Label(
                "Réseau local",
                systemImage: "wifi"
            )
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.top, topInset + 4)
    }

    private var commandBar: some View {
        HStack(spacing: 8) {
            commandButton("Saisie", systemImage: "keyboard") { showKeyboard = true }
            commandButton("Effacer", systemImage: "delete.left") { sendKey(.backspace) }

            PTTButton(dictation: dictation)
                .scaleEffect(0.82)
                .frame(width: 86, height: 86)

            commandButton("Espace", systemImage: "space") { sendKey(.space) }
            commandButton("Entrée", systemImage: "return") { sendKey(.enter) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.controlSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white.opacity(0.07), lineWidth: 1)
                )
        )
    }

    private func commandButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticFeedback.shared.tick()
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                Text(title)
                    .font(.system(size: 8, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white.opacity(0.9))
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func sendKey(_ key: RemoteKey) {
        client.sendFireAndForget(type: .keyPress, payload: KeyPressPayload(key: key))
    }
}
