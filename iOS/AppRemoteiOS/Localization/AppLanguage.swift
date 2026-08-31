import Foundation
import RemoteCore

/// Langue de l'interface. Le choix « système » conserve le comportement Apple
/// habituel, tandis que les deux autres valeurs permettent de basculer l'app
/// immédiatement sans modifier la langue générale de l'iPhone.
enum AppLanguage: String, CaseIterable, Identifiable {
    static let storageKey = "appLanguage"

    case system
    case french
    case english

    var id: Self { self }

    var locale: Locale {
        switch self {
        case .system: .autoupdatingCurrent
        case .french: Locale(identifier: "fr-FR")
        case .english: Locale(identifier: "en-US")
        }
    }
}

/// Langue utilisée par SpeechAnalyzer. Elle est volontairement indépendante
/// de la langue de l'interface : un développeur peut garder l'app en anglais
/// tout en dictant du français, ou l'inverse.
enum DictationLanguage: String, CaseIterable, Identifiable {
    static let storageKey = "dictationLanguage"

    case automatic
    case french
    case english

    var id: Self { self }

    var localeIdentifier: String {
        switch self {
        case .automatic:
            return Self.deviceLocaleIdentifier
        case .french:
            return "fr-FR"
        case .english:
            return "en-US"
        }
    }

    /// La phase 1 garantit français et anglais. Pour une langue système encore
    /// non prise en charge par l'app, le français reste le repli historique.
    static var deviceLocaleIdentifier: String {
        guard let preferred = Locale.preferredLanguages.first else { return "fr-FR" }
        let language = Locale(identifier: preferred).language.languageCode?.identifier
        switch language {
        case "en", "fr": return preferred
        default: return "fr-FR"
        }
    }
}

enum AppL10n {
    static func text(_ key: String.LocalizationValue) -> String {
        let stored = UserDefaults.standard.string(forKey: AppLanguage.storageKey)
        let language = stored.flatMap(AppLanguage.init(rawValue:)) ?? .system
        return String(localized: key, locale: language.locale)
    }

    static func remoteError(_ code: RemoteErrorCode) -> String {
        switch code {
        case .permissionAccessibilityDenied:
            text("Autorisez l'Accessibilité pour Vibe Walkie sur le Mac.")
        case .localNetworkDenied:
            text("L'accès au réseau local est refusé.")
        case .macUnavailable:
            text("Mac introuvable. Vérifiez le Wi‑Fi, Tailscale et que le compagnon est ouvert.")
        case .speechAssetMissing:
            text("Le modèle de dictée local doit être téléchargé.")
        case .speechUnavailable:
            text("La transcription locale est indisponible sur cet appareil.")
        case .noFocusedTarget:
            text("Cliquez d'abord dans un champ de texte sur le Mac.")
        case .targetChanged:
            text("La fenêtre a changé pendant la dictée. Le texte n'a pas été inséré.")
        case .targetExpired:
            text("La cible a expiré. Recommencez la dictée.")
        case .secureField:
            text("Vibe Walkie n'insère jamais de dictée dans un champ sécurisé.")
        case .axNotSettable:
            text("Ce champ n'accepte pas l'écriture directe.")
        case .pasteNotConsumed:
            text("L'application n'a pas pris en compte le collage.")
        case .pasteboardChanged:
            text("Presse-papiers modifié entre-temps : restauration abandonnée.")
        case .windowUnavailableOnSpace:
            text("Cette fenêtre est sur un autre bureau. Ouvrez-le une fois sur le Mac.")
        case .applicationNotFound:
            text("Cette application n'est plus ouverte.")
        case .peerRevoked:
            text("Cet iPhone a été révoqué. Refaites l'appairage.")
        case .notPaired:
            text("Appareil non appairé.")
        case .pairingDenied:
            text("L'appairage a été refusé sur le Mac.")
        case .pairingApprovalExpired:
            text("La demande d'autorisation a expiré. Scannez de nouveau le QR.")
        case .protocolMismatch:
            text("Les versions de Vibe Walkie diffèrent. Mettez à jour l'iPhone et le Mac.")
        case .replayDetected:
            text("Message rejeté (rejeu détecté).")
        case .payloadTooLarge:
            text("Message trop volumineux.")
        case .rateLimited:
            text("Trop de commandes envoyées, ralentissez.")
        case .internalFailure:
            text("Erreur interne du compagnon Mac.")
        }
    }
}
