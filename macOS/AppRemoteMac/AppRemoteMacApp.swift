import SwiftUI
import RemoteCore

@main
struct AppRemoteMacApp: App {
    @StateObject private var peers = ApprovedPeersStore()
    @StateObject private var permissions = PermissionCoordinator()
    @StateObject private var authority: PairingAuthority
    @StateObject private var server: MacConnectionServer
    @StateObject private var updates = UpdateController()

    init() {
        let peersStore = ApprovedPeersStore()
        let pairingAuthority = PairingAuthority(peers: peersStore)
        _peers = StateObject(wrappedValue: peersStore)
        _authority = StateObject(wrappedValue: pairingAuthority)
        _server = StateObject(wrappedValue: MacConnectionServer(peers: peersStore, authority: pairingAuthority))
    }

    var body: some Scene {
        WindowGroup("Vibe Remote") {
            controlPanel
                .frame(minWidth: 380, idealWidth: 400, minHeight: 440, maxHeight: .infinity, alignment: .top)
        }
        .defaultSize(width: 400, height: 560)

        MenuBarExtra("Vibe Remote", systemImage: "iphone.gen3.radiowaves.left.and.right") {
            controlPanel
        }
        .menuBarExtraStyle(.window)
    }

    private var controlPanel: some View {
        MenuBarView()
            .environmentObject(server)
            .environmentObject(permissions)
            .environmentObject(authority)
            .environmentObject(peers)
            .environmentObject(updates)
            .task {
                if InstallationLocation.isSuitable { server.start() }
            }
    }
}
