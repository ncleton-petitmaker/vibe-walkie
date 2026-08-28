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
    @Published private(set) var hasCompletedFirstCommand: Bool

    private var listener: NWListener?
    private var identity: SecIdentity?
    private var sessions: [ObjectIdentifier: Session] = [:]
    private let screenCapture = ScreenCaptureService()
    private var screenCaptureRunning = false
    private var screenCaptureStarting = false

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
        let sessionID = UUID().uuidString

        init(connection: NWConnection) {
            self.connection = connection
            self.nonce = SecureRandom.bytes(32)
        }

        var isAuthenticated: Bool { router != nil }
    }

    init(peers: ApprovedPeersStore, authority: PairingAuthority) {
        self.peers = peers
        self.authority = authority
        self.hasCompletedFirstCommand = UserDefaults.standard.bool(forKey: "hasCompletedFirstCommand")
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
            guard let port = NWEndpoint.Port(rawValue: VibeRemoteInfo.controlPort) else {
                throw RemoteErrorPayload(code: .internalFailure, detail: "port invalide")
            }
            let listener = try NWListener(using: parameters, on: port)

            let name = "VibeRemote-\(Host.current().localizedName ?? "Mac")"
            listener.service = NWListener.Service(name: name, type: VibeRemoteInfo.bonjourServiceType)
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
        let session = Session(connection: connection)
        sessions[ObjectIdentifier(connection)] = session

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    self.sendChallenge(session)
                case .failed, .cancelled:
                    session.approvalExpiryTask?.cancel()
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
            send(error: RemoteErrorPayload(code: .protocolMismatch), to: session, replyTo: envelope.messageID)
            session.connection.cancel()
            return
        }
        guard session.isAuthenticated else {
            // Avant authentification, un seul type de message est recevable.
            guard envelope.type == .pairingResponse,
                  let payload = try? envelope.decodePayload(PairingResponsePayload.self) else {
                send(error: RemoteErrorPayload(code: .notPaired), to: session, replyTo: envelope.messageID)
                session.connection.cancel()
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
                        try? await Task.sleep(for: .seconds(VibeRemoteInfo.pairingApprovalWindow))
                        guard !Task.isCancelled, let self, let session else { return }
                        await MainActor.run { self.expirePairing(pending.id, in: session) }
                    }
                }
            } catch let error as RemoteErrorPayload {
                send(error: error, to: session, replyTo: envelope.messageID)
                session.connection.cancel()
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
        send(error: RemoteErrorPayload(code: .pairingDenied), to: session, replyTo: session.pendingApprovalReplyTo)
        session.connection.cancel()
    }

    private func expirePairing(_ requestID: UUID, in session: Session) {
        guard session.pendingApprovalID == requestID else { return }
        _ = authority.cancelPendingApproval(requestID)
        send(
            error: RemoteErrorPayload(code: .pairingApprovalExpired),
            to: session,
            replyTo: session.pendingApprovalReplyTo
        )
        session.connection.cancel()
    }

    private func establishAuthenticatedSession(_ session: Session, peer: ApprovedPeer, replyTo: UUID?) {
        session.router = SessionRouter(peerID: peer.id, sessionID: session.sessionID)
        connectedPeerName = peer.name
        send(
            type: .connectionStatus,
            payload: ConnectionStatusPayload(
                accessibilityGranted: AccessibilityClient.isTrusted,
                macName: Host.current().localizedName ?? "Mac",
                companionVersion: Bundle.main.appVersion
            ),
            to: session,
            replyTo: replyTo
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
}

extension Bundle {
    var appVersion: String {
        let short = infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}
