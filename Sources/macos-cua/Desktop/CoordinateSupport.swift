import AppKit
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

    // Reference dimensions for relative coordinate scaling (1000 == full width or height).
    static func referenceSize(for resolution: CoordinateResolution) -> CGSize {
        switch resolution.coordinateSpace {
        case .window:
            if let size = resolution.window?.bounds.size, size.width > 0, size.height > 0 {
                return size
            }
            fallthrough
        case .screen:
            return NSScreen.main?.frame.size ?? .zero
        }
    }

    // Convert a [0, 1000] relative point to an absolute point in the resolution's local space.
    static func denormalize(_ relative: CGPoint, resolution: CoordinateResolution) -> CGPoint {
        let ref = referenceSize(for: resolution)
        guard ref.width > 0, ref.height > 0 else { return .zero }
        return CGPoint(x: relative.x * ref.width / 1000, y: relative.y * ref.height / 1000)
    }

    // Convert a [0, 1000] relative rect (origin + size all relative) to absolute local space.
    static func denormalize(_ relative: CGRect, resolution: CoordinateResolution) -> CGRect {
        let ref = referenceSize(for: resolution)
        guard ref.width > 0, ref.height > 0 else { return .zero }
        return CGRect(
            x: relative.origin.x * ref.width / 1000,
            y: relative.origin.y * ref.height / 1000,
            width: relative.width * ref.width / 1000,
            height: relative.height * ref.height / 1000
        )
    }

    // Convert an absolute local-space point to [0, 1000] relative.
    static func normalize(_ absolute: CGPoint, resolution: CoordinateResolution) -> CGPoint {
        let ref = referenceSize(for: resolution)
        guard ref.width > 0, ref.height > 0 else { return .zero }
        return CGPoint(
            x: (absolute.x / ref.width * 1000).rounded(),
            y: (absolute.y / ref.height * 1000).rounded()
        )
    }

    // Convert an absolute local-space rect to [0, 1000] relative.
    static func normalize(_ absolute: CGRect, resolution: CoordinateResolution) -> CGRect {
        let ref = referenceSize(for: resolution)
        guard ref.width > 0, ref.height > 0 else { return .zero }
        return CGRect(
            x: (absolute.origin.x / ref.width * 1000).rounded(),
            y: (absolute.origin.y / ref.height * 1000).rounded(),
            width: (absolute.width / ref.width * 1000).rounded(),
            height: (absolute.height / ref.height * 1000).rounded()
        )
    }

    static func pointJSON(_ point: CGPoint) -> [String: Any] {
        ["x": Int(point.x.rounded()), "y": Int(point.y.rounded())]
    }

    static func rectJSON(_ rect: CGRect) -> [String: Any] {
        [
            "x": Int(rect.origin.x.rounded()),
            "y": Int(rect.origin.y.rounded()),
            "width": Int(rect.width.rounded()),
            "height": Int(rect.height.rounded()),
        ]
    }
}
