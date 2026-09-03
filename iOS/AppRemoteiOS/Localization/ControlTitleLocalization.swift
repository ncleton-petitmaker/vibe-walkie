import Foundation
import RemoteCore

/// Les titres du protocole restent stables pour préserver la compatibilité
/// avec les configurations déjà synchronisées. Seuls les libellés standard
/// sont traduits à l'affichage ; un titre réellement personnalisé est conservé.
enum ControlTitleLocalization {
    private static let stockTitles: Set<String> = [
        "Suivant", "Clavier", "App précédente", "Entrée", "Effacer", "Espace",
        "Tabulation", "Échap", "Supprimer", "Haut", "Bas", "Gauche", "Droite",
        "Copier", "Coller", "Couper", "Ajouter"
    ]

    static func title(_ storedTitle: String, action: ControlButtonAction) -> String {
        guard stockTitles.contains(storedTitle) else { return storedTitle }
        switch action {
        case .none:
            return AppL10n.text("ios.add.8d39b2a")
        case .showKeyboard:
            return AppL10n.text("ios.keyboard.cd896f5")
        case .standardKey(let key):
            return key.localizedName
        case .hostShortcut, .macShortcut:
            return storedTitle
        }
    }
}
