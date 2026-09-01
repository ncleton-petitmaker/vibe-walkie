import Foundation
import RemoteCore

/// Liste des iPhone autorisés à piloter ce Mac.
///
/// Stockée dans le conteneur de l'application, pas dans un fichier partagé :
/// un pair approuvé équivaut à un droit de frappe clavier, il n'a rien à faire
/// dans un emplacement lisible par n'importe quel processus utilisateur.
@MainActor
final class ApprovedPeersStore: ObservableObject {

    @Published private(set) var peers: [ApprovedPeer] = []

    private let fileURL: URL

    init(fileURL suppliedFileURL: URL? = nil) {
        let support = suppliedFileURL?.deletingLastPathComponent()
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("VibeRemote", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        self.fileURL = suppliedFileURL ?? support.appendingPathComponent("peers-v2.json")
        load()
    }

    func peer(withID id: String) -> ApprovedPeer? {
        peers.first { $0.id == id && !$0.isRevoked }
    }

    func approve(_ peer: ApprovedPeer) {
        // L'identifiant logique de l'iPhone a historiquement été stocké dans
        // UserDefaults alors que sa clé survivait dans le Trousseau. Après une
        // réinstallation, un même téléphone pouvait donc revenir avec un nouvel
        // UUID mais exactement la même identité cryptographique. La clé publique
        // est l'identité fiable : une nouvelle approbation remplace toute entrée
        // qui utilise déjà cette clé, au lieu d'afficher deux iPhone fantômes.
        peers.removeAll { $0.id == peer.id || $0.publicKey == peer.publicKey }
        peers.append(peer)
        save()
    }

    func markSeen(_ id: String) {
        guard let index = peers.firstIndex(where: { $0.id == id }) else { return }
        peers[index].lastSeenAt = Date()
        save()
    }

    /// Révoque un appareil. La session en cours doit être fermée par l'appelant :
    /// retirer l'autorisation sans couper la connexion laisserait un iPhone
    /// révoqué continuer à envoyer des commandes jusqu'à sa déconnexion.
    func revoke(_ id: String) {
        guard let index = peers.firstIndex(where: { $0.id == id }) else { return }
        peers[index].isRevoked = true
        save()
    }

    func rename(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = peers.firstIndex(where: { $0.id == id }) else { return }
        peers[index].name = String(trimmed.prefix(80))
        save()
    }

    func revokeAll() {
        for index in peers.indices { peers[index].isRevoked = true }
        save()
    }

    func forget(_ id: String) {
        peers.removeAll { $0.id == id }
        save()
    }

    private func load() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? RemoteCoding.decoder.decode([ApprovedPeer].self, from: data) {
            let normalized = Self.normalized(decoded)
            peers = normalized
            if normalized != decoded { save() }
        }
    }

    /// Ne conserve qu'une ligne par clé publique. Une autorisation active est
    /// prioritaire sur une ancienne révocation, puis l'appareil vu/appairé le
    /// plus récemment gagne. Cette migration répare aussi les fichiers déjà
    /// affectés sans demander un nouvel appairage.
    private static func normalized(_ peers: [ApprovedPeer]) -> [ApprovedPeer] {
        var selectedByKey: [Data: ApprovedPeer] = [:]

        for peer in peers {
            guard let current = selectedByKey[peer.publicKey] else {
                selectedByKey[peer.publicKey] = peer
                continue
            }

            let shouldReplace: Bool
            if current.isRevoked != peer.isRevoked {
                shouldReplace = current.isRevoked && !peer.isRevoked
            } else {
                let currentActivity = current.lastSeenAt ?? current.pairedAt
                let peerActivity = peer.lastSeenAt ?? peer.pairedAt
                shouldReplace = peerActivity > currentActivity
            }

            if shouldReplace { selectedByKey[peer.publicKey] = peer }
        }

        return selectedByKey.values.sorted { $0.pairedAt < $1.pairedAt }
    }

    private func save() {
        guard let data = try? RemoteCoding.encoder.encode(peers) else { return }
        try? data.write(
            to: fileURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }
}
