import Foundation
import Security
import XCTest
@testable import VibeRemoteMac

final class TLSIdentityStoreTests: XCTestCase {
    private var configuration: TLSIdentityStore.Configuration!

    override func setUp() {
        super.setUp()
        let id = UUID().uuidString
        configuration = .init(
            label: "Vibe Remote Tests \(id)",
            keyTag: Data("com.nicolascleton.viberemote.tests.\(id)".utf8)
        )
    }

    override func tearDown() {
        try? TLSIdentityStore.deleteAll(configuration: configuration)
        configuration = nil
        super.tearDown()
    }

    func testFreshIdentityIsCreatedAndLoadable() throws {
        let created = try TLSIdentityStore.loadOrCreate(configuration: configuration)
        let loaded = try TLSIdentityStore.load(configuration: configuration)
        XCTAssertEqual(
            try TLSIdentityStore.fingerprint(of: created),
            try TLSIdentityStore.fingerprint(of: loaded)
        )
    }

    func testFingerprintIsStableAcrossLaunches() throws {
        let first = try TLSIdentityStore.loadOrCreate(configuration: configuration)
        let second = try TLSIdentityStore.loadOrCreate(configuration: configuration)
        XCTAssertEqual(
            try TLSIdentityStore.fingerprint(of: first),
            try TLSIdentityStore.fingerprint(of: second)
        )
    }

    func testRegenerationChangesFingerprint() throws {
        let first = try TLSIdentityStore.loadOrCreate(configuration: configuration)
        let before = try TLSIdentityStore.fingerprint(of: first)
        let regenerated = try TLSIdentityStore.regenerate(configuration: configuration)
        XCTAssertNotEqual(before, try TLSIdentityStore.fingerprint(of: regenerated))
    }

    func testPartialKeyStateIsRejected() throws {
        var error: Unmanaged<CFError>?
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrIsPermanent as String: true,
            kSecAttrApplicationTag as String: configuration.keyTag,
            kSecAttrLabel as String: configuration.label
        ]
        XCTAssertNotNil(SecKeyCreateRandomKey(attributes as CFDictionary, &error))
        XCTAssertThrowsError(try TLSIdentityStore.loadOrCreate(configuration: configuration)) { error in
            XCTAssertEqual(error as? TLSIdentityStore.StoreError, .partialState)
        }
    }

    func testMissingCertificateAfterCreationIsRejectedAsPartial() throws {
        _ = try TLSIdentityStore.loadOrCreate(configuration: configuration)
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: configuration.label
        ]
        XCTAssertEqual(SecItemDelete(query as CFDictionary), errSecSuccess)
        XCTAssertThrowsError(try TLSIdentityStore.loadOrCreate(configuration: configuration)) { error in
            XCTAssertEqual(error as? TLSIdentityStore.StoreError, .partialState)
        }
    }

    func testFingerprintIsSHA256Base64() throws {
        let identity = try TLSIdentityStore.loadOrCreate(configuration: configuration)
        let fingerprint = try TLSIdentityStore.fingerprint(of: identity)
        XCTAssertEqual(Data(base64Encoded: fingerprint)?.count, 32)
    }
}
