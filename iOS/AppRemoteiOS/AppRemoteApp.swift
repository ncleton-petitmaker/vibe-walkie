import SwiftUI
import RemoteCore
import UIKit
import WidgetKit

/// Supprime les transcriptions créées par les prototypes qui proposaient un
/// historique local. La suppression est répétée sans danger à chaque lancement
/// afin qu'aucune ancienne phrase ne subsiste après la mise à jour.
enum LegacyTranscriptCleanup {
    private static let enabledKey = "com.nicolascleton.viberemote.historyEnabled"

    static func run(defaults: UserDefaults = .standard, fileURL: URL? = nil) {
        defaults.removeObject(forKey: enabledKey)
        let transcriptURL = fileURL
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("transcripts.json")
        try? FileManager.default.removeItem(at: transcriptURL)
    }
}

/// L'app reste verticale au quotidien. Seul le retour d'écran du Mac peut
/// pivoter, car c'est le seul endroit où le paysage apporte une vraie surface
/// de travail supplémentaire.
@MainActor
enum AppOrientationPolicy {
    static var supported: UIInterfaceOrientationMask = .portrait

    static func setRemoteScreenActive(_ isActive: Bool) {
        supported = isActive ? .allButUpsideDown : .portrait

        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: supported))
        }
    }
}

final class VibeWalkieAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        AppOrientationPolicy.supported
    }
}

/// Canal privé de développement. Le symbole `OTA_UPDATES` n'est défini que
/// pour les archives Ad Hoc publiées sur le VPS ; ce code est donc absent des
/// builds TestFlight et App Store.
#if !DEBUG && OTA_UPDATES
@MainActor
private final class OTAUpdateCoordinator: ObservableObject {
    @Published var isUpdateAvailable = false
    private var manifestURL: URL?
    private var isChecking = false

    private struct UpdateResponse: Decodable {
        let hasUpdate: Bool
        let manifestUrl: URL?
    }

    func checkForUpdate() async {
        guard !isChecking, !isUpdateAvailable else { return }
        isChecking = true
        defer { isChecking = false }

        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        guard var components = URLComponents(
            string: "https://app-remote.92.222.247.135.sslip.io/api/releases/ios/check"
        ) else { return }
        components.queryItems = [URLQueryItem(name: "build", value: build)]
        guard let url = components.url,
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let update = try? JSONDecoder().decode(UpdateResponse.self, from: data),
              update.hasUpdate,
              let manifestURL = update.manifestUrl else { return }

        self.manifestURL = manifestURL
        isUpdateAvailable = true
    }

    func install() {
        guard let manifestURL,
              let encoded = manifestURL.absoluteString.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed
              ),
              let installURL = URL(
                string: "itms-services://?action=download-manifest&url=\(encoded)"
              ) else { return }
        UIApplication.shared.open(installURL)
    }
}
#endif

@main
struct VibeWalkieApp: App {
    @UIApplicationDelegateAdaptor(VibeWalkieAppDelegate.self) private var appDelegate
    @StateObject private var client = MacConnectionClient()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system
#if !DEBUG && OTA_UPDATES
    @StateObject private var updater = OTAUpdateCoordinator()
#endif

    init() {
        LegacyTranscriptCleanup.run()
        TrackpadSettings.migrateExpandedSpeedRange()
    }

    var body: some Scene {
        WindowGroup {
            rootContent
                .environmentObject(client)
                .environment(\.locale, appLanguage.locale)
                .task {
                    ControlCenter.shared.reloadAllControls()
#if !DEBUG && OTA_UPDATES
                    await updater.checkForUpdate()
#endif
                }
#if !DEBUG && OTA_UPDATES
                .alert("Mise à jour disponible", isPresented: $updater.isUpdateAvailable) {
                    Button("Installer") { updater.install() }
                    Button("Plus tard", role: .cancel) {}
                } message: {
                    Text("Une nouvelle version de Vibe Walkie est prête.")
                }
#endif
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
                client.resumeAfterForeground()
#if !DEBUG && OTA_UPDATES
                Task { await updater.checkForUpdate() }
#endif
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
                MarketingRootView(mode: mode, client: client)
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
    @State private var showDiscovery = false

    var body: some View {
        if client.isPaired {
            RemoteHomeView(client: client)
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
