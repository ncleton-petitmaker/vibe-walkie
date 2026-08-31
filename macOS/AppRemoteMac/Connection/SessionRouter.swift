import Foundation
import AppKit
import RemoteCore

/// Exécute les commandes d'une session authentifiée.
///
/// Le routeur est la seule porte d'entrée vers les actions réelles. Chaque
/// commande passe par la validation de séquence, la limitation de débit, puis
/// une méthode dédiée : il n'existe pas de chemin générique qui exécuterait
/// une chaîne venue du réseau.
@MainActor
final class SessionRouter {

    private let targets = TargetTracker()
    private let insertion = TextInsertionCoordinator()
    private let windows = WindowCatalog()

    private var validator = SequenceValidator()
    private var gestureLimiter = RateLimiter(capacity: 240, refillPerSecond: 180)
    private var commandLimiter = RateLimiter(capacity: 40, refillPerSecond: 20)
    private var acknowledgements: [UUID: AcknowledgementPayload] = [:]

    let peerID: String
    let sessionID: String

    init(peerID: String, sessionID: String) {
        self.peerID = peerID
        self.sessionID = sessionID
    }

    enum Outcome {
        case acknowledge(AcknowledgementPayload)
        case snapshot(WindowsSnapshotPayload)
        case screenRequest(ScreenStreamRequestPayload)
        case controlConfigurationRequest
        case controlConfigurationUpdate(ControlConfiguration)
        case macShortcutPress(MacKeyboardShortcut)
        case failure(RemoteErrorPayload)
        case ignore
    }

    func handle(_ envelope: RemoteEnvelope) -> Outcome {
        guard envelope.version == ProtocolVersion.current else {
            return .failure(RemoteErrorPayload(code: .protocolMismatch))
        }

        switch validator.validate(envelope) {
        case .replay:
            return .failure(RemoteErrorPayload(code: .replayDetected))
        case .duplicate(let id):
            // Une commande renvoyée après une perte d'accusé ne doit jamais
            // être exécutée deux fois : on rejoue seulement la réponse.
            if let previous = acknowledgements[id] { return .acknowledge(previous) }
            return .ignore
        case .accepted:
            break
        }

        let isGesture = [.pointerMove, .pointerAbsolute, .pointerDrag, .scroll].contains(envelope.type)
        let allowed = isGesture ? gestureLimiter.allow() : commandLimiter.allow()
        guard allowed else {
            return .failure(RemoteErrorPayload(code: .rateLimited))
        }

        do {
            return try execute(envelope)
        } catch let error as RemoteErrorPayload {
            return .failure(error)
        } catch {
            return .failure(RemoteErrorPayload(code: .internalFailure, detail: error.localizedDescription))
        }
    }

    private func execute(_ envelope: RemoteEnvelope) throws -> Outcome {
        switch envelope.type {
        case .hello:
            // Battement de cœur authentifié. Il permet à l’iPhone de détecter
            // une socket silencieusement morte après veille ou mise à jour.
            _ = try? envelope.decodePayload(HelloPayload.self)
            return record(envelope, AcknowledgementPayload(ok: true))

        case .recordingStarted:
            let target = try targets.capture()
            let token = TargetToken(
                token: target.token,
                applicationName: target.applicationName,
                bundleIdentifier: target.bundleIdentifier,
                windowTitle: target.windowTitle,
                expiresAt: target.expiresAt
            )
            return record(envelope, AcknowledgementPayload(ok: true, targetToken: token))

        case .insertText:
            let payload = try envelope.decodePayload(InsertTextPayload.self)
            let target = try targets.resolve(token: payload.targetToken)
            let result = try insertion.insert(payload.text, into: target)
            targets.consume()
            return record(envelope, AcknowledgementPayload(ok: true, insertion: result))

        case .cancel:
            targets.consume()
            return record(envelope, AcknowledgementPayload(ok: true))

        case .keyboardText:
            let payload = try envelope.decodePayload(KeyboardTextPayload.self)
            guard payload.text.count <= 512 else {
                throw RemoteErrorPayload(code: .payloadTooLarge)
            }
            let result = try insertion.typeManually(payload.text, userInitiated: payload.userInitiated)
            return record(envelope, AcknowledgementPayload(ok: true, insertion: result))

        case .keyPress:
            let payload = try envelope.decodePayload(KeyPressPayload.self)
            CGEventFactory.press(payload.key)
            return record(envelope, AcknowledgementPayload(ok: true))

        case .macShortcutPress:
            let payload = try envelope.decodePayload(MacShortcutPressPayload.self)
            guard payload.shortcut.isValid else {
                throw RemoteErrorPayload(code: .internalFailure, detail: "Raccourci clavier invalide")
            }
            return .macShortcutPress(payload.shortcut)

        case .controlConfigurationRequest:
            return .controlConfigurationRequest

        case .controlConfigurationUpdate:
            let payload = try envelope.decodePayload(ControlConfigurationPayload.self)
            return .controlConfigurationUpdate(payload.configuration)

        case .pointerMove:
            let payload = try envelope.decodePayload(PointerMovePayload.self)
            CGEventFactory.move(
                deltaX: try ControlInputPolicy.gestureDelta(payload.deltaX),
                deltaY: try ControlInputPolicy.gestureDelta(payload.deltaY)
            )
            return .ignore

        case .pointerAbsolute:
            let payload = try envelope.decodePayload(PointerAbsolutePayload.self)
            CGEventFactory.moveAbsolute(
                normalizedX: try ControlInputPolicy.normalizedCoordinate(payload.normalizedX),
                normalizedY: try ControlInputPolicy.normalizedCoordinate(payload.normalizedY)
            )
            return .ignore

        case .pointerClick:
            let payload = try envelope.decodePayload(PointerClickPayload.self)
            CGEventFactory.click(button: payload.button, clickCount: payload.clickCount)
            return record(envelope, AcknowledgementPayload(ok: true))

        case .pointerDrag:
            let payload = try envelope.decodePayload(PointerDragPayload.self)
            CGEventFactory.drag(
                phase: payload.phase,
                deltaX: try ControlInputPolicy.gestureDelta(payload.deltaX),
                deltaY: try ControlInputPolicy.gestureDelta(payload.deltaY)
            )
            return .ignore

        case .scroll:
            let payload = try envelope.decodePayload(ScrollPayload.self)
            CGEventFactory.scroll(
                deltaX: try ControlInputPolicy.gestureDelta(payload.deltaX),
                deltaY: try ControlInputPolicy.gestureDelta(payload.deltaY)
            )
            return .ignore

        case .listWindows:
            let payload = (try? envelope.decodePayload(ListWindowsPayload.self)) ?? ListWindowsPayload()
            return .snapshot(windows.snapshot(includeIcons: payload.includeIcons))

        case .activateWindow:
            let payload = try envelope.decodePayload(ActivateWindowPayload.self)
            try windows.activate(applicationID: payload.applicationID, windowID: payload.windowID)
            return record(envelope, AcknowledgementPayload(ok: true))

        case .screenStreamRequest:
            return .screenRequest(try envelope.decodePayload(ScreenStreamRequestPayload.self))

        case .pairingChallenge, .pairingResponse, .pairingPending, .acknowledgement,
             .connectionStatus, .error, .windowsSnapshot, .screenStreamStatus,
             .screenFrame, .controlConfigurationSnapshot:
            return .ignore
        }
    }

    private func record(_ envelope: RemoteEnvelope, _ payload: AcknowledgementPayload) -> Outcome {
        acknowledgements[envelope.messageID] = payload
        if acknowledgements.count > 128 {
            acknowledgements.removeAll(keepingCapacity: true)
        }
        return .acknowledge(payload)
    }

}
