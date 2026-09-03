import Foundation

struct SpeechUpdate: Sendable {
    /// Texte visible sur l'iPhone : finalisé + hypothèse volatile courante.
    let text: String
    /// Préfixe cumulatif garanti immuable par SpeechAnalyzer. C'est le seul
    /// texte autorisé à partir vers le Mac.
    let finalizedText: String

    static let empty = SpeechUpdate(text: "", finalizedText: "")
}

/// Un moteur de transcription, vu par l'interface.
///
/// L'abstraction existe pour permettre d'ajouter Whisper local plus tard sans
/// toucher au bouton ni au réseau. Elle n'autorise pas un moteur distant :
/// toute implémentation doit garder l'audio sur l'appareil.
///
/// Isolé sur le main actor : l'état de dictée pilote directement l'interface,
/// et un moteur qui publierait depuis une file de fond obligerait chaque
/// implémentation à refaire la même synchronisation.
@MainActor
protocol SpeechEngine: AnyObject {
    /// Vérifie la disponibilité réelle sur ce matériel et prépare les modèles.
    func prepare() async throws

    /// Démarre la capture. Les résultats partiels arrivent par le flux.
    func start() async throws -> AsyncStream<SpeechUpdate>

    /// Termine et retourne le dernier texte entièrement finalisé.
    func finish() async throws -> SpeechUpdate

    /// Abandonne et détruit l'audio capturé.
    func cancel() async

    var isAvailable: Bool { get }
}

enum SpeechEngineError: LocalizedError {
    case unsupportedDevice
    case localeUnavailable(String)
    case assetMissing
    case microphoneDenied
    case speechRecognitionDenied
    case notPrepared

    var errorDescription: String? {
        switch self {
        case .unsupportedDevice:
            return AppL10n.text("ios.this.iphone.does.not.support.the.required.on.device.transcription.ab659af")
        case .localeUnavailable(let locale):
            return AppL10n.format("ios.the.value.language.is.not.available.on.device.on.this.76f6795", locale)
        case .assetMissing:
            return AppL10n.text("ios.the.on.device.dictation.model.must.be.downloaded.edc4230")
        case .microphoneDenied:
            return AppL10n.text("ios.microphone.access.is.disabled.for.vibe.walkie.0a0bf5b")
        case .speechRecognitionDenied:
            return AppL10n.text("ios.speech.recognition.is.disabled.for.vibe.walkie.cc53045")
        case .notPrepared:
            return AppL10n.text("ios.the.dictation.engine.is.not.ready.1365a2c")
        }
    }
}
