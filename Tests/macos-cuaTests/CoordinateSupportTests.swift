import CoreGraphics
import XCTest
@testable import macos_cua

final class CoordinateSupportTests: XCTestCase {
    func testResolveDefaultsToWindowWhenFrontmostWindowExists() {
        let window = makeWindow(bounds: CGRect(x: 120, y: 80, width: 900, height: 700))

        let resolution = CoordinateSupport.resolve(explicitScreen: false, frontmostWindow: window)

        XCTAssertEqual(resolution.coordinateSpace, .window)
        XCTAssertFalse(resolution.coordinateFallback)
        XCTAssertEqual(resolution.window?.bounds.origin.x, 120)
        XCTAssertEqual(resolution.window?.bounds.origin.y, 80)
    }

    func testResolveFallsBackToScreenWhenWindowIsMissing() {
        let resolution = CoordinateSupport.resolve(explicitScreen: false, frontmostWindow: nil)

        XCTAssertEqual(resolution.coordinateSpace, .screen)
        XCTAssertTrue(resolution.coordinateFallback)
        XCTAssertNil(resolution.window)
    }

    func testExplicitScreenBypassesWindowOffset() {
        let window = makeWindow(bounds: CGRect(x: 400, y: 300, width: 800, height: 600))
        let resolution = CoordinateSupport.resolve(explicitScreen: true, frontmostWindow: window)
        let point = CGPoint(x: 25, y: 40)

        XCTAssertEqual(resolution.translate(point: point).x, 25, accuracy: 0.0001)
        XCTAssertEqual(resolution.translate(point: point).y, 40, accuracy: 0.0001)
        XCTAssertFalse(resolution.coordinateFallback)
    }

    func testWindowTranslationMapsLocalPointIntoScreenSpace() {
        let window = makeWindow(bounds: CGRect(x: 300, y: 180, width: 640, height: 480))
        let resolution = CoordinateSupport.resolve(explicitScreen: false, frontmostWindow: window)
        let translated = resolution.translate(point: CGPoint(x: 17, y: 23))

        XCTAssertEqual(translated.x, 317, accuracy: 0.0001)
        XCTAssertEqual(translated.y, 203, accuracy: 0.0001)
    }

    func testLocalPointerSubtractsWindowOrigin() {
        let window = makeWindow(bounds: CGRect(x: 220, y: 140, width: 900, height: 700))
        let resolution = CoordinateSupport.resolve(explicitScreen: false, frontmostWindow: window)
        let pointer = resolution.localPointer(fromScreenPoint: CGPoint(x: 260, y: 175))

        XCTAssertEqual(pointer?.x, 40, accuracy: 0.0001)
        XCTAssertEqual(pointer?.y, 35, accuracy: 0.0001)
    }

    func testFrontmostWindowScreenshotBoundsUseLocalOrigin() {
        let window = makeWindow(bounds: CGRect(x: 10, y: 20, width: 500, height: 400))
        let resolution = CoordinateSupport.resolve(explicitScreen: false, frontmostWindow: window)
        let bounds = resolution.screenshotBounds(for: .frontmostWindow)

        XCTAssertEqual(bounds?.origin.x, 0, accuracy: 0.0001)
        XCTAssertEqual(bounds?.origin.y, 0, accuracy: 0.0001)
        XCTAssertEqual(bounds?.size.width, 500, accuracy: 0.0001)
        XCTAssertEqual(bounds?.size.height, 400, accuracy: 0.0001)
    }

    func testWindowRegionScreenshotBoundsStayLocal() {
        let window = makeWindow(bounds: CGRect(x: 10, y: 20, width: 500, height: 400))
        let resolution = CoordinateSupport.resolve(explicitScreen: false, frontmostWindow: window)
        let region = CGRect(x: 30, y: 40, width: 120, height: 80)
        let bounds = resolution.screenshotBounds(for: .region(region))

        XCTAssertEqual(bounds?.origin.x, 30, accuracy: 0.0001)
        XCTAssertEqual(bounds?.origin.y, 40, accuracy: 0.0001)
        XCTAssertEqual(bounds?.size.width, 120, accuracy: 0.0001)
        XCTAssertEqual(bounds?.size.height, 80, accuracy: 0.0001)
    }

    private func makeWindow(bounds: CGRect) -> WindowRecord {
        WindowRecord(
            id: 99,
            pid: 123,
            appName: "TestApp",
            title: "Test Window",
            bounds: bounds,
            layer: 0,
            onScreen: true,
            isFrontmost: true
        )
    }
}
