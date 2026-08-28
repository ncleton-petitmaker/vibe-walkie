import Foundation
import RemoteCore

/// Une transcription conservée localement.
struct TranscriptEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let text: String
    let createdAt: Date
    var delivery: DeliveryState
    var applicationName: String?
}

/// Historique local des dictées.
///
/// Il existe surtout pour ne pas perdre une phrase quand l'insertion échoue.
/// Volontairement borné et effaçable : conserver indéfiniment ce que
/// l'utilisateur a dicté dans son travail serait un mauvais défaut.
@MainActor
final class TranscriptHistoryStore: ObservableObject {

    @Published private(set) var entries: [TranscriptEntry] = []
    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.enabledKey)
            if !isEnabled { clear() }
        }
    }

    private static let enabledKey = "com.nicolascleton.viberemote.historyEnabled"
    private static let maximumEntries = 50
    private static let maximumAge: TimeInterval = 7 * 24 * 3600

    private let fileURL: URL
    private let defaults: UserDefaults

    init(fileURL suppliedFileURL: URL? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Self.enabledKey) == nil {
            defaults.set(true, forKey: Self.enabledKey)
        }
        self.isEnabled = defaults.bool(forKey: Self.enabledKey)

        let directory = suppliedFileURL?.deletingLastPathComponent()
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = suppliedFileURL ?? directory.appendingPathComponent("transcripts.json")
        load()
    }

    var lastEntry: TranscriptEntry? { entries.first }

    @discardableResult
    func record(_ text: String, delivery: DeliveryState, applicationName: String?) -> TranscriptEntry {
        let entry = TranscriptEntry(
            id: UUID(),
            text: text,
            createdAt: Date(),
            delivery: delivery,
            applicationName: applicationName
        )
        guard isEnabled else { return entry }
        entries.insert(entry, at: 0)
        prune()
        save()
        return entry
    }

    func update(_ id: UUID, delivery: DeliveryState, applicationName: String? = nil) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].delivery = delivery
        if let applicationName { entries[index].applicationName = applicationName }
        save()
    }

    func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    /// Supprime réellement les objets persistés, pas seulement l'affichage.
    func clear() {
        entries.removeAll()
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-Self.maximumAge)
        entries.removeAll { $0.createdAt < cutoff }
        if entries.count > Self.maximumEntries {
            entries = Array(entries.prefix(Self.maximumEntries))
        }
    }

    private func load() {
        guard isEnabled,
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? RemoteCoding.decoder.decode([TranscriptEntry].self, from: data) else {
            return
        }
        entries = decoded
        prune()
    }

    private func save() {
        guard isEnabled, let data = try? RemoteCoding.encoder.encode(entries) else { return }
        // Protection complète : l'historique doit être illisible quand
        // l'iPhone est verrouillé.
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}
