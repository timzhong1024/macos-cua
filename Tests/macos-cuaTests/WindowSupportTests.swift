import ApplicationServices
import CoreGraphics
import XCTest
@testable import macos_cua

final class WindowSupportTests: XCTestCase {
    func testModalSubroleIsRecognized() {
        XCTAssertTrue(WindowSupport.isModalLikeWindow(role: "AXWindow", subrole: "AXDialog"))
        XCTAssertTrue(WindowSupport.isModalLikeWindow(role: "AXWindow", subrole: "AXFloatingWindow"))
    }

    func testModalRoleIsRecognized() {
        XCTAssertTrue(WindowSupport.isModalLikeWindow(role: "AXSheet", subrole: nil))
        XCTAssertTrue(WindowSupport.isModalLikeWindow(role: "AXDrawer", subrole: nil))
        XCTAssertFalse(WindowSupport.isModalLikeWindow(role: "AXWindow", subrole: "AXStandardWindow"))
    }

    func testFallbackWindowIDRequiresCloseBoundsOrSameTitle() {
        let fallback = WindowRecord(
            id: 42,
            pid: 99,
            appName: "TestApp",
            title: "Main Window",
            bounds: CGRect(x: 100, y: 80, width: 1200, height: 900),
            layer: 0,
            onScreen: true,
            isFrontmost: true
        )

        XCTAssertTrue(
            WindowSupport.shouldAssociateFallbackWindowID(
                title: "Main Window",
                bounds: CGRect(x: 400, y: 300, width: 500, height: 400),
                fallback: fallback
            )
        )
        XCTAssertTrue(
            WindowSupport.shouldAssociateFallbackWindowID(
                title: "",
                bounds: CGRect(x: 104, y: 82, width: 1194, height: 896),
                fallback: fallback
            )
        )
        XCTAssertFalse(
            WindowSupport.shouldAssociateFallbackWindowID(
                title: "",
                bounds: CGRect(x: 500, y: 420, width: 420, height: 240),
                fallback: fallback
            )
        )
    }

    func testBlockingModalStateFlagsFocusedDialog() {
        let focused = WindowSupport.WindowDescriptor(
            record: makeWindow(id: 20, title: "Save", bounds: CGRect(x: 360, y: 220, width: 520, height: 320)),
            role: "AXWindow",
            subrole: "AXDialog"
        )
        let main = WindowSupport.WindowDescriptor(
            record: makeWindow(id: 10, title: "Document", bounds: CGRect(x: 100, y: 80, width: 1200, height: 900)),
            role: "AXWindow",
            subrole: "AXStandardWindow"
        )

        let state = WindowSupport.blockingModalState(
            focused: focused,
            main: main,
            focusedElement: AXUIElementCreateApplication(111),
            mainElement: AXUIElementCreateApplication(222)
        )

        XCTAssertTrue(state.blockingModalPresent)
        XCTAssertTrue(state.interactionBlocked)
        XCTAssertEqual((state.payload["requiredAction"] as? String), "dismiss-or-handle-modal")
        XCTAssertEqual((state.payload["blockedTargets"] as? [String]) ?? [], ["main-window"])
    }

    func testBlockingModalStateIgnoresNonModalFocusedWindow() {
        let focused = WindowSupport.WindowDescriptor(
            record: makeWindow(id: 20, title: "Inspector", bounds: CGRect(x: 360, y: 220, width: 520, height: 320)),
            role: "AXWindow",
            subrole: "AXStandardWindow"
        )
        let main = WindowSupport.WindowDescriptor(
            record: makeWindow(id: 10, title: "Document", bounds: CGRect(x: 100, y: 80, width: 1200, height: 900)),
            role: "AXWindow",
            subrole: "AXStandardWindow"
        )

        let state = WindowSupport.blockingModalState(
            focused: focused,
            main: main,
            focusedElement: AXUIElementCreateApplication(111),
            mainElement: AXUIElementCreateApplication(222)
        )

        XCTAssertFalse(state.blockingModalPresent)
        XCTAssertFalse(state.interactionBlocked)
        XCTAssertNil(state.payload["requiredAction"])
    }

    private func makeWindow(id: Int, title: String, bounds: CGRect) -> WindowRecord {
        WindowRecord(
            id: id,
            pid: 123,
            appName: "TestApp",
            title: title,
            bounds: bounds,
            layer: 0,
            onScreen: true,
            isFrontmost: true
        )
    }
}
