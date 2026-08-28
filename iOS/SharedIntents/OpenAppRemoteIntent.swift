import AppIntents

/// iOS 26 remplace `openAppWhenRun` par un mode d'exécution explicite.
/// Le mode immédiat demande au système de placer l'app au premier plan avant
/// même d'exécuter l'action, y compris lorsqu'elle était complètement arrêtée.
struct OpenAppRemoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Ouvrir Vibe Remote"
    static let description = IntentDescription("Ouvre Vibe Remote pour contrôler le Mac associé.")
    static let supportedModes: IntentModes = [.foreground(.immediate)]

    func perform() async throws -> some IntentResult {
        .result()
    }
}
