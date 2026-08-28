import Foundation

/// Rejette les rejeux et les doublons pour une session donnée.
///
/// Deux protections distinctes : la séquence doit progresser, et un
/// `messageID` déjà traité renvoie son accusé précédent au lieu d'exécuter la
/// commande une seconde fois. C'est ce qui empêche qu'une insertion renvoyée
/// après une perte de réseau écrive deux fois la même phrase.
public struct SequenceValidator: Sendable {
    public enum Verdict: Equatable, Sendable {
        case accepted
        case duplicate(UUID)
        case replay
    }

    private var lastSequence: UInt64 = 0
    private var seenMessages: [UUID: Date] = [:]
    private let memoryWindow: TimeInterval

    public init(memoryWindow: TimeInterval = 300) {
        self.memoryWindow = memoryWindow
    }

    public mutating func validate(_ envelope: RemoteEnvelope, now: Date = Date()) -> Verdict {
        prune(now: now)

        if seenMessages[envelope.messageID] != nil {
            return .duplicate(envelope.messageID)
        }
        guard envelope.sequence > lastSequence else {
            return .replay
        }

        lastSequence = envelope.sequence
        seenMessages[envelope.messageID] = now
        return .accepted
    }

    private mutating func prune(now: Date) {
        guard seenMessages.count > 256 else { return }
        seenMessages = seenMessages.filter { now.timeIntervalSince($0.value) < memoryWindow }
    }
}

/// Limiteur de débit à jeton, utilisé pour les gestes continus.
///
/// Le trackpad envoie beaucoup d'événements ; c'est normal. Un pair qui en
/// envoie mille par seconde ne l'est pas, et le Mac doit pouvoir dire non
/// sans se figer.
public struct RateLimiter: Sendable {
    private let capacity: Double
    private let refillPerSecond: Double
    private var tokens: Double
    private var lastRefill: Date

    public init(capacity: Double, refillPerSecond: Double, now: Date = Date()) {
        self.capacity = capacity
        self.refillPerSecond = refillPerSecond
        self.tokens = capacity
        self.lastRefill = now
    }

    public mutating func allow(now: Date = Date()) -> Bool {
        let elapsed = now.timeIntervalSince(lastRefill)
        if elapsed > 0 {
            tokens = min(capacity, tokens + elapsed * refillPerSecond)
            lastRefill = now
        }
        guard tokens >= 1 else { return false }
        tokens -= 1
        return true
    }
}
