#if DEBUG
import SwiftUI

/// Point d'entrée non distribué pour produire des captures exactes des écrans
/// de l'app dans le simulateur. Aucun de ces états n'existe dans l'archive
/// Release : ils servent uniquement aux assets de la landing page.
struct MarketingRootView: View {
    let mode: String
    @ObservedObject var client: HostConnectionClient

    var body: some View {
        Group {
            switch mode {
            case "--marketing-home":
                RemoteHomeView(client: client)
            case "--marketing-home-idle", "--marketing-home-delivered":
                RemoteHomeView(client: client)
            case "--marketing-global":
                RemoteHomeView(client: client)
            case "--marketing-apps":
                AppSwitcherView()
                    .environmentObject(client)
            case "--marketing-screen":
                MarketingScreenRoot(client: client)
            case "--marketing-settings":
                MarketingSettingsPreview(client: client)
            case "--marketing-controls":
                NavigationStack {
                    ControlConfiguratorView()
                        .environmentObject(client)
                }
            case "--marketing-welcome":
                DiscoveryView()
            case "--marketing-macs":
                HostSwitcherView()
                    .environmentObject(client)
            default:
                RemoteHomeView(client: client)
            }
        }
        .task { client.configureMarketingPreview() }
    }
}

private struct MarketingScreenRoot: View {
    @StateObject private var dictation: DictationController
    @ObservedObject var client: HostConnectionClient

    init(client: HostConnectionClient) {
        self.client = client
        _dictation = StateObject(wrappedValue: DictationController(client: client))
    }

    var body: some View {
        RemoteScreenView(dictation: dictation)
            .environmentObject(client)
    }
}

private struct MarketingSettingsPreview: View {
    @ObservedObject var client: HostConnectionClient

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Text("ios.vibe.walkie.111e6dd")
                        .font(.headline)
                    Spacer()
                    Text("ios.ok.565339b")
                        .font(.headline)
                        .frame(width: 48, height: 44)
                        .background(Color.controlSurface, in: Capsule())
                }
                .padding(.leading, 48)
                .padding(.horizontal, 16)
                .padding(.bottom, 18)

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        sectionTitle("ios.connection.61d6950")
                        card {
                            row("ios.status.de4dd03", value: "ios.connected.e92b0f9")
                            divider
                            row("ios.current.connection.8cf8ef6", value: "ios.local.8c31e6e", symbol: "wifi", tint: .green)
                        }

                        sectionTitle("ios.trackpad.c8dc586")
                        card {
                            sliderRow("ios.pointer.speed.28fb9b9", value: "1.6×", progress: 0.48, left: "tortoise", right: "hare")
                            divider
                            sliderRow("ios.scroll.speed.addea81", value: "0.8×", progress: 0.36, left: "tortoise", right: "hare")
                        }

                        sectionTitle("ios.controls.0e3118a")
                        card {
                            row("ios.configure.button.panel.a006d38", value: "7 · Global", symbol: "rectangle.3.group", tint: .white)
                        }

                        sectionTitle("ios.screen.view.b5645a8")
                        card {
                            sliderRow("ios.screen.quality.d18a3e1", value: "45 %", progress: 0.45, left: "rectangle", right: "rectangle.inset.filled")
                            divider
                            row("ios.frame.rate.d190183", value: "ios.balanced.10.fps.27a7782")
                        }

                        HStack(spacing: 10) {
                            Image(systemName: "lock.shield.fill")
                                .foregroundStyle(.green)
                            Text("ios.screen.view.stays.encrypted.between.iphone.and.mac.and.adapts.5eedf76")
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
        Text(LocalizedStringKey(text))
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
            Text(LocalizedStringKey(title))
            Spacer()
            if let symbol { Image(systemName: symbol) }
            Text(LocalizedStringKey(value))
        }
        .font(.body)
        .foregroundStyle(tint)
        .padding(.vertical, 16)
        .accessibilityElement(children: .combine)
    }

    private func sliderRow(_ title: String, value: String, progress: CGFloat, left: String, right: String) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text(LocalizedStringKey(title))
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
