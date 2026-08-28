import Foundation

public struct VibeRemoteInfo: Sendable {
    public static let bonjourServiceType = "_viberemote._tcp"
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
