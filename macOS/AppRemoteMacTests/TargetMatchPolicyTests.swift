import XCTest
import RemoteCore
@testable import VibeRemoteMac

final class TargetMatchPolicyTests: XCTestCase {
    private let captured = TargetMatchPolicy.Snapshot(
        processIdentifier: 100,
        accessibilityIdentifier: "message-body",
        role: "AXTextArea",
        subrole: nil
    )

    func testExactAccessibilityElementIsAccepted() throws {
        try TargetMatchPolicy.validate(
            captured: captured,
            current: .init(
                processIdentifier: 100,
                accessibilityIdentifier: nil,
                role: "AXUnknown",
                subrole: nil
            ),
            isExactElement: true,
            isSameWindow: false,
            currentIsSecure: false
        )
    }

    func testStableIdentifierWindowRoleAndProcessAreAccepted() throws {
        try TargetMatchPolicy.validate(
            captured: captured,
            current: captured,
            isExactElement: false,
            isSameWindow: true,
            currentIsSecure: false
        )
    }

    func testApplicationChangeIsRejected() {
        assertError(.targetChanged) {
            try TargetMatchPolicy.validate(
                captured: captured,
                current: .init(
                    processIdentifier: 200,
                    accessibilityIdentifier: "message-body",
                    role: "AXTextArea",
                    subrole: nil
                ),
                isExactElement: false,
                isSameWindow: true,
                currentIsSecure: false
            )
        }
    }

    func testWindowChangeIsRejected() {
        assertError(.targetChanged) {
            try TargetMatchPolicy.validate(
                captured: captured,
                current: captured,
                isExactElement: false,
                isSameWindow: false,
                currentIsSecure: false
            )
        }
    }

    func testFieldIdentifierChangeIsRejected() {
        assertError(.targetChanged) {
            try TargetMatchPolicy.validate(
                captured: captured,
                current: .init(
                    processIdentifier: 100,
                    accessibilityIdentifier: "subject",
                    role: "AXTextArea",
                    subrole: nil
                ),
                isExactElement: false,
                isSameWindow: true,
                currentIsSecure: false
            )
        }
    }

    func testEmptyIdentifierCannotAuthorizeFallback() {
        assertError(.targetChanged) {
            try TargetMatchPolicy.validate(
                captured: .init(
                    processIdentifier: 100,
                    accessibilityIdentifier: "",
                    role: "AXTextArea",
                    subrole: nil
                ),
                current: .init(
                    processIdentifier: 100,
                    accessibilityIdentifier: "",
                    role: "AXTextArea",
                    subrole: nil
                ),
                isExactElement: false,
                isSameWindow: true,
                currentIsSecure: false
            )
        }
    }

    func testRoleChangeIsRejected() {
        assertError(.targetChanged) {
            try TargetMatchPolicy.validate(
                captured: captured,
                current: .init(
                    processIdentifier: 100,
                    accessibilityIdentifier: "message-body",
                    role: "AXTextField",
                    subrole: nil
                ),
                isExactElement: false,
                isSameWindow: true,
                currentIsSecure: false
            )
        }
    }

    func testSecureFieldIsAlwaysRejected() {
        assertError(.secureField) {
            try TargetMatchPolicy.validate(
                captured: captured,
                current: captured,
                isExactElement: true,
                isSameWindow: true,
                currentIsSecure: true
            )
        }
    }

    func testWindowFallbackAcceptsSameApplicationAndWindow() throws {
        try TargetMatchPolicy.validateWindowFallback(
            capturedProcessIdentifier: 100,
            currentProcessIdentifier: 100,
            isSameWindow: true,
            secureInputEnabled: false
        )
    }

    func testWindowFallbackRejectsApplicationOrWindowChange() {
        assertError(.targetChanged) {
            try TargetMatchPolicy.validateWindowFallback(
                capturedProcessIdentifier: 100,
                currentProcessIdentifier: 200,
                isSameWindow: true,
                secureInputEnabled: false
            )
        }
        assertError(.targetChanged) {
            try TargetMatchPolicy.validateWindowFallback(
                capturedProcessIdentifier: 100,
                currentProcessIdentifier: 100,
                isSameWindow: false,
                secureInputEnabled: false
            )
        }
    }

    func testWindowFallbackRejectsSecureInput() {
        assertError(.secureField) {
            try TargetMatchPolicy.validateWindowFallback(
                capturedProcessIdentifier: 100,
                currentProcessIdentifier: 100,
                isSameWindow: true,
                secureInputEnabled: true
            )
        }
    }

    private func assertError(
        _ expected: RemoteErrorCode,
        operation: () throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual((error as? RemoteErrorPayload)?.code, expected, file: file, line: line)
        }
    }
}
