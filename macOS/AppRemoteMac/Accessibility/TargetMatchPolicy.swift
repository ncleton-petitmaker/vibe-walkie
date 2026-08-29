import Foundation
import RemoteCore

/// Règle pure qui décide si le champ AX observé au relâchement représente
/// encore exactement la cible capturée au début de la dictée.
enum TargetMatchPolicy {
    struct Snapshot {
        let processIdentifier: pid_t
        let accessibilityIdentifier: String?
        let role: String?
        let subrole: String?
    }

    static func validate(
        captured: Snapshot,
        current: Snapshot,
        isExactElement: Bool,
        isSameWindow: Bool,
        currentIsSecure: Bool
    ) throws {
        guard current.processIdentifier == captured.processIdentifier else {
            throw RemoteErrorPayload(code: .targetChanged)
        }
        guard !currentIsSecure else {
            throw RemoteErrorPayload(code: .secureField)
        }

        let hasStableMatchingIdentifier = captured.accessibilityIdentifier?.isEmpty == false
            && current.accessibilityIdentifier == captured.accessibilityIdentifier
        let sameShape = current.role == captured.role && current.subrole == captured.subrole

        guard isExactElement || (isSameWindow && hasStableMatchingIdentifier && sameShape) else {
            throw RemoteErrorPayload(code: .targetChanged)
        }
    }

    /// Repli borné pour une application qui ne publie aucun champ AX.
    /// L'application et l'objet fenêtre doivent rester strictement identiques.
    static func validateWindowFallback(
        capturedProcessIdentifier: pid_t,
        currentProcessIdentifier: pid_t,
        isSameWindow: Bool,
        secureInputEnabled: Bool
    ) throws {
        guard !secureInputEnabled else {
            throw RemoteErrorPayload(code: .secureField)
        }
        guard currentProcessIdentifier == capturedProcessIdentifier, isSameWindow else {
            throw RemoteErrorPayload(code: .targetChanged)
        }
    }
}
