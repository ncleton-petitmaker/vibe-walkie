import SwiftUI
import UIKit
import RemoteCore

enum TrackpadSettings {
    static let pointerRange = 0.5...6.0
    static let scrollRange = 0.2...5.0
    static let defaultPointerSpeed = 2.0
    static let defaultScrollSpeed = 1.2

    private static let pointerKey = "trackpadSensitivity"
    private static let scrollKey = "scrollSensitivity"
    private static let expandedSpeedMigrationKey = "expandedTrackpadSpeedRangeV1"

    /// Conserve l'intention des personnes qui avaient choisi l'ancien maximum,
    /// sans les propulser brutalement au nouveau plafond dès la mise à jour.
    static func migrateExpandedSpeedRange(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: expandedSpeedMigrationKey) else { return }

        if defaults.object(forKey: pointerKey) != nil,
           defaults.double(forKey: pointerKey) >= 2.95 {
            defaults.set(5.0, forKey: pointerKey)
        }
        if defaults.object(forKey: scrollKey) != nil,
           defaults.double(forKey: scrollKey) >= 1.95 {
            defaults.set(4.0, forKey: scrollKey)
        }
        defaults.set(true, forKey: expandedSpeedMigrationKey)
    }
}

enum TrackpadGestureMath {
    /// Une variation logarithmique garde le zoom symétrique : écarter de 20 %
    /// puis rapprocher de 20 % produit des deltas opposés, sans accélération
    /// artificielle liée à la fréquence des événements UIKit.
    static func zoomDelta(forIncrementalScale scale: CGFloat) -> Double {
        guard scale.isFinite, scale > 0 else { return 0 }
        return log(Double(scale)) * 120
    }
}

/// Regroupe les événements UIKit reçus entre deux envois. Un glissement peut
/// produire bien plus de callbacks que le réseau et le Mac ne peuvent en
/// afficher ; additionner les deltas conserve exactement le déplacement sans
/// créer une file qui ferait suivre le curseur avec retard.
struct TrackpadPendingDeltas: Equatable {
    var move = CGPoint.zero
    var scroll = CGPoint.zero
    var zoom = 0.0
    var drag = CGPoint.zero

    var isEmpty: Bool {
        move == .zero && scroll == .zero && zoom == 0 && drag == .zero
    }

    mutating func drain() -> Self {
        let drained = self
        self = .init()
        return drained
    }
}

enum TrackpadAppearance: Equatable {
    case surface
    case screenOverlay
}

/// Grande surface tactile, inspirée de la disposition de la Télécommande Apple.
///
/// Les événements sont envoyés sans attendre d'accusé : un pointeur qui
/// attendrait une confirmation à chaque déplacement serait inutilisable. La
/// perte occasionnelle d'un mouvement est sans conséquence, contrairement à la
/// perte d'une insertion de texte.
struct TrackpadView: View {
    @EnvironmentObject private var client: HostConnectionClient
    @AppStorage("trackpadSensitivity") private var sensitivity: Double = TrackpadSettings.defaultPointerSpeed
    @AppStorage("scrollSensitivity") private var scrollSensitivity: Double = TrackpadSettings.defaultScrollSpeed
    var appearance: TrackpadAppearance = .surface

    var body: some View {
        ZStack {
            if appearance == .surface {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.trackpadSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
                    .overlay(hint)
            } else {
                Color.clear
            }

            touchSurface
        }
        .overlay(alignment: .trailing) {
            scrollStripHint
        }
        .contentShape(Rectangle())
        .accessibilityLabel("ios.trackpad.c8dc586")
        .accessibilityHint("ios.one.finger.moves.the.pointer.a.tap.clicks.and.the.3ff0c11")
    }

    private var touchSurface: some View {
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
            onZoom: { delta in
                client.sendFireAndForget(
                    type: .scroll,
                    payload: ScrollPayload(deltaX: 0, deltaY: delta, zoom: true)
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

    private var hint: some View {
        VStack(spacing: 6) {
            Image(systemName: "hand.point.up.left")
                .font(.system(size: 26, weight: .light))
            Text("ios.trackpad.c8dc586")
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
        .background(Capsule().fill(Color.black.opacity(appearance == .screenOverlay ? 0.46 : 0.12)))
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
    var onZoom: (Double) -> Void
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
        view.onZoom = onZoom
        view.onClick = onClick
        view.onDrag = onDrag
    }
}

private final class TouchpadUIView: UIView, UIGestureRecognizerDelegate {
    static let scrollStripWidth: CGFloat = 48

    var onMove: ((CGPoint) -> Void)?
    var onScroll: ((CGPoint) -> Void)?
    var onZoom: ((Double) -> Void)?
    var onClick: (() -> Void)?
    var onDrag: ((DragPhase, CGPoint) -> Void)?
    private var previousDragPoint: CGPoint?
    private var pendingDeltas = TrackpadPendingDeltas()
    private var lastContinuousFlushTime: CFTimeInterval = 0
    private static let minimumFlushInterval: CFTimeInterval = 1.0 / 30.0

    private lazy var moveGesture = makePan(touches: 1, action: #selector(handleMove(_:)))
    private lazy var scrollGesture = makePan(touches: 2, action: #selector(handleScroll(_:)))
    private lazy var pinchGesture: UIPinchGestureRecognizer = {
        let gesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        gesture.delegate = self
        return gesture
    }()
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
        addGestureRecognizer(pinchGesture)
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
        switch gesture.state {
        case .changed:
            let delta = gesture.translation(in: self)
            gesture.setTranslation(.zero, in: self)
            pendingDeltas.move.x += delta.x
            pendingDeltas.move.y += delta.y
            scheduleFlush()
        case .ended, .cancelled, .failed:
            flushPendingEvents()
        default:
            break
        }
    }

    @objc private func handleScroll(_ gesture: UIPanGestureRecognizer) {
        guard pinchGesture.state != .began && pinchGesture.state != .changed else { return }
        switch gesture.state {
        case .changed:
            let delta = gesture.translation(in: self)
            gesture.setTranslation(.zero, in: self)
            pendingDeltas.scroll.x += delta.x
            pendingDeltas.scroll.y += delta.y
            scheduleFlush()
        case .ended, .cancelled, .failed:
            flushPendingEvents()
        default:
            break
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
            flushPendingEvents()
            return
        }
        guard gesture.state == .began || gesture.state == .changed else { return }
        let delta = TrackpadGestureMath.zoomDelta(forIncrementalScale: gesture.scale)
        gesture.scale = 1
        guard abs(delta) >= 0.1 else { return }
        pendingDeltas.zoom += delta
        scheduleFlush()
    }

    @objc private func handleScrollStrip(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .changed:
            let delta = gesture.translation(in: self)
            gesture.setTranslation(.zero, in: self)
            pendingDeltas.scroll.y += delta.y
            scheduleFlush()
        case .ended, .cancelled, .failed:
            flushPendingEvents()
        default:
            break
        }
    }

    @objc private func handleClick() {
        flushPendingEvents()
        onClick?()
    }

    @objc private func handleDrag(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            flushPendingEvents()
            HapticFeedback.shared.armedForCancel()
            previousDragPoint = gesture.location(in: self)
            onDrag?(.began, .zero)
        case .changed:
            let location = gesture.location(in: self)
            let previous = previousDragPoint ?? location
            pendingDeltas.drag.x += location.x - previous.x
            pendingDeltas.drag.y += location.y - previous.y
            previousDragPoint = location
            scheduleFlush()
        case .ended, .cancelled, .failed:
            flushPendingEvents()
            previousDragPoint = nil
            onDrag?(.ended, .zero)
        default:
            break
        }
    }

    private func scheduleFlush() {
        // Aucun minuteur et aucune boucle à 60 Hz : on ne travaille que lors
        // d'un vrai événement tactile. Au-delà de 30 envois/s, les deltas
        // restent simplement agrégés jusqu'au prochain événement ou jusqu'à
        // la fin du geste.
        let now = CACurrentMediaTime()
        guard now - lastContinuousFlushTime >= Self.minimumFlushInterval else { return }
        flushPendingEvents(at: now)
    }

    @objc private func flushPendingEvents() {
        flushPendingEvents(at: CACurrentMediaTime())
    }

    private func flushPendingEvents(at time: CFTimeInterval) {
        guard !pendingDeltas.isEmpty else { return }
        let drained = pendingDeltas.drain()
        lastContinuousFlushTime = time
        if drained.move != .zero { onMove?(drained.move) }
        if drained.scroll != .zero { onScroll?(drained.scroll) }
        if drained.zoom != 0 { onZoom?(drained.zoom) }
        if drained.drag != .zero { onDrag?(.moved, drained.drag) }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        (gestureRecognizer === moveGesture && otherGestureRecognizer === dragGesture)
            || (gestureRecognizer === dragGesture && otherGestureRecognizer === moveGesture)
            || (gestureRecognizer === scrollGesture && otherGestureRecognizer === pinchGesture)
            || (gestureRecognizer === pinchGesture && otherGestureRecognizer === scrollGesture)
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
