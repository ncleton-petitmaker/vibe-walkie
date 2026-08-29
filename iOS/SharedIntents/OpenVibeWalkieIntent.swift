import AppIntents

/// Destination unique exigée par `OpenIntent`.
///
/// Même si Vibe Walkie ne possède qu'un écran d'accueil, déclarer une cible
/// permet à WidgetKit d'identifier cette action comme une véritable ouverture
/// d'application plutôt que comme une action vide exécutée par l'extension.
enum VibeWalkieOpenDestination: String, AppEnum {
    case remote

    static let typeDisplayRepresentation = TypeDisplayRepresentation("Vibe Walkie")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .remote: "Télécommande"
    ]
}

/// Action partagée par l'application et son extension de contrôle.
/// `OpenIntent` est le contrat utilisé par WidgetKit pour lancer l'application
/// depuis le Centre de contrôle, l'écran verrouillé ou le bouton Action.
struct OpenVibeWalkieIntent: OpenIntent {
    static let title: LocalizedStringResource = "Ouvrir Vibe Walkie"
    static let description = IntentDescription("Ouvre Vibe Walkie pour contrôler le Mac associé.")

    @Parameter(title: "Destination")
    var target: VibeWalkieOpenDestination

    init() {
        target = .remote
    }
}
