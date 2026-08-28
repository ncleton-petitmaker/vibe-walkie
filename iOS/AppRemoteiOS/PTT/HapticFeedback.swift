import UIKit

/// Retours haptiques du bouton.
///
/// Les générateurs sont conservés et préparés à l'avance : en créer un juste
/// avant de le déclencher peut retarder la vibration, en particulier au moment
/// où la session audio s'active.
@MainActor
final class HapticFeedback {
    static let shared = HapticFeedback()

    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notification = UINotificationFeedbackGenerator()

    private init() {}

    func prepare() {
        light.prepare()
        medium.prepare()
        heavy.prepare()
        notification.prepare()
    }

    func recordingStarted() { heavy.impactOccurred(intensity: 1.0) }
    func armedForCancel() { medium.impactOccurred() }
    func tick() { light.impactOccurred() }
    func delivered() { notification.notificationOccurred(.success) }
    func failed() { notification.notificationOccurred(.error) }
}
