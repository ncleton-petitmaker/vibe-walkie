#if DEBUG
import SwiftUI

/// Point d'entrée non distribué pour produire des captures exactes des écrans
/// de l'app dans le simulateur. Aucun de ces états n'existe dans l'archive
/// Release : ils servent uniquement aux assets de la landing page.
struct MarketingRootView: View {
    let mode: String
    @ObservedObject var client: MacConnectionClient
    @ObservedObject var history: TranscriptHistoryStore

    var body: some View {
        Group {
            switch mode {
            case "--marketing-home":
                RemoteHomeView(client: client, history: history)
            case "--marketing-home-idle", "--marketing-home-delivered":
                RemoteHomeView(client: client, history: history)
            case "--marketing-apps":
                AppSwitcherView()
                    .environmentObject(client)
            case "--marketing-screen":
                MarketingScreenRoot(client: client, history: history)
            case "--marketing-settings":
                MarketingSettingsPreview(client: client)
            default:
                RemoteHomeView(client: client, history: history)
            }
        }
        .task { client.configureMarketingPreview() }
    }
}

private struct MarketingScreenRoot: View {
    @StateObject private var dictation: DictationController
    @ObservedObject var client: MacConnectionClient

    init(client: MacConnectionClient, history: TranscriptHistoryStore) {
        self.client = client
        _dictation = StateObject(wrappedValue: DictationController(client: client, history: history))
    }

    var body: some View {
        RemoteScreenView(dictation: dictation)
            .environmentObject(client)
    }
}

private struct MarketingSettingsPreview: View {
    @ObservedObject var client: MacConnectionClient

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Text("Vibe Remote")
                        .font(.headline)
                    Spacer()
                    Text("OK")
                        .font(.headline)
                        .frame(width: 48, height: 44)
                        .background(Color.controlSurface, in: Capsule())
                }
                .padding(.leading, 48)
                .padding(.horizontal, 16)
                .padding(.bottom, 18)

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        sectionTitle("Connexion")
                        card {
                            row("État", value: "Connecté à MacBook Pro")
                            divider
                            row("Connexion actuelle", value: "Réseau local", symbol: "wifi", tint: .green)
                        }

                        sectionTitle("Pavé tactile")
                        card {
                            sliderRow("Vitesse du curseur", value: "1,6×", progress: 0.48, left: "tortoise", right: "hare")
                            divider
                            sliderRow("Vitesse du défilement", value: "0,8×", progress: 0.36, left: "tortoise", right: "hare")
                        }

                        sectionTitle("Retour écran")
                        card {
                            sliderRow("Qualité de l’écran", value: "45 %", progress: 0.45, left: "rectangle", right: "rectangle.inset.filled")
                            divider
                            row("Fluidité", value: "Équilibré · 10 i/s")
                        }

                        HStack(spacing: 10) {
                            Image(systemName: "lock.shield.fill")
                                .foregroundStyle(.green)
                            Text("Voix et commandes protégées sur votre réseau local.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 4)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 28)
                }
            }
            .padding(.top, 6)
        }
        .preferredColorScheme(.dark)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.title3.bold())
            .foregroundStyle(.secondary)
            .padding(.leading, 16)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .padding(.horizontal, 16)
            .background(Color.controlSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.07), lineWidth: 1)
            )
    }

    private func row(_ title: String, value: String, symbol: String? = nil, tint: Color = .secondary) -> some View {
        HStack(spacing: 8) {
            Text(title)
            Spacer()
            if let symbol { Image(systemName: symbol) }
            Text(value)
        }
        .font(.body)
        .foregroundStyle(tint)
        .padding(.vertical, 16)
        .accessibilityElement(children: .combine)
    }

    private func sliderRow(_ title: String, value: String, progress: CGFloat, left: String, right: String) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text(title)
                Spacer()
                Text(value).foregroundStyle(.secondary).monospacedDigit()
            }
            HStack(spacing: 12) {
                Image(systemName: left)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.12)).frame(height: 5)
                        Capsule().fill(Color.remoteBlue).frame(width: proxy.size.width * progress, height: 5)
                        Circle().fill(.white).frame(width: 22, height: 22)
                            .offset(x: max(0, proxy.size.width * progress - 11))
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(height: 22)
                Image(systemName: right)
            }
        }
        .padding(.vertical, 15)
    }

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.10)).frame(height: 1)
    }
}
#endif
