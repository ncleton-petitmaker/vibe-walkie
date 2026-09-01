import XCTest
@testable import VibeWalkieMac

final class ScreenCaptureAuthorizationStateTests: XCTestCase {
    func testPermissionAlreadyGrantedAtLaunchMustBeVerified() {
        var state = ScreenCaptureAuthorizationState(isGrantedAtLaunch: true)

        XCTAssertTrue(state.isGranted)
        XCTAssertFalse(state.requiresRelaunch)
        XCTAssertEqual(state.readiness, .verifying)
        XCTAssertFalse(state.isReady)

        state.completeVerification(succeeded: true)

        XCTAssertEqual(state.readiness, .ready)
        XCTAssertTrue(state.isReady)
    }

    func testPermissionGrantedWhileRunningRequiresOneRelaunch() {
        var state = ScreenCaptureAuthorizationState(isGrantedAtLaunch: false)

        state.update(isGranted: true)

        XCTAssertTrue(state.isGranted)
        XCTAssertTrue(state.requiresRelaunch)
        XCTAssertEqual(state.readiness, .relaunchRequired)
    }

    func testFreshProcessClearsTheRelaunchRequirement() {
        var previousProcess = ScreenCaptureAuthorizationState(isGrantedAtLaunch: false)
        previousProcess.update(isGranted: true)
        XCTAssertTrue(previousProcess.requiresRelaunch)

        let relaunchedProcess = ScreenCaptureAuthorizationState(isGrantedAtLaunch: true)
        XCTAssertTrue(relaunchedProcess.isGranted)
        XCTAssertFalse(relaunchedProcess.requiresRelaunch)
        XCTAssertEqual(relaunchedProcess.readiness, .verifying)
    }

    func testRevokingThenRegrantingRequiresAnotherRelaunch() {
        var state = ScreenCaptureAuthorizationState(isGrantedAtLaunch: true)

        state.update(isGranted: false)
        XCTAssertFalse(state.requiresRelaunch)

        state.update(isGranted: true)
        XCTAssertTrue(state.requiresRelaunch)
    }

    func testFailedRuntimeVerificationDoesNotReportReady() {
        var state = ScreenCaptureAuthorizationState(isGrantedAtLaunch: true)

        state.completeVerification(succeeded: false)

        XCTAssertEqual(state.readiness, .failed)
        XCTAssertFalse(state.isReady)
    }

    func testVerificationCannotBypassRequiredRelaunch() {
        var state = ScreenCaptureAuthorizationState(isGrantedAtLaunch: false)
        state.update(isGranted: true)

        state.completeVerification(succeeded: true)

        XCTAssertEqual(state.readiness, .relaunchRequired)
        XCTAssertFalse(state.isReady)
    }
}
