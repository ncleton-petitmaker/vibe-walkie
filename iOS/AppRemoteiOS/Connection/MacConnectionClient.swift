import Foundation
import Network
import CryptoKit
import RemoteCore

/// Client réseau de l'iPhone : découverte, TLS épinglé, authentification.
@MainActor
final class MacConnectionClient: ObservableObject {

    @Published private(set) var state: ConnectionState = .idle
    @Published private(set) var snapshot: WindowsSnapshotPayload?
    @Published private(set) var accessibilityGranted = true
    @Published private(set) var latestScreenFrame: ScreenFramePayload?
    @Published private(set) var lastScreenFrameAt: Date?
    @Published private(set) var screenStreamStatus = ScreenStreamStatusPayload(
        isStreaming: false,
        permissionGranted: true
    )

    private var connection: NWConnection?
    private var browser: NWBrowser?
    private var framer = MessageFramer()
    private var sequence: UInt64 = 0
    private var sessionID = UUID().uuidString
    private var retry = RetryPolicy()
    private var reconnectTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?

    private var pairedMac: PairedMac?
    /// Renseigné le temps d'un appairage, puis effacé.
    private var pendingPairing: PairingQRPayload?

    private var pendingReplies: [UUID: CheckedContinuation<RemoteEnvelope, Error>] = [:]

    init() {
        pairedMac = PairedMac.load()
    }

#if DEBUG
    /// Données déterministes réservées aux captures marketing du simulateur.
    /// Elles ne sont jamais compilées dans une archive Release.
    func configureMarketingPreview() {
        state = .ready(macName: "MacBook Pro")
        accessibilityGranted = true
        snapshot = WindowsSnapshotPayload(
            applications: [
                RemoteApplication(
                    id: "notes",
                    name: "Notes",
                    bundleIdentifier: "com.apple.Notes",
                    isActive: true,
                    iconPNG: nil,
                    windows: [RemoteWindow(id: "notes-main", title: "Brief lancement", isMain: true, isMinimized: false)]
                ),
                RemoteApplication(
                    id: "safari",
                    name: "Safari",
                    bundleIdentifier: "com.apple.Safari",
                    isActive: false,
                    iconPNG: nil,
                    windows: [RemoteWindow(id: "safari-main", title: "Recherche", isMain: true, isMinimized: false)]
                ),
                RemoteApplication(
                    id: "mail",
                    name: "Mail",
                    bundleIdentifier: "com.apple.mail",
                    isActive: false,
                    iconPNG: nil,
                    windows: [RemoteWindow(id: "mail-main", title: "Boîte de réception", isMain: true, isMinimized: false)]
                ),
                RemoteApplication(
                    id: "codex",
                    name: "Codex",
                    bundleIdentifier: "com.openai.codex",
                    isActive: false,
                    iconPNG: nil,
                    windows: [RemoteWindow(id: "codex-main", title: "Vibe Remote", isMain: true, isMinimized: false)]
                ),
                RemoteApplication(
                    id: "xcode",
                    name: "Xcode",
                    bundleIdentifier: "com.apple.dt.Xcode",
                    isActive: false,
                    iconPNG: nil,
                    windows: [RemoteWindow(id: "xcode-main", title: "Vibe Remote", isMain: true, isMinimized: false)]
                ),
                RemoteApplication(
                    id: "terminal",
                    name: "Terminal",
                    bundleIdentifier: "com.apple.Terminal",
                    isActive: false,
                    iconPNG: nil,
                    windows: [RemoteWindow(id: "terminal-main", title: "zsh", isMain: true, isMinimized: false)]
                )
            ],
            activeApplicationID: "notes"
        )
    }
#endif

    var isPaired: Bool { pairedMac != nil }
    // MARK: - Appairage

    /// Prend en compte un QR scanné et lance la connexion.
    func pair(with payload: PairingQRPayload) throws {
        guard !payload.isExpired else {
            throw RemoteErrorPayload(code: .notPaired, detail: "QR expiré")
        }
        guard payload.version == ProtocolVersion.current else {
            throw RemoteErrorPayload(code: .protocolMismatch)
        }
        pendingPairing = payload
        state = .pairing(macName: payload.macName, confirmationCode: payload.confirmationCode)
        connect(
            to: payload.serviceName,
            fingerprint: payload.certificateFingerprint,
            macName: payload.macName
        )
    }

    func forgetMac() {
        disconnect()
        PairedMac.forget()
        pairedMac = nil
        state = .idle
    }

    // MARK: - Connexion

    func connectIfPossible() {
        guard let mac = pairedMac, connection == nil else { return }
        state = .searching
        connect(
            to: mac.serviceName,
            fingerprint: mac.certificateFingerprint,
            macName: mac.name
        )
    }

    /// Relance immédiatement une connexion bloquée en résolution ou en TLS.
    /// Le bouton de reconnexion doit remplacer l'objet `NWConnection` : appeler
    /// simplement `connectIfPossible` ne faisait rien tant qu'une connexion en
    /// état `.waiting` restait conservée.
    func reconnectNow() {
        guard let mac = pairedMac else { return }
        reconnectTask?.cancel()
        reconnectTask = nil
        connection?.cancel()
        connection = nil
        state = .searching
        connect(
            to: mac.serviceName,
            fingerprint: mac.certificateFingerprint,
            macName: mac.name
        )
    }

    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        watchdogTask?.cancel()
        watchdogTask = nil
        connection?.cancel()
        connection = nil
        browser?.cancel()
        browser = nil
        framer.reset()
        latestScreenFrame = nil
        lastScreenFrameAt = nil
        screenStreamStatus = ScreenStreamStatusPayload(isStreaming: false, permissionGranted: true)
        failPendingReplies(RemoteErrorPayload(code: .internalFailure, detail: "déconnecté"))
    }

    private func connect(
        to serviceName: String,
        fingerprint: String,
        macName: String
    ) {
        connection?.cancel()
        framer.reset()
        sequence = 0
        sessionID = UUID().uuidString
        state = .connecting(macName: macName)

        let parameters = makeParameters(expecting: fingerprint)
        let endpoint = NWEndpoint.service(
            name: serviceName,
            type: VibeRemoteInfo.bonjourServiceType,
            domain: "local.",
            interface: nil
        )
        let connection = NWConnection(to: endpoint, using: parameters)

        connection.stateUpdateHandler = { [weak self] newState in
            Task { @MainActor in
                guard let self else { return }
                // Une ancienne connexion annulée peut publier son état après
                // qu'une nouvelle a déjà été créée. Elle ne doit jamais
                // débrancher ou replanifier la connexion courante.
                guard self.connection === connection else { return }
                switch newState {
                case .ready:
                    self.retry.reset()
                    self.receive(
                        on: connection,
                        macName: macName,
                        serviceName: serviceName,
                        fingerprint: fingerprint
                    )
                case .waiting:
                    // `cancel()` depuis `.waiting` ne produit pas toujours un
                    // second callback `.cancelled` sur iOS. Attendre ce
                    // callback laissait la reconnexion bloquée après le
                    // redémarrage du Mac ou une transition entre réseaux Wi‑Fi.
                    connection.cancel()
                    self.handleDisconnection(
                        macName: macName,
                        serviceName: serviceName,
                        fingerprint: fingerprint
                    )
                case .failed, .cancelled:
                    self.handleDisconnection(
                        macName: macName,
                        serviceName: serviceName,
                        fingerprint: fingerprint
                    )
                default:
                    break
                }
            }
        }
        connection.start(queue: .main)
        self.connection = connection
    }

    /// Paramètres TLS avec épinglage strict.
    ///
    /// Le certificat du Mac est auto-signé : la validation par défaut le
    /// rejetterait. On ne désactive pas la vérification pour autant — on la
    /// remplace par une comparaison d'empreinte exacte, celle transmise par le
    /// QR. Accepter n'importe quel certificat ouvrirait la porte à un
    /// intercepteur sur le même Wi-Fi.
    private func makeParameters(expecting fingerprint: String) -> NWParameters {
        let options = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(options.securityProtocolOptions, .TLSv13)

        sec_protocol_options_set_verify_block(
            options.securityProtocolOptions,
            { _, trust, complete in
                let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
                guard let chain = SecTrustCopyCertificateChain(secTrust) as? [SecCertificate],
                      let leaf = chain.first else {
                    complete(false)
                    return
                }
                let data = SecCertificateCopyData(leaf) as Data
                let digest = Data(SHA256.hash(data: data)).base64EncodedString()
                complete(digest == fingerprint)
            },
            .main
        )

        let parameters = NWParameters(tls: options)
        parameters.includePeerToPeer = true
        return parameters
    }

    private func handleDisconnection(
        macName: String,
        serviceName: String,
        fingerprint: String
    ) {
        watchdogTask?.cancel()
        watchdogTask = nil
        connection = nil
        latestScreenFrame = nil
        lastScreenFrameAt = nil
        screenStreamStatus = ScreenStreamStatusPayload(isStreaming: false, permissionGranted: true)
        failPendingReplies(RemoteErrorPayload(code: .internalFailure, detail: "connexion perdue"))
        guard isPaired || pendingPairing != nil else {
            state = .idle
            return
        }
        state = .searching

        reconnectTask?.cancel()
        let delay = retry.nextDelay()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.connect(
                    to: serviceName,
                    fingerprint: fingerprint,
                    macName: macName
                )
            }
        }
    }

    // MARK: - Réception

    private func receive(
        on connection: NWConnection,
        macName: String,
        serviceName: String,
        fingerprint: String
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else { return }
                // Une fin de lecture appartenant à une ancienne connexion ne
                // doit jamais annuler celle qui vient de la remplacer.
                guard self.connection === connection else { return }
                if let data, !data.isEmpty {
                    self.ingest(data)
                }
                if isComplete || error != nil {
                    // On programme nous-mêmes la reconnexion. Attendre le
                    // callback `.cancelled` de Network.framework laissait
                    // parfois l’iPhone bloqué sur l’ancienne session après une
                    // mise à jour ou un redémarrage du compagnon Mac.
                    connection.cancel()
                    self.handleDisconnection(
                        macName: macName,
                        serviceName: serviceName,
                        fingerprint: fingerprint
                    )
                    return
                }
                self.receive(
                    on: connection,
                    macName: macName,
                    serviceName: serviceName,
                    fingerprint: fingerprint
                )
            }
        }
    }

    private func ingest(_ data: Data) {
        guard let messages = try? framer.append(data) else {
            connection?.cancel()
            return
        }
        for message in messages {
            guard let envelope = try? RemoteCoding.decoder.decode(RemoteEnvelope.self, from: message) else { continue }
            handle(envelope)
        }
    }

    private func handle(_ envelope: RemoteEnvelope) {
        guard envelope.version == ProtocolVersion.current else {
            pendingPairing = nil
            connection?.cancel()
            connection = nil
            state = .failed(.protocolMismatch)
            return
        }
        if let replyTo = envelope.replyTo, let continuation = pendingReplies.removeValue(forKey: replyTo) {
            if envelope.type == .error, let payload = try? envelope.decodePayload(RemoteErrorPayload.self) {
                continuation.resume(throwing: payload)
            } else {
                // Les réponses typées doivent aussi alimenter l'état publié.
                // Avant, `windowsSnapshot` reprenait la continuation puis
                // quittait la méthode : la grille d'apps restait donc vide.
                if envelope.type == .windowsSnapshot {
                    snapshot = try? envelope.decodePayload(WindowsSnapshotPayload.self)
                }
                continuation.resume(returning: envelope)
            }
            return
        }

        switch envelope.type {
        case .pairingChallenge:
            guard let payload = try? envelope.decodePayload(PairingChallengePayload.self) else { return }
            respondToChallenge(payload, replyTo: envelope.messageID)

        case .pairingPending:
            guard let payload = try? envelope.decodePayload(PairingPendingPayload.self),
                  let pending = pendingPairing else { return }
            state = .awaitingApproval(
                macName: pending.macName,
                confirmationCode: payload.confirmationCode
            )

        case .connectionStatus:
            guard let payload = try? envelope.decodePayload(ConnectionStatusPayload.self) else { return }
            accessibilityGranted = payload.accessibilityGranted
            state = .ready(macName: payload.macName)
            startWatchdog()

            if let pending = pendingPairing {
                let mac = PairedMac(
                    name: payload.macName,
                    serviceName: pending.serviceName,
                    certificateFingerprint: pending.certificateFingerprint
                )
                mac.save()
                pairedMac = mac
                pendingPairing = nil
            }

        case .windowsSnapshot:
            snapshot = try? envelope.decodePayload(WindowsSnapshotPayload.self)

        case .screenFrame:
            if let frame = try? envelope.decodePayload(ScreenFramePayload.self) {
                latestScreenFrame = frame
                lastScreenFrameAt = Date()
            }

        case .screenStreamStatus:
            if let payload = try? envelope.decodePayload(ScreenStreamStatusPayload.self) {
                screenStreamStatus = payload
                if !payload.isStreaming { latestScreenFrame = nil }
            }

        case .error:
            if let payload = try? envelope.decodePayload(RemoteErrorPayload.self) {
                if pendingPairing != nil,
                   [.pairingDenied, .pairingApprovalExpired, .notPaired, .protocolMismatch].contains(payload.code) {
                    pendingPairing = nil
                    connection?.cancel()
                    connection = nil
                }
                state = .failed(payload.code)
            }

        default:
            break
        }
    }

    func startScreenStream(maxWidth: Int = 1_280, framesPerSecond: Int = 10, jpegQuality: Double = 0.45) {
        latestScreenFrame = nil
        lastScreenFrameAt = nil
        screenStreamStatus = ScreenStreamStatusPayload(isStreaming: false, permissionGranted: true)
        sendFireAndForget(
            type: .screenStreamRequest,
            payload: ScreenStreamRequestPayload(
                enabled: true,
                maxWidth: maxWidth,
                framesPerSecond: framesPerSecond,
                jpegQuality: jpegQuality
            )
        )
    }

    func stopScreenStream() {
        sendFireAndForget(type: .screenStreamRequest, payload: ScreenStreamRequestPayload(enabled: false))
        latestScreenFrame = nil
        lastScreenFrameAt = nil
        screenStreamStatus = ScreenStreamStatusPayload(isStreaming: false, permissionGranted: true)
    }

    /// Battement de cœur indépendant des vues présentées. Le plein écran peut
    /// suspendre les tâches de la vue principale ; la connexion, elle, doit
    /// continuer à être surveillée et se reconstruire sans intervention.
    private func startWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, let self, self.state.isReady else { return }
                do {
                    _ = try await self.send(
                        type: .hello,
                        payload: HelloPayload(
                            deviceName: DeviceKeyStore.deviceName,
                            deviceIdentifier: DeviceKeyStore.deviceIdentifier,
                            appVersion: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
                        )
                    )
                } catch {
                    // `send` remplace déjà la connexion sur timeout. Ce garde
                    // couvre les autres erreurs de transport immédiates.
                    if self.state.isReady { self.reconnectNow() }
                    return
                }
            }
        }
    }

    private func respondToChallenge(_ challenge: PairingChallengePayload, replyTo: UUID) {
        do {
            let key = try DeviceKeyStore.loadOrCreatePrivateKey()
            let secret = pendingPairing.flatMap { Data(base64Encoded: $0.pairingSecret) }
            let signature = try ChallengeSigner.sign(
                nonce: challenge.nonce,
                deviceIdentifier: DeviceKeyStore.deviceIdentifier,
                pairingSecret: secret,
                privateKey: key
            )
            let payload = PairingResponsePayload(
                deviceIdentifier: DeviceKeyStore.deviceIdentifier,
                deviceName: DeviceKeyStore.deviceName,
                publicKey: key.publicKey.rawRepresentation,
                signature: signature,
                pairingSecret: secret
            )
            sendFireAndForget(type: .pairingResponse, payload: payload, replyTo: replyTo)
        } catch {
            state = .failed(.notPaired)
        }
    }

    // MARK: - Envoi

    @discardableResult
    func send<T: Encodable>(type: RemoteMessageType, payload: T) async throws -> RemoteEnvelope {
        guard let connection, state.isReady || type == .pairingResponse else {
            throw RemoteErrorPayload(code: .internalFailure, detail: "non connecté")
        }
        sequence += 1
        let envelope = try RemoteEnvelope.make(
            type: type,
            sessionID: sessionID,
            sequence: sequence,
            payload: payload
        )
        let data = try RemoteCoding.encoder.encode(envelope)
        let framed = try MessageFramer.frame(data)

        return try await withCheckedThrowingContinuation { continuation in
            pendingReplies[envelope.messageID] = continuation
            connection.send(content: framed, completion: .idempotent)

            Task { [weak self] in
                try? await Task.sleep(for: .seconds(ProtocolLimits.acknowledgementTimeout))
                await MainActor.run {
                    guard let pending = self?.pendingReplies.removeValue(forKey: envelope.messageID) else { return }
                    // Sans réponse, on ne conclut pas à un échec : la commande
                    // a pu aboutir. L'appelant décidera quoi montrer.
                    pending.resume(throwing: RemoteErrorPayload(code: .internalFailure, detail: "timeout"))
                    // La requête périodique des apps sert aussi de battement de
                    // cœur. Si le Mac a redémarré sans que Network.framework
                    // nous signale la socket morte, on la remplace ici.
                    self?.reconnectNow()
                }
            }
        }
    }

    /// Envoi sans attente de réponse, pour les gestes continus.
    func sendFireAndForget<T: Encodable>(type: RemoteMessageType, payload: T, replyTo: UUID? = nil) {
        guard let connection else { return }
        sequence += 1
        guard let envelope = try? RemoteEnvelope.make(
            type: type,
            sessionID: sessionID,
            sequence: sequence,
            replyTo: replyTo,
            payload: payload
        ),
        let data = try? RemoteCoding.encoder.encode(envelope),
        let framed = try? MessageFramer.frame(data) else { return }
        connection.send(content: framed, completion: .idempotent)
    }

    private func failPendingReplies(_ error: Error) {
        let pending = pendingReplies
        pendingReplies.removeAll()
        pending.values.forEach { $0.resume(throwing: error) }
    }

}
