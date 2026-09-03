import Foundation

/// Réponse sérialisée qui peut être rejouée à un pair après une reconnexion.
///
/// Le cache conserve les octets JSON exacts plutôt que de réencoder le
/// payload : une réponse à un `messageID` donné reste ainsi strictement la
/// même, quelle que soit la nouvelle session TLS qui la redemande.
public struct CachedPeerResponse: Equatable, Sendable {
    public let type: RemoteMessageType
    public let payload: Data

    public init(type: RemoteMessageType, payload: Data) {
        self.type = type
        self.payload = payload
    }
}

/// Cache LRU borné des réponses déjà exécutées, cloisonné par pair approuvé.
///
/// `SequenceValidator` protège une socket donnée. Celui-ci complète cette
/// protection lorsque le client ouvre une nouvelle socket après avoir perdu un
/// accusé. Les hôtes décident eux-mêmes quelles commandes sont sûres à mettre
/// ici : les commandes qui reconstruisent un état de session ne doivent pas
/// être rejouées entre deux sessions.
public struct PeerResponseCache: Sendable {
    private struct PeerEntries: Sendable {
        var responses: [UUID: CachedPeerResponse] = [:]
        var order: [UUID] = []
    }

    private var entriesByPeer: [String: PeerEntries] = [:]
    private var peerOrder: [String] = []
    private let maximumPeers: Int
    private let entriesPerPeer: Int

    public init(maximumPeers: Int = 32, entriesPerPeer: Int = 2_048) {
        self.maximumPeers = max(1, maximumPeers)
        self.entriesPerPeer = max(1, entriesPerPeer)
    }

    public mutating func response(for peerID: String, messageID: UUID) -> CachedPeerResponse? {
        guard let response = entriesByPeer[peerID]?.responses[messageID] else { return nil }
        touch(peerID)
        return response
    }

    public mutating func store(_ response: CachedPeerResponse, for peerID: String, messageID: UUID) {
        touch(peerID)
        var peer = entriesByPeer[peerID] ?? PeerEntries()
        peer.responses[messageID] = response
        peer.order.removeAll { $0 == messageID }
        peer.order.append(messageID)

        while peer.order.count > entriesPerPeer {
            let evicted = peer.order.removeFirst()
            peer.responses.removeValue(forKey: evicted)
        }
        entriesByPeer[peerID] = peer
    }

    /// Oublie immédiatement les réponses d'un appareil révoqué. Une nouvelle
    /// approbation de ce même identifiant repart alors sans aucun état de
    /// l'ancienne relation de confiance.
    public mutating func removeAll(for peerID: String) {
        entriesByPeer.removeValue(forKey: peerID)
        peerOrder.removeAll { $0 == peerID }
    }

    public mutating func removeAll() {
        entriesByPeer.removeAll(keepingCapacity: false)
        peerOrder.removeAll(keepingCapacity: false)
    }

    private mutating func touch(_ peerID: String) {
        peerOrder.removeAll { $0 == peerID }
        peerOrder.append(peerID)

        while peerOrder.count > maximumPeers {
            let evicted = peerOrder.removeFirst()
            entriesByPeer.removeValue(forKey: evicted)
        }
    }
}
