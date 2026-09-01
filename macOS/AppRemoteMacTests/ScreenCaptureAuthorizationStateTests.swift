import XCTest
@testable import VibeWalkieMac

final class ScreenCaptureAuthorizationStateTests: XCTestCase {
    func testPermissionAlreadyGrantedAtLaunchIsImmediatelyReady() {
        let state = ScreenCaptureAuthorizationState(isGrantedAtLaunch: true)

        XCTAssertTrue(state.isGranted)
        XCTAssertFalse(state.requiresRelaunch)
    }

    func testPermissionGrantedWhileRunningRequiresOneRelaunch() {
        var state = ScreenCaptureAuthorizationState(isGrantedAtLaunch: false)

        state.update(isGranted: true)

        XCTAssertTrue(state.isGranted)
        XCTAssertTrue(state.requiresRelaunch)
    }

    func testFreshProcessClearsTheRelaunchRequirement() {
        var previousProcess = ScreenCaptureAuthorizationState(isGrantedAtLaunch: false)
        previousProcess.update(isGranted: true)
        XCTAssertTrue(previousProcess.requiresRelaunch)

        let relaunchedProcess = ScreenCaptureAuthorizationState(isGrantedAtLaunch: true)
        XCTAssertTrue(relaunchedProcess.isGranted)
        XCTAssertFalse(relaunchedProcess.requiresRelaunch)
    }

    func testRevokingThenRegrantingRequiresAnotherRelaunch() {
        var state = ScreenCaptureAuthorizationState(isGrantedAtLaunch: true)

        state.update(isGranted: false)
        XCTAssertFalse(state.requiresRelaunch)

        state.update(isGranted: true)
        XCTAssertTrue(state.requiresRelaunch)
    }
}
