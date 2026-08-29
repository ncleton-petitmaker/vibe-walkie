import Foundation

public struct VibeWalkieInfo: Sendable {
    // Identifiant réseau historique et invisible. Il doit rester stable entre
    // les mises à jour et les changements de marque : un iPhone récent doit
    // continuer à trouver un ancien compagnon Mac (et inversement).
    public static let bonjourServiceType = "_viberemote._tcp"
    // Identifiants historiques invisibles : la fiche App Store, la signature
    // macOS et le trousseau existant y sont déjà liés. Une marque n'a pas
    // besoin de correspondre au Bundle ID.
    public static let iosBundleIdentifier = "com.nicolascleton.viberemote"
    public static let macBundleIdentifier = "com.nicolascleton.viberemote.mac"
    public static let keychainService = "com.nicolascleton.viberemote"
    public static let dictationLocale = "fr-FR"
    /// Port fixe du compagnon, publié uniquement sur le LAN par Bonjour.
    public static let controlPort: UInt16 = 54_389

    /// Durée de vie d'un jeton de cible. Assez long pour une phrase, assez
    /// court pour qu'un jeton oublié ne serve jamais à insérer ailleurs.
    public static let targetTokenLifetime: TimeInterval = 120
    /// Fenêtre du mode appairage sur le Mac.
    public static let pairingWindow: TimeInterval = 120
    /// Une approbation explicite ne doit jamais rester ouverte indéfiniment.
    public static let pairingApprovalWindow: TimeInterval = 60
}
