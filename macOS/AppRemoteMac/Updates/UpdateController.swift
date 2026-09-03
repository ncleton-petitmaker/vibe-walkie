import Foundation
import Sparkle

enum UpdateRequest {
    static let scheme = "vibewalkie-mac"
    static let checkForUpdatesHost = "check-for-updates"

    static func requestsImmediateCheck(_ url: URL) -> Bool {
        url.scheme?.caseInsensitiveCompare(scheme) == .orderedSame
            && url.host?.caseInsensitiveCompare(checkForUpdatesHost) == .orderedSame
    }
}

@MainActor
final class UpdateController: ObservableObject {
    private let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(
            // Les tests unitaires hébergés lancent l'exécutable de l'app. Ne pas
            // contacter l'appcast public pendant une suite locale ou une CI.
            startingUpdater: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
