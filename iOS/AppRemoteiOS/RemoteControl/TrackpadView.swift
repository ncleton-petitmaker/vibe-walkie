import SwiftUI
import UIKit
import RemoteCore

/// Grande surface tactile, inspirée de la disposition de la Télécommande Apple.
///
/// Les événements sont envoyés sans attendre d'accusé : un pointeur qui
/// attendrait une confirmation à chaque déplacement serait inutilisable. La
/// perte occasionnelle d'un mouvement est sans conséquence, contrairement à la
/// perte d'une insertion de texte.
struct TrackpadView: View {
    @EnvironmentObject private var client: MacConnectionClient
    @AppStorage("trackpadSensitivity") private var sensitivity: Double = 1.6
    @AppStorage("scrollSensitivity") private var scrollSensitivity: Double = 0.8

    var body: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Color.trackpadSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
            .overlay(hint)
            .overlay {
                TouchpadSurface(
                    onMove: { delta in
                        client.sendFireAndForget(
                            type: .pointerMove,
                            payload: PointerMovePayload(
                                deltaX: delta.x * sensitivity,
                                deltaY: delta.y * sensitivity
                            )
                        )
                    },
                    onScroll: { delta in
                        client.sendFireAndForget(
                            type: .scroll,
                            payload: ScrollPayload(
                                deltaX: delta.x * scrollSensitivity,
                                deltaY: delta.y * scrollSensitivity
                            )
                        )
                    },
                    onClick: {
                        HapticFeedback.shared.tick()
                        client.sendFireAndForget(
                            type: .pointerClick,
                            payload: PointerClickPayload(button: .left, clickCount: 1)
                        )
                    },
                    onDrag: { phase, delta in
                        client.sendFireAndForget(
                            type: .pointerDrag,
                            payload: PointerDragPayload(
                                phase: phase,
                                deltaX: delta.x * sensitivity,
                                deltaY: delta.y * sensitivity
                            )
                        )
                    }
                )
            }
            .overlay(alignment: .trailing) {
                scrollStripHint
            }
            .contentShape(Rectangle())
            .accessibilityLabel("Pavé tactile")
            .accessibilityHint("Un doigt déplace le curseur, un toucher clique, et la bande à droite ou deux doigts font défiler.")
    }

    private var hint: some View {
        VStack(spacing: 6) {
            Image(systemName: "hand.point.up.left")
                .font(.system(size: 26, weight: .light))
            Text("Pavé tactile")
                .font(.footnote)
        }
        .foregroundStyle(Color.remoteBlue.opacity(0.28))
        .allowsHitTesting(false)
    }

    private var scrollStripHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "chevron.up")
            Capsule()
                .frame(width: 3, height: 24)
            Image(systemName: "chevron.down")
        }
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(Color.remoteBlue.opacity(0.38))
        .frame(width: 34, height: 104)
        .background(Capsule().fill(Color.black.opacity(0.12)))
        .overlay(alignment: .leading) {
            Capsule()
                .fill(Color.white.opacity(0.1))
                .frame(width: 1, height: 72)
        }
        .frame(width: TouchpadUIView.scrollStripWidth)
        .allowsHitTesting(false)
    }

}

/// Surface UIKit multitouch. SwiftUI ne permet pas d'imposer deux doigts à
/// un `DragGesture`; superposer deux glissements faisait donc défiler et bouger
/// le pointeur en même temps.
private struct TouchpadSurface: UIViewRepresentable {
    var onMove: (CGPoint) -> Void
    var onScroll: (CGPoint) -> Void
    var onClick: () -> Void
    var onDrag: (DragPhase, CGPoint) -> Void

    func makeUIView(context: Context) -> TouchpadUIView {
        let view = TouchpadUIView()
        update(view)
        return view
    }

    func updateUIView(_ uiView: TouchpadUIView, context: Context) {
        update(uiView)
    }

    private func update(_ view: TouchpadUIView) {
        view.onMove = onMove
        view.onScroll = onScroll
        view.onClick = onClick
        view.onDrag = onDrag
    }
}

private final class TouchpadUIView: UIView, UIGestureRecognizerDelegate {
    static let scrollStripWidth: CGFloat = 48

    var onMove: ((CGPoint) -> Void)?
    var onScroll: ((CGPoint) -> Void)?
    var onClick: (() -> Void)?
    var onDrag: ((DragPhase, CGPoint) -> Void)?
    private var previousDragPoint: CGPoint?

    private lazy var moveGesture = makePan(touches: 1, action: #selector(handleMove(_:)))
    private lazy var scrollGesture = makePan(touches: 2, action: #selector(handleScroll(_:)))
    private lazy var scrollStripGesture = makePan(touches: 1, action: #selector(handleScrollStrip(_:)))
    private lazy var dragGesture: UILongPressGestureRecognizer = {
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handleDrag(_:)))
        gesture.minimumPressDuration = 0.45
        gesture.allowableMovement = 18
        gesture.numberOfTouchesRequired = 1
        gesture.delegate = self
        return gesture
    }()
    private lazy var tapGesture: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleClick))
        gesture.numberOfTouchesRequired = 1
        gesture.delegate = self
        gesture.require(toFail: dragGesture)
        return gesture
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true

        addGestureRecognizer(moveGesture)
        addGestureRecognizer(scrollGesture)
        addGestureRecognizer(scrollStripGesture)
        addGestureRecognizer(dragGesture)
        addGestureRecognizer(tapGesture)
    }

    required init?(coder: NSCoder) { nil }

    private func makePan(touches: Int, action: Selector) -> UIPanGestureRecognizer {
        let gesture = UIPanGestureRecognizer(target: self, action: action)
        gesture.minimumNumberOfTouches = touches
        gesture.maximumNumberOfTouches = touches
        gesture.delegate = self
        return gesture
    }

    @objc private func handleMove(_ gesture: UIPanGestureRecognizer) {
        guard dragGesture.state != .began && dragGesture.state != .changed else { return }
        guard gesture.state == .changed else { return }
        let delta = gesture.translation(in: self)
        gesture.setTranslation(.zero, in: self)
        onMove?(delta)
    }

    @objc private func handleScroll(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .changed else { return }
        let delta = gesture.translation(in: self)
        gesture.setTranslation(.zero, in: self)
        onScroll?(delta)
    }

    @objc private func handleScrollStrip(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .changed else { return }
        let delta = gesture.translation(in: self)
        gesture.setTranslation(.zero, in: self)
        onScroll?(CGPoint(x: 0, y: delta.y))
    }

    @objc private func handleClick() { onClick?() }

    @objc private func handleDrag(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            HapticFeedback.shared.armedForCancel()
            previousDragPoint = gesture.location(in: self)
            onDrag?(.began, .zero)
        case .changed:
            let location = gesture.location(in: self)
            let previous = previousDragPoint ?? location
            onDrag?(.moved, CGPoint(x: location.x - previous.x, y: location.y - previous.y))
            previousDragPoint = location
        case .ended, .cancelled, .failed:
            previousDragPoint = nil
            onDrag?(.ended, .zero)
        default:
            break
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        (gestureRecognizer === moveGesture && otherGestureRecognizer === dragGesture)
            || (gestureRecognizer === dragGesture && otherGestureRecognizer === moveGesture)
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let startsInScrollStrip = gestureRecognizer.location(in: self).x
            >= bounds.maxX - Self.scrollStripWidth

        if gestureRecognizer === scrollStripGesture {
            guard startsInScrollStrip else { return false }
            let velocity = scrollStripGesture.velocity(in: self)
            return abs(velocity.y) > abs(velocity.x) * 0.6
        }

        if gestureRecognizer === moveGesture
            || gestureRecognizer === dragGesture
            || gestureRecognizer === tapGesture {
            return !startsInScrollStrip
        }

        return true
    }
}

extension Color {
    /// Palette inspirée des télécommandes de bureau sombres : noir profond,
    /// cartes anthracite et un seul accent bleu très lisible.
    static let appBackground = Color(red: 0.035, green: 0.038, blue: 0.042)
    static let appChrome = Color(red: 0.075, green: 0.078, blue: 0.082)
    static let trackpadSurface = Color(red: 0.105, green: 0.115, blue: 0.12)
    static let controlSurface = Color(red: 0.135, green: 0.145, blue: 0.15)
    static let dockSurface = Color(red: 0.12, green: 0.125, blue: 0.13)
    static let remoteBlue = Color(red: 0.02, green: 0.56, blue: 0.98)
}
