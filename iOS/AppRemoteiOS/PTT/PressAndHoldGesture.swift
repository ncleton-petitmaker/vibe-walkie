import SwiftUI
import UIKit

/// Geste Push-to-Talk adossé à UIKit.
///
/// Ce reconnaisseur UIKit garantit deux comportements indispensables :
///
/// - `touchesMoved` ne fait rien. Le doigt peut glisser n'importe où sans que
///   l'enregistrement s'arrête ; un `DragGesture` SwiftUI, lui, se fait annuler
///   dès qu'une vue ancêtre se recompose, ce qui ressemble à un doigt qui se
///   lève tout seul.
/// - Le délégué force la reconnaissance simultanée, sinon un défilement parent
///   promeut son propre geste et annule celui-ci en cours de dictée.
///
/// Il n'existe aucun seuil de pression : le bouton n'a qu'une seule action et
/// la capture doit commencer immédiatement.
struct PressAndHoldGesture: UIViewRepresentable {
    var onPressStart: () -> Void
    var onPressMoved: (CGPoint) -> Void
    var onPressEnd: () -> Void
    var onPressCancel: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true

        let recognizer = PressAndHoldRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handle(_:))
        )
        recognizer.delegate = context.coordinator
        recognizer.cancelsTouchesInView = false
        view.addGestureRecognizer(recognizer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: PressAndHoldGesture

        init(parent: PressAndHoldGesture) { self.parent = parent }

        @objc func handle(_ gesture: PressAndHoldRecognizer) {
            switch gesture.state {
            case .began:
                parent.onPressStart()
            case .changed:
                parent.onPressMoved(gesture.translation)
            case .ended:
                parent.onPressEnd()
            case .cancelled, .failed:
                // Appel entrant, Centre de contrôle : ce n'est pas un
                // relâchement volontaire, donc jamais un envoi.
                parent.onPressCancel()
            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy other: UIGestureRecognizer
        ) -> Bool { false }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRequireFailureOf other: UIGestureRecognizer
        ) -> Bool { false }
    }
}

final class PressAndHoldRecognizer: UIGestureRecognizer {
    private var origin: CGPoint = .zero
    private(set) var translation: CGPoint = .zero

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        origin = touches.first?.location(in: view) ?? .zero
        translation = .zero
        state = .began
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        // Volontairement sans annulation : le doigt peut aller où il veut.
        // On rapporte seulement le déplacement, pour armer « glisser pour annuler ».
        guard let location = touches.first?.location(in: view) else { return }
        translation = CGPoint(x: location.x - origin.x, y: location.y - origin.y)
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        state = .cancelled
    }
}
