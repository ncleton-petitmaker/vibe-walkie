import XCTest
import RemoteCore
@testable import VibeWalkieiOS

final class CommercializationConfigurationTests: XCTestCase {
    func testWorkingBundleIdentifierAndFrenchPermissionCopy() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.nicolascleton.viberemote")
        XCTAssertNotNil(Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String)
        XCTAssertNotNil(Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") as? String)
        XCTAssertNotNil(Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") as? String)
        XCTAssertNotNil(Bundle.main.object(forInfoDictionaryKey: "NSLocalNetworkUsageDescription") as? String)
    }

    func testBonjourAndEncryptionDeclarationsAreEmbedded() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "NSBonjourServices") as? [String], ["_viberemote._tcp"])
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "ITSAppUsesNonExemptEncryption") as? Bool, false)
    }

    func testPrivacyManifestIsBundled() {
        XCTAssertNotNil(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
    }

    func testPairedMacV1StorageMigratesWithoutNomadEndpoint() throws {
        let legacy = Data(#"""
        {
          "name": "Mac de test",
          "serviceName": "VibeWalkie-Test",
          "certificateFingerprint": "fingerprint"
        }
        """#.utf8)
        let paired = try RemoteCoding.decoder.decode(PairedMac.self, from: legacy)
        XCTAssertEqual(paired.name, "Mac de test")
        XCTAssertNil(paired.nomadEndpoint)
    }

    func testPairedMacPersistsOnlyAValidTailscaleEndpoint() {
        let valid = NomadEndpoint(
            magicDNSName: "mac-vibe.tail123.ts.net",
            ipv4Address: "100.101.22.8"
        )
        let paired = PairedMac(
            name: "Mac de test",
            serviceName: "VibeWalkie-Test",
            certificateFingerprint: "fingerprint",
            nomadEndpoint: valid
        )
        XCTAssertEqual(paired.nomadEndpoint, valid)

        let invalid = NomadEndpoint(
            magicDNSName: "example.com",
            ipv4Address: "8.8.8.8"
        )
        let rejected = PairedMac(
            name: "Mac de test",
            serviceName: "VibeWalkie-Test",
            certificateFingerprint: "fingerprint",
            nomadEndpoint: invalid
        )
        XCTAssertNil(rejected.nomadEndpoint)
    }

    func testPairedMacStoreMigratesLegacySelection() throws {
        let defaults = try makeDefaults()
        let legacy = PairedMac(
            name: "Ancien Mac",
            serviceName: "VibeWalkie-Legacy",
            certificateFingerprint: "legacy-fingerprint"
        )
        defaults.set(
            try RemoteCoding.encoder.encode(legacy),
            forKey: "com.nicolascleton.viberemote.pairedMac"
        )

        let state = PairedMacStore.load(defaults: defaults)

        XCTAssertEqual(state.macs, [legacy])
        XCTAssertEqual(state.selectedMac, legacy)
        XCTAssertNil(defaults.data(forKey: "com.nicolascleton.viberemote.pairedMac"))
    }

    func testPairedMacStoreAddsSelectsAndRemovesMacs() throws {
        let defaults = try makeDefaults()
        let office = PairedMac(
            name: "Mac bureau",
            serviceName: "VibeWalkie-Office",
            certificateFingerprint: "office-fingerprint"
        )
        let home = PairedMac(
            name: "Mac maison",
            serviceName: "VibeWalkie-Home",
            certificateFingerprint: "home-fingerprint"
        )

        _ = PairedMacStore.upsert(office, select: true, defaults: defaults)
        var state = PairedMacStore.upsert(home, select: false, defaults: defaults)
        XCTAssertEqual(state.macs, [office, home])
        XCTAssertEqual(state.selectedMac, office)

        state = PairedMacStore.select(home.id, defaults: defaults)
        XCTAssertEqual(state.selectedMac, home)

        state = PairedMacStore.remove(home.id, defaults: defaults)
        XCTAssertEqual(state.macs, [office])
        XCTAssertEqual(state.selectedMac, office)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "CommercializationConfigurationTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw XCTSkip("Impossible de créer un domaine UserDefaults isolé")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
