import CoreGraphics
import Foundation

enum CoordinateSpaceName: String {
    case window
    case screen
}

struct CoordinateResolution {
    let coordinateSpace: CoordinateSpaceName
    let coordinateFallback: Bool
    let window: WindowRecord?

    var windowBounds: CGRect? {
        window?.bounds
    }

    func translate(point: CGPoint) -> CGPoint {
        guard coordinateSpace == .window, let bounds = windowBounds else {
            return point
        }
        return CGPoint(x: bounds.origin.x + point.x, y: bounds.origin.y + point.y)
    }

    func translate(rect: CGRect) -> CGRect {
        CGRect(origin: translate(point: rect.origin), size: rect.size)
    }

    func localPointer(fromScreenPoint point: CGPoint) -> CGPoint? {
        guard let bounds = windowBounds else { return nil }
        return CGPoint(x: point.x - bounds.origin.x, y: point.y - bounds.origin.y)
    }

    func screenshotBounds(for target: ScreenshotTarget) -> CGRect? {
        switch target {
        case .frontmostWindow:
            guard let bounds = windowBounds else { return nil }
            if coordinateSpace == .window {
                return CGRect(origin: .zero, size: bounds.size)
            }
            return bounds
        case .screen:
            return ScreenshotSupport.screenBounds()
        case .region(let rect):
            return rect
        }
    }
}

enum CoordinateSupport {
    static func resolve(explicitScreen: Bool, frontmostWindow: WindowRecord? = WindowSupport.frontmostWindow()) -> CoordinateResolution {
        if explicitScreen {
            return CoordinateResolution(coordinateSpace: .screen, coordinateFallback: false, window: frontmostWindow)
        }
        if let frontmostWindow {
            return CoordinateResolution(coordinateSpace: .window, coordinateFallback: false, window: frontmostWindow)
        }
        return CoordinateResolution(coordinateSpace: .screen, coordinateFallback: true, window: nil)
    }

    static func pointJSON(_ point: CGPoint) -> [String: Any] {
        [
            "x": Int(point.x.rounded()),
            "y": Int(point.y.rounded()),
        ]
    }
}
