import Foundation
import RemoteCore

/// Vérifie les preuves cryptographiques et impose une décision humaine avant
/// d'accorder pour la première fois le contrôle du Mac.
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

    func beginPairing(macName: String, serviceName: String, fingerprint: String) -> PairingQRPayload {
        cancelPendingApproval()
        let secret = SecureRandom.bytes(16)
        let payload = PairingQRPayload(
            macName: macName,
            serviceName: serviceName,
            certificateFingerprint: fingerprint,
            pairingSecret: secret.base64EncodedString(),
            expiresAt: Date().addingTimeInterval(VibeRemoteInfo.pairingWindow)
        )
        activeSession = PairingSession(
            payload: payload,
            secret: secret,
            encodedPayload: (try? payload.encoded()) ?? ""
        )

        expiryTask?.cancel()
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(VibeRemoteInfo.pairingWindow))
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
            guard known.publicKey == response.publicKey else {
                throw RemoteErrorPayload(code: .notPaired, detail: "clé différente")
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
        let pending = PendingApproval(
            id: UUID(),
            peer: peer,
            confirmationCode: session.payload.confirmationCode,
            expiresAt: Date().addingTimeInterval(VibeRemoteInfo.pairingApprovalWindow)
        )
        pendingApproval = pending
        return .requiresApproval(pending)
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
