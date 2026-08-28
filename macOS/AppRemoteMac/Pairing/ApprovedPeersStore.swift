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
        if let index = peers.firstIndex(where: { $0.id == peer.id }) {
            peers[index] = peer
        } else {
            peers.append(peer)
        }
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
            peers = decoded
        }
    }

    private func save() {
        guard let data = try? RemoteCoding.encoder.encode(peers) else { return }
        try? data.write(
            to: fileURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }
}
