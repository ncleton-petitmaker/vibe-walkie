import XCTest
@testable import VibeWalkieMac

final class CommercializationConfigurationTests: XCTestCase {
    func testWorkingBundleIdentifierAndMinimumSystem() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.nicolascleton.viberemote.mac")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String, "15.0")
        XCTAssertNotEqual(Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool, true)
    }

    func testBonjourAndSparkleConfigurationAreEmbedded() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "NSBonjourServices") as? [String], ["_viberemote._tcp"])
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            "https://ncleton-petitmaker.github.io/vibe-walkie/appcast.xml"
        )
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
            "nQ6eywkcEooao6zZ73sWlafO396coAq3i5+Qn2UmU/o="
        )
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "SUEnableAutomaticChecks") as? Bool, true)
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "SUEnableSystemProfiling") as? Bool, false)
    }

    func testPrivacyAndThirdPartyNoticesAreBundled() {
        XCTAssertNotNil(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        XCTAssertNotNil(Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md"))
        XCTAssertNotNil(Bundle.main.url(forResource: "Apache-2.0", withExtension: "txt"))
        XCTAssertNotNil(Bundle.main.url(forResource: "Sparkle", withExtension: "txt"))
        XCTAssertNotNil(Bundle.main.url(forResource: "SwiftCrypto-NOTICE", withExtension: "txt"))
        XCTAssertNotNil(Bundle.main.url(forResource: "SwiftASN1-NOTICE", withExtension: "txt"))
        XCTAssertNotNil(Bundle.main.url(forResource: "SwiftCertificates-NOTICE", withExtension: "txt"))
    }
}
