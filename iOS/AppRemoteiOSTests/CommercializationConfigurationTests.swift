import XCTest
@testable import VibeRemoteiOS

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
}
