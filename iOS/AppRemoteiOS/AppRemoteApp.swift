import SwiftUI
import RemoteCore
import WidgetKit

@main
struct VibeWalkieApp: App {
    @StateObject private var client = MacConnectionClient()
    @StateObject private var history = TranscriptHistoryStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            rootContent
                .environmentObject(client)
                .environmentObject(history)
                .task {
                    ControlCenter.shared.reloadAllControls()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            // iOS suspend l'application en arrière-plan : la connexion est
            // rétablie au retour au premier plan plutôt que maintenue en vain.
            switch phase {
            case .active:
                // Une mise à jour ou un redémarrage du compagnon peut laisser
                // iOS avec une socket apparemment vivante mais inutilisable.
                // Recréer la connexion au retour au premier plan est rapide et
                // garantit que le bouton Reconnecter n’est jamais nécessaire.
                if client.isPaired { client.reconnectNow() }
            case .background: client.disconnect()
            default: break
            }
        }
    }

    @ViewBuilder
    private var rootContent: some View {
#if DEBUG
        if let mode = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--marketing-") }) {
            if mode == "--marketing-welcome" {
                RootView()
            } else {
                MarketingRootView(mode: mode, client: client, history: history)
            }
        } else {
            RootView()
        }
#else
        RootView()
#endif
    }
}

private struct RootView: View {
    @EnvironmentObject private var client: MacConnectionClient
    @EnvironmentObject private var history: TranscriptHistoryStore
    @State private var showDiscovery = false

    var body: some View {
        if client.isPaired {
            RemoteHomeView(client: client, history: history)
        } else {
            WelcomeView(showDiscovery: $showDiscovery)
                .fullScreenCover(isPresented: $showDiscovery) { DiscoveryView() }
        }
    }
}

/// Premier lancement : rien d'autre que ce qu'il faut pour se connecter.
private struct WelcomeView: View {
    @EnvironmentObject private var client: MacConnectionClient
    @Binding var showDiscovery: Bool
    @State private var showScanner = false

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 20) {
                HStack {
                    Text("Vibe Walkie")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(.horizontal, 22)
                .padding(.top, 10)

                Spacer()

                VStack(alignment: .leading, spacing: 18) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.controlSurface)
                            .frame(width: 92, height: 92)
                        Image(systemName: "laptopcomputer")
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(Color.remoteBlue)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Ajoutez votre Mac")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                        Text("Pilotez le pointeur, le clavier et la dictée depuis cet iPhone. Aucun compte, aucun cloud.")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.72))
                        onboardingStep(1, "Téléchargez le compagnon sur vibewalkie.app")
                        onboardingStep(2, "Ouvrez Vibe Walkie sur le Mac")
                        onboardingStep(3, "Scannez son QR et autorisez cet iPhone")
                        onboardingStep(4, "Testez une première commande")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color.trackpadSurface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(.white.opacity(0.07), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 20)

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        showScanner = true
                    } label: {
                        Label("Ajouter un Mac", systemImage: "plus")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Capsule().fill(Color.remoteBlue))
                    }
                    .buttonStyle(.plain)

                    Link(destination: URL(string: "https://vibewalkie.app/download")!) {
                        Label("Télécharger le compagnon Mac", systemImage: "arrow.down.circle")
                            .font(.subheadline.weight(.semibold))
                    }

                    Button("Découvrir sans Mac") { showDiscovery = true }
                        .font(.subheadline.weight(.semibold))

                    Text("Ouvrez Vibe Walkie sur votre Mac, puis « Appairer un iPhone ».")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.62))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showScanner) {
            PairingScannerView().environmentObject(client)
        }
    }

    private func onboardingStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text("\(number)")
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(Color.remoteBlue)
            Text(text)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
        }
        .accessibilityElement(children: .combine)
    }
}
