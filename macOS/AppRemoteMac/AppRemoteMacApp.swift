import SwiftUI
import RemoteCore

/// Dépendances uniques du compagnon.
///
/// SwiftUI peut reconstruire la valeur `App` lorsqu'une `WindowGroup` et un
/// `MenuBarExtra` coexistent. Les conserver ici garantit que les deux scènes
/// partagent le même serveur, la même autorité d'appairage et le même QR.
@MainActor
private final class VibeWalkieDependencies {
    static let shared = VibeWalkieDependencies()

    let peers: ApprovedPeersStore
    let permissions: PermissionCoordinator
    let authority: PairingAuthority
    let server: MacConnectionServer
    let tailscale: TailscaleCoordinator
    let updates: UpdateController

    private init() {
        let peers = ApprovedPeersStore()
        let authority = PairingAuthority(peers: peers)
        let tailscale = TailscaleCoordinator()
        let server = MacConnectionServer(
            peers: peers,
            authority: authority,
            nomadEndpoint: NomadFeatureFlag.isEnabled ? tailscale.activeEndpoint : nil
        )

        self.peers = peers
        self.permissions = PermissionCoordinator()
        self.authority = authority
        self.server = server
        self.tailscale = tailscale
        self.updates = UpdateController()
        if InstallationLocation.isSuitable { server.start() }
    }
}

@main
struct VibeWalkieMacApp: App {
    private let dependencies = VibeWalkieDependencies.shared

    var body: some Scene {
        WindowGroup("Vibe Walkie") {
            controlPanel
                .frame(minWidth: 340, idealWidth: 340, minHeight: 420, maxHeight: .infinity, alignment: .top)
        }
        .defaultSize(width: 340, height: 520)

        MenuBarExtra("Vibe Walkie", systemImage: "iphone.gen3.radiowaves.left.and.right") {
            controlPanel
        }
        .menuBarExtraStyle(.window)
    }

    private var controlPanel: some View {
        MenuBarView()
            .environmentObject(dependencies.server)
            .environmentObject(dependencies.permissions)
            .environmentObject(dependencies.authority)
            .environmentObject(dependencies.peers)
            .environmentObject(dependencies.tailscale)
            .environmentObject(dependencies.updates)
    }
}
