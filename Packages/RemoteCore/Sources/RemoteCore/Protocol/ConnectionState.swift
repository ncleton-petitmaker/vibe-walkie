import Foundation

/// Chemin réseau effectivement utilisé par la session courante.
public enum ConnectionRoute: String, Codable, Equatable, Sendable {
    case local
    case nomad

    /// Le LAN reste le chemin préféré : moins de latence, pas de tunnel à
    /// réveiller et davantage de débit pour le retour écran.
    public func isPreferred(over current: ConnectionRoute) -> Bool {
        self == .local && current == .nomad
    }
}

/// États visibles de la liaison du mobile vers un compagnon de bureau.
public enum ConnectionState: Equatable, Sendable {
    case idle
    case searching
    case connecting(hostName: String)
    case pairing(hostName: String, confirmationCode: String)
    case awaitingApproval(hostName: String, confirmationCode: String)
    case ready(hostName: String)
    case failed(RemoteErrorCode)

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    public var hostName: String? {
        switch self {
        case .connecting(let name), .ready(let name): return name
        case .pairing(let name, _), .awaitingApproval(let name, _): return name
        default: return nil
        }
    }

    /// Compatibilité source temporaire avec l'interface iOS V3.
    public var macName: String? { hostName }
}

extension RemoteErrorCode: Equatable {}

/// Backoff exponentiel avec gigue.
///
/// La gigue n'est pas cosmétique : sans elle, un iPhone et un Mac qui se
/// réveillent ensemble retentent en cadence et se manquent à chaque fois.
public struct RetryPolicy: Sendable {
    private let base: TimeInterval
    private let maximum: TimeInterval
    private var attempt: Int = 0

    public init(base: TimeInterval = 0.5, maximum: TimeInterval = 20) {
        self.base = base
        self.maximum = maximum
    }

    public mutating func nextDelay() -> TimeInterval {
        let exponential = min(maximum, base * pow(2, Double(attempt)))
        attempt += 1
        let jitter = Double.random(in: 0.75...1.25)
        return min(maximum, exponential * jitter)
    }

    public mutating func reset() {
        attempt = 0
    }

    public var attemptCount: Int { attempt }
}
