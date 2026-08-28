import Foundation

/// Découpe le flux TCP en messages.
///
/// Le cadrage est un entier 32 bits big-endian suivi du corps JSON. Une
/// longueur qui dépasse `maxFrameBytes` ferme la session au lieu d'allouer :
/// c'est la première ligne de défense contre un pair hostile du réseau local,
/// avant même la vérification de signature.
public struct MessageFramer: Sendable {
    public enum FramingError: Error, Equatable, Sendable {
        case frameTooLarge(declared: Int, maximum: Int)
        case invalidLength
    }

    private var buffer = Data()

    public init() {}

    /// Préfixe une charge utile de sa longueur.
    public static func frame(_ payload: Data) throws -> Data {
        guard payload.count <= ProtocolLimits.maxFrameBytes else {
            throw FramingError.frameTooLarge(
                declared: payload.count,
                maximum: ProtocolLimits.maxFrameBytes
            )
        }
        var out = Data(capacity: payload.count + 4)
        var length = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: &length) { out.append(contentsOf: $0) }
        out.append(payload)
        return out
    }

    /// Ajoute des octets reçus et retourne les messages complets.
    public mutating func append(_ bytes: Data) throws -> [Data] {
        buffer.append(bytes)
        var messages: [Data] = []

        while buffer.count >= 4 {
            let header = buffer.prefix(4)
            let declared = header.withUnsafeBytes { raw in
                UInt32(bigEndian: raw.loadUnaligned(as: UInt32.self))
            }
            let length = Int(declared)

            guard length >= 0 else { throw FramingError.invalidLength }
            guard length <= ProtocolLimits.maxFrameBytes else {
                throw FramingError.frameTooLarge(
                    declared: length,
                    maximum: ProtocolLimits.maxFrameBytes
                )
            }
            guard buffer.count >= 4 + length else { break }

            let start = buffer.index(buffer.startIndex, offsetBy: 4)
            let end = buffer.index(start, offsetBy: length)
            messages.append(Data(buffer[start..<end]))
            buffer = Data(buffer[end...])
        }

        return messages
    }

    public mutating func reset() {
        buffer.removeAll(keepingCapacity: false)
    }
}
