import AppKit
import CoreGraphics
import Foundation
import ImageIO

enum ScreenshotTarget {
    case frontmostWindow
    case screen
    case region(CGRect)
}

enum ScreenshotSupport {
    static func screenCaptureAccess() -> Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightScreenCaptureAccess()
        }
        return true
    }

    static func ensureDirectory(for path: URL) throws {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    static func capture(target: ScreenshotTarget, path: String) throws -> [String: Any] {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard url.path.lowercased().hasSuffix(".png") else {
            throw CUAError(message: "screenshot currently requires a .png output path")
        }
        try ensureDirectory(for: url)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = arguments(for: target, outputPath: url.path)
        let stderr = Pipe()
        process.standardError = stderr
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw CUAError(message: "failed to launch screencapture: \(error.localizedDescription)")
        }
        if process.terminationStatus != 0 {
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw CUAError(message: message?.isEmpty == false ? message! : "screencapture failed")
        }

        let dimensions = try pngDimensions(at: url)
        let actionSpace = try InputSupport.actionSpace()
        return [
            "path": url.path,
            "target": targetName(target),
            "bounds": bounds(for: target).map(rectJSON) as Any,
            "image": [
                "width": dimensions.width,
                "height": dimensions.height,
            ],
            "actionSpace": actionSpace,
        ]
    }

    static func arguments(for target: ScreenshotTarget, outputPath: String) -> [String] {
        switch target {
        case .frontmostWindow:
            if let window = WindowSupport.frontmostWindow(), let id = window.id {
                return ["-x", "-l", String(id), outputPath]
            }
            return ["-x", "-m", outputPath]
        case .screen:
            return ["-x", "-m", outputPath]
        case .region(let rect):
            let region = "\(Int(rect.origin.x.rounded())),\(Int(rect.origin.y.rounded())),\(Int(rect.size.width.rounded())),\(Int(rect.size.height.rounded()))"
            return ["-x", "-R\(region)", outputPath]
        }
    }

    static func targetName(_ target: ScreenshotTarget) -> String {
        switch target {
        case .frontmostWindow: return "frontmost-window"
        case .screen: return "screen"
        case .region: return "region"
        }
    }

    static func bounds(for target: ScreenshotTarget) -> CGRect? {
        switch target {
        case .frontmostWindow:
            return WindowSupport.frontmostWindow()?.bounds
        case .screen:
            guard let screen = NSScreen.main else { return nil }
            return CGRect(origin: .zero, size: screen.frame.size)
        case .region(let rect):
            return rect
        }
    }

    static func pngDimensions(at url: URL) throws -> (width: Int, height: Int) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw CUAError(message: "failed to read screenshot dimensions: \(url.path)")
        }
        return (width, height)
    }
}
