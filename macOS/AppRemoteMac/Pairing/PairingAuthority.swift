import Foundation
import RemoteCore

/// Vérifie les preuves cryptographiques transportées par le QR avant
/// d'accorder le contrôle du Mac. Scanner le QR affiché physiquement par le
/// compagnon constitue l'autorisation explicite : aucune seconde confirmation
/// n'est demandée dans l'interface Mac.
@MainActor
final class PairingAuthority: ObservableObject {

    struct PairingSession {
        let payload: PairingQRPayload
        let secret: Data
        let encodedPayload: String
    }

    struct PendingApproval: Identifiable, Equatable {
        let id: UUID
        let peer: ApprovedPeer
        let confirmationCode: String
        let expiresAt: Date

        var isExpired: Bool { Date() >= expiresAt }
    }

    enum AuthenticationDecision {
        case approved(ApprovedPeer)
        case requiresApproval(PendingApproval)
    }

    @Published private(set) var activeSession: PairingSession?
    @Published private(set) var pendingApproval: PendingApproval?

    private let peers: ApprovedPeersStore
    private var expiryTask: Task<Void, Never>?

    init(peers: ApprovedPeersStore) {
        self.peers = peers
    }

    func beginPairing(
        macName: String,
        serviceName: String,
        fingerprint: String,
        nomadEndpoint: NomadEndpoint? = nil,
        validity: TimeInterval = VibeWalkieInfo.pairingWindow
    ) -> PairingQRPayload {
        cancelPendingApproval()
        let secret = SecureRandom.bytes(16)
        let payload = PairingQRPayload(
            macName: macName,
            serviceName: serviceName,
            certificateFingerprint: fingerprint,
            pairingSecret: secret.base64EncodedString(),
            expiresAt: Date().addingTimeInterval(validity),
            nomadEndpoint: nomadEndpoint
        )
        activeSession = PairingSession(
            payload: payload,
            secret: secret,
            encodedPayload: (try? payload.encoded()) ?? ""
        )

        expiryTask?.cancel()
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(validity))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.endPairing() }
        }
        return payload
    }

    func endPairing() {
        expiryTask?.cancel()
        expiryTask = nil
        activeSession = nil
    }

    var isPairing: Bool {
        guard let session = activeSession else { return false }
        return !session.payload.isExpired
    }

    func authenticate(response: PairingResponsePayload, nonce: Data) throws -> AuthenticationDecision {
        if let known = peers.peer(withID: response.deviceIdentifier) {
            // Si l'iPhone a régénéré sa clé, un nouveau QR valide constitue la
            // preuve de présence nécessaire pour remplacer l'ancienne identité.
            if known.publicKey != response.publicKey {
                return try prepareKeyReplacement(response: response, nonce: nonce)
            }

            let verificationSecret: Data?
            if let provided = response.pairingSecret {
                guard let session = activeSession,
                      !session.payload.isExpired,
                      provided == session.secret else {
                    throw RemoteErrorPayload(code: .notPaired, detail: "secret de réappairage invalide")
                }
                verificationSecret = session.secret
            } else {
                verificationSecret = nil
            }
            guard ChallengeSigner.verify(
                signature: response.signature,
                nonce: nonce,
                deviceIdentifier: response.deviceIdentifier,
                pairingSecret: verificationSecret,
                publicKeyRepresentation: known.publicKey
            ) else {
                throw RemoteErrorPayload(code: .notPaired, detail: "signature invalide")
            }
            peers.markSeen(known.id)
            if verificationSecret != nil { endPairing() }
            return .approved(known)
        }

        guard pendingApproval == nil else {
            throw RemoteErrorPayload(code: .rateLimited, detail: "une approbation est déjà en attente")
        }
        guard let session = activeSession, !session.payload.isExpired else {
            throw RemoteErrorPayload(code: .notPaired)
        }
        guard let provided = response.pairingSecret, provided == session.secret else {
            throw RemoteErrorPayload(code: .notPaired, detail: "secret d'appairage invalide")
        }
        guard ChallengeSigner.verify(
            signature: response.signature,
            nonce: nonce,
            deviceIdentifier: response.deviceIdentifier,
            pairingSecret: session.secret,
            publicKeyRepresentation: response.publicKey
        ) else {
            throw RemoteErrorPayload(code: .notPaired, detail: "signature invalide")
        }

        let peer = ApprovedPeer(
            id: response.deviceIdentifier,
            name: response.deviceName,
            publicKey: response.publicKey,
            pairedAt: Date()
        )
        peers.approve(peer)
        endPairing()
        return .approved(peer)
    }

    private func prepareKeyReplacement(
        response: PairingResponsePayload,
        nonce: Data
    ) throws -> AuthenticationDecision {
        guard let session = activeSession, !session.payload.isExpired,
              let provided = response.pairingSecret,
              provided == session.secret else {
            throw RemoteErrorPayload(code: .notPaired, detail: "nouvelle clé sans QR valide")
        }
        guard ChallengeSigner.verify(
            signature: response.signature,
            nonce: nonce,
            deviceIdentifier: response.deviceIdentifier,
            pairingSecret: session.secret,
            publicKeyRepresentation: response.publicKey
        ) else {
            throw RemoteErrorPayload(code: .notPaired, detail: "signature de remplacement invalide")
        }

        let replacement = ApprovedPeer(
            id: response.deviceIdentifier,
            name: response.deviceName,
            publicKey: response.publicKey,
            pairedAt: Date()
        )
        peers.approve(replacement)
        endPairing()
        return .approved(replacement)
    }

    func approve(_ requestID: UUID) -> ApprovedPeer? {
        guard let pending = pendingApproval,
              pending.id == requestID,
              !pending.isExpired else { return nil }
        peers.approve(pending.peer)
        pendingApproval = nil
        endPairing()
        return pending.peer
    }

    @discardableResult
    func cancelPendingApproval(_ requestID: UUID? = nil) -> Bool {
        guard let pending = pendingApproval,
              requestID == nil || pending.id == requestID else { return false }
        pendingApproval = nil
        endPairing()
        return true
    }
}
