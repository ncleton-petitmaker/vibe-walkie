import Foundation
import Network
import AppKit
import CoreGraphics
import RemoteCore

/// Serveur local : publication Bonjour, TLS, authentification, routage des
/// commandes et diffusion bornée de l'écran.
@MainActor
final class MacConnectionServer: ObservableObject {

    @Published private(set) var isListening = false
    @Published private(set) var connectedPeerName: String?
    @Published private(set) var lastError: String?
    @Published private(set) var serviceName: String = ""
    @Published private(set) var nomadEndpoint: NomadEndpoint?
    @Published private(set) var hasCompletedFirstCommand: Bool
    @Published private(set) var controlConfiguration: ControlConfiguration

    private var listener: NWListener?
    private var identity: SecIdentity?
    private var sessions: [ObjectIdentifier: Session] = [:]
    private let screenCapture = ScreenCaptureService()
    private var screenCaptureRunning = false
    private var screenCaptureStarting = false
    private var connectionLimiter = RateLimiter(capacity: 20, refillPerSecond: 1.0 / 3.0)

    private let peers: ApprovedPeersStore
    private let authority: PairingAuthority

    /// Une connexion en cours de vie, avec son état d'authentification.
    ///
    /// Isolée sur le main actor comme le serveur : tout le traitement réseau
    /// est séquentiel ici, ce qui évite d'avoir à raisonner sur des accès
    /// concurrents à l'état d'authentification.
    @MainActor
    private final class Session {
        let connection: NWConnection
        var framer = MessageFramer()
        var nonce: Data
        var router: SessionRouter?
        var sequence: UInt64 = 0
        var wantsScreen = false
        var screenFrameInFlight = false
        var pendingApprovalID: UUID?
        var pendingApprovalReplyTo: UUID?
        var approvalExpiryTask: Task<Void, Never>?
        var authenticationExpiryTask: Task<Void, Never>?
        let sessionID = UUID().uuidString

        init(connection: NWConnection) {
            self.connection = connection
            self.nonce = SecureRandom.bytes(32)
        }

        var isAuthenticated: Bool { router != nil }
    }

    init(
        peers: ApprovedPeersStore,
        authority: PairingAuthority,
        nomadEndpoint: NomadEndpoint? = nil
    ) {
        self.peers = peers
        self.authority = authority
        self.nomadEndpoint = nomadEndpoint?.isValid == true ? nomadEndpoint : nil
        self.hasCompletedFirstCommand = UserDefaults.standard.bool(forKey: "hasCompletedFirstCommand")
        self.controlConfiguration = Self.loadControlConfiguration()
    }

    var certificateFingerprint: String? {
        guard let identity else { return nil }
        return try? TLSIdentityStore.fingerprint(of: identity)
    }

    // MARK: - Cycle de vie

    func start() {
        guard listener == nil else { return }
        do {
            let identity = try TLSIdentityStore.loadOrCreate()
            self.identity = identity

            let parameters = try makeParameters(identity: identity)
            guard let port = NWEndpoint.Port(rawValue: VibeWalkieInfo.controlPort) else {
                throw RemoteErrorPayload(code: .internalFailure, detail: "port invalide")
            }
            let listener = try NWListener(using: parameters, on: port)

            // Le nom historique basé uniquement sur le Mac pouvait rester
            // réservé par une ancienne installation Bonjour et faire échouer
            // la nouvelle publication avec EADDRINUSE. Le certificat est
            // propre à cette installation : son préfixe donne un nom stable,
            // unique et dépourvu de donnée personnelle supplémentaire.
            let fingerprint = try TLSIdentityStore.fingerprint(of: identity)
            let suffix = String(fingerprint.filter { $0.isLetter || $0.isNumber }.prefix(8))
            let host = String((Host.current().localizedName ?? "Mac").prefix(30))
            // Le nom Bonjour est également un identifiant technique durable.
            // Conserver le préfixe historique évite de casser les iPhone déjà
            // appairés lors d'une simple mise à jour ou d'un renommage produit.
            let name = "VibeRemote-\(host)-\(suffix)"
            listener.service = NWListener.Service(name: name, type: VibeWalkieInfo.bonjourServiceType)
            self.serviceName = name

            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in self?.handleListenerState(state) }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }

            listener.start(queue: .main)
            self.listener = listener
        } catch {
            lastError = "Impossible de démarrer le service : \(error.localizedDescription)"
        }
    }

    /// Répare une identité TLS partielle ou corrompue. Une nouvelle empreinte
    /// invalide nécessairement tous les appareils précédemment appairés.
    func regenerateTLSIdentity() {
        stop()
        do {
            _ = try TLSIdentityStore.regenerate()
            peers.revokeAll()
            lastError = nil
            start()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func resetEverything() {
        authority.cancelPendingApproval()
        peers.revokeAll()
        regenerateTLSIdentity()
        UserDefaults.standard.set(false, forKey: "hasCompletedFirstCommand")
        hasCompletedFirstCommand = false
    }

    func stop() {
        sessions.values.forEach {
            $0.approvalExpiryTask?.cancel()
            $0.authenticationExpiryTask?.cancel()
            $0.connection.cancel()
        }
        sessions.removeAll()
        listener?.cancel()
        listener = nil
        isListening = false
        connectedPeerName = nil
        screenCaptureRunning = false
        screenCaptureStarting = false
        Task { await screenCapture.stop() }
    }

    /// Ferme immédiatement les sessions d'un appareil révoqué.
    func disconnectPeer(_ peerID: String) {
        for (key, session) in sessions where session.router?.peerID == peerID {
            session.connection.cancel()
            sessions.removeValue(forKey: key)
        }
        if sessions.isEmpty { connectedPeerName = nil }
        stopScreenCaptureWhenUnused()
    }

    private func makeParameters(identity: SecIdentity) throws -> NWParameters {
        let options = NWProtocolTLS.Options()
        guard let secIdentity = sec_identity_create(identity) else {
            throw RemoteErrorPayload(code: .internalFailure, detail: "identité TLS invalide")
        }
        sec_protocol_options_set_local_identity(options.securityProtocolOptions, secIdentity)
        sec_protocol_options_set_min_tls_protocol_version(options.securityProtocolOptions, .TLSv13)

        let parameters = NWParameters(tls: options)
        parameters.includePeerToPeer = true
        return parameters
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            isListening = true
            lastError = nil
        case .failed(let error):
            isListening = false
            lastError = error.localizedDescription
        case .cancelled:
            isListening = false
        default:
            break
        }
    }

    // MARK: - Connexions

    private func accept(_ connection: NWConnection) {
        let unauthenticatedCount = sessions.values.filter { !$0.isAuthenticated }.count
        guard unauthenticatedCount < 8, connectionLimiter.allow() else {
            connection.cancel()
            return
        }
        let session = Session(connection: connection)
        sessions[ObjectIdentifier(connection)] = session
        session.authenticationExpiryTask = Task { [weak connection] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            connection?.cancel()
        }

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    self.sendChallenge(session)
                case .failed, .cancelled:
                    session.approvalExpiryTask?.cancel()
                    session.authenticationExpiryTask?.cancel()
                    if let requestID = session.pendingApprovalID {
                        _ = self.authority.cancelPendingApproval(requestID)
                    }
                    self.sessions.removeValue(forKey: ObjectIdentifier(connection))
                    if self.sessions.isEmpty { self.connectedPeerName = nil }
                    self.stopScreenCaptureWhenUnused()
                default:
                    break
                }
            }
        }
        connection.start(queue: .main)
        receive(session)
    }

    private func receive(_ session: Session) {
        session.connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else { return }
                if let data, !data.isEmpty {
                    self.ingest(data, into: session)
                }
                if isComplete || error != nil {
                    session.connection.cancel()
                    return
                }
                self.receive(session)
            }
        }
    }

    private func ingest(_ data: Data, into session: Session) {
        let messages: [Data]
        do {
            messages = try session.framer.append(data)
        } catch {
            // Trame invalide ou surdimensionnée : on coupe, sans négocier.
            session.connection.cancel()
            return
        }

        for message in messages {
            guard let envelope = try? RemoteCoding.decoder.decode(RemoteEnvelope.self, from: message) else {
                session.connection.cancel()
                return
            }
            process(envelope, in: session)
        }
    }

    private func process(_ envelope: RemoteEnvelope, in session: Session) {
        guard envelope.version == ProtocolVersion.current else {
            sendAndClose(
                error: RemoteErrorPayload(code: .protocolMismatch),
                to: session,
                replyTo: envelope.messageID
            )
            return
        }
        guard session.isAuthenticated else {
            // Avant authentification, un seul type de message est recevable.
            guard envelope.type == .pairingResponse,
                  let payload = try? envelope.decodePayload(PairingResponsePayload.self) else {
                sendAndClose(
                    error: RemoteErrorPayload(code: .notPaired),
                    to: session,
                    replyTo: envelope.messageID
                )
                return
            }
            do {
                switch try authority.authenticate(response: payload, nonce: session.nonce) {
                case .approved(let peer):
                    establishAuthenticatedSession(session, peer: peer, replyTo: envelope.messageID)
                case .requiresApproval(let pending):
                    session.pendingApprovalID = pending.id
                    session.pendingApprovalReplyTo = envelope.messageID
                    send(
                        type: .pairingPending,
                        payload: PairingPendingPayload(
                            requestID: pending.id,
                            deviceName: pending.peer.name,
                            confirmationCode: pending.confirmationCode,
                            expiresAt: pending.expiresAt
                        ),
                        to: session,
                        replyTo: envelope.messageID
                    )
                    session.approvalExpiryTask = Task { [weak self, weak session] in
                        try? await Task.sleep(for: .seconds(VibeWalkieInfo.pairingApprovalWindow))
                        guard !Task.isCancelled, let self, let session else { return }
                        await MainActor.run { self.expirePairing(pending.id, in: session) }
                    }
                }
            } catch let error as RemoteErrorPayload {
                sendAndClose(error: error, to: session, replyTo: envelope.messageID)
            } catch {
                session.connection.cancel()
            }
            return
        }

        guard let router = session.router else { return }
        switch router.handle(envelope) {
        case .acknowledge(let payload):
            if payload.ok && ![.hello, .recordingStarted, .cancel].contains(envelope.type) {
                markFirstCommandCompleted()
            }
            send(type: .acknowledgement, payload: payload, to: session, replyTo: envelope.messageID)
        case .snapshot(let payload):
            send(type: .windowsSnapshot, payload: payload, to: session, replyTo: envelope.messageID)
        case .screenRequest(let payload):
            handleScreenRequest(payload, for: session, replyTo: envelope.messageID)
        case .controlConfigurationRequest:
            sendControlConfiguration(to: session, replyTo: envelope.messageID)
        case .controlConfigurationUpdate(let configuration):
            updateControlConfigurationFromPeer(configuration)
            send(
                type: .acknowledgement,
                payload: AcknowledgementPayload(ok: true),
                to: session,
                replyTo: envelope.messageID
            )
        case .macShortcutPress(let shortcut):
            let configuredActions = controlConfiguration.buttons.map(\.action) +
                controlConfiguration.globalButtons.map(\.action)
            let isConfigured = configuredActions.contains { action in
                guard case .macShortcut(let configured) = action else { return false }
                return configured == shortcut
            }
            guard isConfigured else {
                send(
                    error: RemoteErrorPayload(code: .internalFailure, detail: "Raccourci non configuré"),
                    to: session,
                    replyTo: envelope.messageID
                )
                break
            }
            CGEventFactory.press(shortcut)
            send(
                type: .acknowledgement,
                payload: AcknowledgementPayload(ok: true),
                to: session,
                replyTo: envelope.messageID
            )
        case .failure(let error):
            send(error: error, to: session, replyTo: envelope.messageID)
        case .ignore:
            break
        }
    }

    private func markFirstCommandCompleted() {
        guard !hasCompletedFirstCommand else { return }
        hasCompletedFirstCommand = true
        UserDefaults.standard.set(true, forKey: "hasCompletedFirstCommand")
    }

    func approvePairing(_ requestID: UUID) {
        guard let session = sessions.values.first(where: { $0.pendingApprovalID == requestID }),
              let peer = authority.approve(requestID) else {
            if let session = sessions.values.first(where: { $0.pendingApprovalID == requestID }) {
                expirePairing(requestID, in: session)
            }
            return
        }
        session.approvalExpiryTask?.cancel()
        let replyTo = session.pendingApprovalReplyTo
        session.pendingApprovalID = nil
        session.pendingApprovalReplyTo = nil
        establishAuthenticatedSession(session, peer: peer, replyTo: replyTo)
    }

    func denyPairing(_ requestID: UUID) {
        guard let session = sessions.values.first(where: { $0.pendingApprovalID == requestID }) else { return }
        session.approvalExpiryTask?.cancel()
        _ = authority.cancelPendingApproval(requestID)
        sendAndClose(
            error: RemoteErrorPayload(code: .pairingDenied),
            to: session,
            replyTo: session.pendingApprovalReplyTo
        )
    }

    private func expirePairing(_ requestID: UUID, in session: Session) {
        guard session.pendingApprovalID == requestID else { return }
        _ = authority.cancelPendingApproval(requestID)
        sendAndClose(
            error: RemoteErrorPayload(code: .pairingApprovalExpired),
            to: session,
            replyTo: session.pendingApprovalReplyTo
        )
    }

    private func establishAuthenticatedSession(_ session: Session, peer: ApprovedPeer, replyTo: UUID?) {
        session.authenticationExpiryTask?.cancel()
        session.authenticationExpiryTask = nil
        session.router = SessionRouter(peerID: peer.id, sessionID: session.sessionID)
        connectedPeerName = peer.name
        sendConnectionStatus(to: session, replyTo: replyTo)
        sendControlConfiguration(to: session, replyTo: nil)
    }

    func setNomadEndpoint(_ endpoint: NomadEndpoint?) {
        nomadEndpoint = endpoint?.isValid == true ? endpoint : nil
        for session in sessions.values where session.isAuthenticated {
            sendConnectionStatus(to: session, replyTo: nil)
        }
    }

    private func sendConnectionStatus(to session: Session, replyTo: UUID?) {
        send(
            type: .connectionStatus,
            payload: ConnectionStatusPayload(
                accessibilityGranted: AccessibilityClient.isTrusted,
                macName: Host.current().localizedName ?? "Mac",
                companionVersion: Bundle.main.appVersion,
                nomadEndpoint: nomadEndpoint
            ),
            to: session,
            replyTo: replyTo
        )
    }

    // MARK: - Bloc de commandes

    /// Le Mac conserve la copie de référence afin qu'un nouvel iPhone retrouve
    /// immédiatement la disposition et les raccourcis matériels enregistrés.
    func updateControlConfiguration(_ requested: ControlConfiguration) {
        var sanitized = Self.sanitizedControlConfiguration(requested)
        sanitized.revision = controlConfiguration.revision &+ 1
        sanitized.updatedAt = Date()
        controlConfiguration = sanitized

        if let data = try? RemoteCoding.encoder.encode(sanitized) {
            UserDefaults.standard.set(data, forKey: Self.controlConfigurationDefaultsKey)
        }

        for session in sessions.values where session.isAuthenticated {
            sendControlConfiguration(to: session, replyTo: nil)
        }
    }

    func resetControlConfiguration() {
        updateControlConfiguration(.standard)
    }

    /// L'iPhone peut déplacer/remplacer les actions existantes, mais il ne
    /// peut pas fabriquer un keycode matériel. Une combinaison Mac déjà
    /// présente peut seulement être conservée à l'identique.
    private func updateControlConfigurationFromPeer(_ requested: ControlConfiguration) {
        var restricted = requested
        for zone in ControlZone.allCases {
            var proposed = restricted.button(in: zone)
            guard case .macShortcut = proposed.action,
                  proposed.action != controlConfiguration.button(in: zone).action else { continue }

            let currentAction = controlConfiguration.button(in: zone).action
            if case .macShortcut = currentAction {
                proposed.action = currentAction
            } else {
                proposed.action = .none
            }
            restricted.setButton(proposed)
        }
        restricted.globalButtons = restricted.globalButtons.map { proposed in
            guard case .macShortcut = proposed.action,
                  proposed.action != controlConfiguration.globalButtons.first(where: { $0.id == proposed.id })?.action else {
                return proposed
            }
            var safe = proposed
            let currentAction = controlConfiguration.globalButtons.first(where: { $0.id == proposed.id })?.action
            if let currentAction, case .macShortcut = currentAction {
                safe.action = currentAction
            } else {
                safe.action = .none
            }
            return safe
        }
        updateControlConfiguration(restricted)
    }

    private func sendControlConfiguration(to session: Session, replyTo: UUID?) {
        send(
            type: .controlConfigurationSnapshot,
            payload: ControlConfigurationPayload(configuration: controlConfiguration),
            to: session,
            replyTo: replyTo
        )
    }

    private static let controlConfigurationDefaultsKey = "controlConfiguration.v1"

    private static func loadControlConfiguration() -> ControlConfiguration {
        guard let data = UserDefaults.standard.data(forKey: controlConfigurationDefaultsKey),
              let decoded = try? RemoteCoding.decoder.decode(ControlConfiguration.self, from: data) else {
            return .standard
        }
        return sanitizedControlConfiguration(decoded)
    }

    /// Évite qu'une image importée ou une configuration incomplète ne dépasse
    /// la taille maximale d'une trame réseau.
    private static func sanitizedControlConfiguration(_ requested: ControlConfiguration) -> ControlConfiguration {
        var buttons: [ControlButtonConfiguration] = []
        var globalButtons: [GlobalButtonConfiguration] = []
        var customImageBytes = 0

        for zone in ControlZone.allCases {
            var button = requested.button(in: zone)
            button.title = String(button.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
            if button.title.isEmpty { button.title = MacL10n.text("Sans titre") }

            switch button.icon {
            case .system(let name):
                let cleaned = String(name.prefix(80))
                button.icon = .system(cleaned.isEmpty ? "circle" : cleaned)
            case .customImage(let data):
                guard data.count <= 40 * 1_024,
                      customImageBytes + data.count <= 280 * 1_024 else {
                    button.icon = .system("photo")
                    break
                }
                customImageBytes += data.count
            }

            if case .macShortcut(let shortcut) = button.action, !shortcut.isValid {
                button.action = .none
            }
            buttons.append(button)
        }

        for requestedButton in requested.globalButtons.prefix(32) {
            var button = requestedButton
            button.title = String(button.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
            if button.title.isEmpty { button.title = MacL10n.text("Sans titre") }

            switch button.icon {
            case .system(let name):
                let cleaned = String(name.prefix(80))
                button.icon = .system(cleaned.isEmpty ? "circle" : cleaned)
            case .customImage(let data):
                guard data.count <= 40 * 1_024,
                      customImageBytes + data.count <= 280 * 1_024 else {
                    button.icon = .system("photo")
                    break
                }
                customImageBytes += data.count
            }

            if case .macShortcut(let shortcut) = button.action, !shortcut.isValid {
                button.action = .none
            }
            globalButtons.append(button)
        }

        return ControlConfiguration(
            buttons: buttons,
            globalButtons: globalButtons,
            revision: requested.revision,
            updatedAt: requested.updatedAt
        )
    }

    // MARK: - Écran distant

    private func handleScreenRequest(
        _ request: ScreenStreamRequestPayload,
        for session: Session,
        replyTo: UUID
    ) {
        session.wantsScreen = request.enabled

        guard request.enabled else {
            send(
                type: .screenStreamStatus,
                payload: ScreenStreamStatusPayload(
                    isStreaming: false,
                    permissionGranted: CGPreflightScreenCaptureAccess()
                ),
                to: session,
                replyTo: replyTo
            )
            stopScreenCaptureWhenUnused()
            return
        }

        if screenCaptureRunning {
            send(
                type: .screenStreamStatus,
                payload: ScreenStreamStatusPayload(isStreaming: true, permissionGranted: true),
                to: session,
                replyTo: replyTo
            )
            return
        }
        guard !screenCaptureStarting else { return }
        screenCaptureStarting = true

        Task { [weak self] in
            guard let self else { return }
            do {
                try await screenCapture.start(
                    request: request,
                    frameHandler: { [weak self] frame in
                        Task { @MainActor in self?.broadcastScreenFrame(frame) }
                    },
                    stoppedHandler: { [weak self] error in
                        Task { @MainActor in self?.handleScreenCaptureStopped(error) }
                    }
                )
                screenCaptureStarting = false
                screenCaptureRunning = true

                if sessions.values.contains(where: \.wantsScreen) {
                    for viewer in sessions.values where viewer.wantsScreen {
                        send(
                            type: .screenStreamStatus,
                            payload: ScreenStreamStatusPayload(isStreaming: true, permissionGranted: true),
                            to: viewer,
                            replyTo: viewer === session ? replyTo : nil
                        )
                    }
                } else {
                    stopScreenCaptureWhenUnused()
                }
            } catch {
                screenCaptureStarting = false
                screenCaptureRunning = false
                session.wantsScreen = false
                send(
                    type: .screenStreamStatus,
                    payload: ScreenStreamStatusPayload(
                        isStreaming: false,
                        permissionGranted: CGPreflightScreenCaptureAccess(),
                        detail: error.localizedDescription
                    ),
                    to: session,
                    replyTo: replyTo
                )
            }
        }
    }

    private func broadcastScreenFrame(_ frame: ScreenFramePayload) {
        guard screenCaptureRunning else { return }
        for session in sessions.values where session.wantsScreen && session.isAuthenticated {
            sendScreenFrame(frame, to: session)
        }
    }

    /// ScreenCaptureKit peut interrompre un flux sans fermer la connexion
    /// réseau (verrouillage de session, changement d'écran, service relancé).
    /// On publie alors l'état réel afin que l'iPhone puisse redemander le flux
    /// au lieu de rester indéfiniment sur la dernière image reçue.
    private func handleScreenCaptureStopped(_ error: Error) {
        screenCaptureRunning = false
        screenCaptureStarting = false
        Task { await screenCapture.stop() }

        for viewer in sessions.values where viewer.wantsScreen && viewer.isAuthenticated {
            send(
                type: .screenStreamStatus,
                payload: ScreenStreamStatusPayload(
                    isStreaming: false,
                    permissionGranted: CGPreflightScreenCaptureAccess(),
                    detail: error.localizedDescription
                ),
                to: viewer,
                replyTo: nil
            )
        }
    }

    /// Une seule image peut attendre dans la pile TCP par iPhone. Si le réseau
    /// ralentit, on jette les images intermédiaires au lieu d'accumuler du
    /// retard : l'écran reste ainsi proche du temps réel.
    private func sendScreenFrame(_ payload: ScreenFramePayload, to session: Session) {
        guard !session.screenFrameInFlight else { return }
        session.sequence += 1
        guard let envelope = try? RemoteEnvelope.make(
            type: .screenFrame,
            sessionID: session.sessionID,
            sequence: session.sequence,
            payload: payload
        ), let data = try? RemoteCoding.encoder.encode(envelope),
           let framed = try? MessageFramer.frame(data) else { return }

        session.screenFrameInFlight = true
        session.connection.send(content: framed, completion: .contentProcessed { [weak session] _ in
            Task { @MainActor in session?.screenFrameInFlight = false }
        })
    }

    private func stopScreenCaptureWhenUnused() {
        guard !sessions.values.contains(where: \.wantsScreen),
              screenCaptureRunning || screenCaptureStarting else { return }
        screenCaptureRunning = false
        screenCaptureStarting = false
        Task { await screenCapture.stop() }
    }

    // MARK: - Envoi

    private func sendChallenge(_ session: Session) {
        session.nonce = SecureRandom.bytes(32)
        send(
            type: .pairingChallenge,
            payload: PairingChallengePayload(nonce: session.nonce, requiresPairingSecret: authority.isPairing),
            to: session,
            replyTo: nil
        )
    }

    private func send<T: Encodable>(type: RemoteMessageType, payload: T, to session: Session, replyTo: UUID?) {
        session.sequence += 1
        guard let envelope = try? RemoteEnvelope.make(
            type: type,
            sessionID: session.sessionID,
            sequence: session.sequence,
            replyTo: replyTo,
            payload: payload
        ),
        let data = try? RemoteCoding.encoder.encode(envelope),
        let framed = try? MessageFramer.frame(data) else {
            return
        }
        session.connection.send(content: framed, completion: .idempotent)
    }

    private func send(error: RemoteErrorPayload, to session: Session, replyTo: UUID?) {
        send(type: .error, payload: error, to: session, replyTo: replyTo)
    }

    /// Network.framework ne garantit pas qu'un envoi `.idempotent` soit vidé
    /// avant un `cancel()` immédiat. Les erreurs d'appairage doivent parvenir à
    /// l'iPhone avant de fermer la session, sinon le scanner reste sur son
    /// loader sans savoir que le QR a expiré.
    private func sendAndClose(error: RemoteErrorPayload, to session: Session, replyTo: UUID?) {
        session.sequence += 1
        guard let envelope = try? RemoteEnvelope.make(
            type: .error,
            sessionID: session.sessionID,
            sequence: session.sequence,
            replyTo: replyTo,
            payload: error
        ),
        let data = try? RemoteCoding.encoder.encode(envelope),
        let framed = try? MessageFramer.frame(data) else {
            session.connection.cancel()
            return
        }
        let connection = session.connection
        connection.send(content: framed, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

extension Bundle {
    var appVersion: String {
        let short = infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}
