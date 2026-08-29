import XCTest
import RemoteCore
@testable import VibeWalkieMac

final class ControlInputPolicyTests: XCTestCase {
    func testGestureDeltasAreBounded() throws {
        XCTAssertEqual(try ControlInputPolicy.gestureDelta(-9_000), -600)
        XCTAssertEqual(try ControlInputPolicy.gestureDelta(9_000), 600)
        XCTAssertEqual(try ControlInputPolicy.gestureDelta(42.5), 42.5)
    }

    func testNonFiniteGestureDeltasAreRejected() {
        for value in [Double.nan, .infinity, -.infinity] {
            XCTAssertThrowsError(try ControlInputPolicy.gestureDelta(value))
        }
    }

    func testNormalizedCoordinatesAreFiniteAndBounded() throws {
        XCTAssertEqual(try ControlInputPolicy.normalizedCoordinate(-1), 0)
        XCTAssertEqual(try ControlInputPolicy.normalizedCoordinate(2), 1)
        XCTAssertThrowsError(try ControlInputPolicy.normalizedCoordinate(.nan))
    }

    func testClickCountIsLimitedToOneThroughThree() {
        XCTAssertEqual(ControlInputPolicy.clickCount(-4), 1)
        XCTAssertEqual(ControlInputPolicy.clickCount(2), 2)
        XCTAssertEqual(ControlInputPolicy.clickCount(99), 3)
    }

    func testScreenSettingsAreBounded() throws {
        let settings = try ControlInputPolicy.screenSettings(for: .init(
            enabled: true,
            maxWidth: 20_000,
            framesPerSecond: 200,
            jpegQuality: 9
        ))
        XCTAssertEqual(settings.maxWidth, 1_920)
        XCTAssertEqual(settings.framesPerSecond, 20)
        XCTAssertEqual(settings.jpegQuality, 0.8)
    }

    func testScreenDimensionsPreserveAspectAndAreEven() throws {
        let settings = try ControlInputPolicy.screenSettings(for: .init(
            enabled: true,
            maxWidth: 1_280,
            framesPerSecond: 10,
            jpegQuality: 0.45
        ))
        let dimensions = settings.dimensions(displayWidth: 2_560, displayHeight: 1_600)
        XCTAssertEqual(dimensions.width, 1_280)
        XCTAssertEqual(dimensions.height, 800)
        XCTAssertEqual(dimensions.width % 2, 0)
        XCTAssertEqual(dimensions.height % 2, 0)
    }

    func testNonFiniteJPEGQualityIsRejected() {
        XCTAssertThrowsError(try ControlInputPolicy.screenSettings(for: .init(
            enabled: true,
            jpegQuality: .nan
        )))
    }
}
