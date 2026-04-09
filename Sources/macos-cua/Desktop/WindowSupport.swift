import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum WindowSupport {
    static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    static func axAppElement(pid: pid_t) -> AXUIElement {
        AXUIElementCreateApplication(pid)
    }

    static func axValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value
    }

    static func axString(_ element: AXUIElement, _ attribute: String) -> String? {
        axValue(element, attribute) as? String
    }

    static func axElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = axValue(element, attribute) else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    static func axBool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        axValue(element, attribute) as? Bool
    }

    static func axPoint(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let value = axValue(element, attribute) else { return nil }
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgPoint else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
    }

    static func axSize(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let value = axValue(element, attribute) else { return nil }
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgSize else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(axValue, .cgSize, &size) ? size : nil
    }

    static func axWindows(for app: NSRunningApplication) -> [AXUIElement] {
        guard isAccessibilityTrusted() else { return [] }
        return (axValue(axAppElement(pid: app.processIdentifier), kAXWindowsAttribute) as? [AXUIElement]) ?? []
    }

    static func cgWindowInfoList(onScreenOnly: Bool) -> [[String: Any]] {
        let options: CGWindowListOption = onScreenOnly
            ? [.optionOnScreenOnly, .excludeDesktopElements]
            : [.optionAll, .excludeDesktopElements]
        let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as NSArray? as? [[String: Any]]
        return raw ?? []
    }

    static func bounds(from info: [String: Any]) -> CGRect? {
        guard let dictionary = info[kCGWindowBounds as String] as? [String: Any] else { return nil }
        return CGRect(dictionaryRepresentation: dictionary as CFDictionary)
    }

    static func interactiveWindows(onScreenOnly: Bool = true) -> [WindowRecord] {
        cgWindowInfoList(onScreenOnly: onScreenOnly).compactMap { info in
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1.0
            guard layer == 0, alpha > 0 else { return nil }
            guard let bounds = bounds(from: info), bounds.width > 1, bounds.height > 1 else { return nil }
            let pid = Int32(info[kCGWindowOwnerPID as String] as? Int ?? 0)
            let appName = info[kCGWindowOwnerName as String] as? String ?? "Unknown"
            let title = info[kCGWindowName as String] as? String ?? ""
            let id = info[kCGWindowNumber as String] as? Int
            return WindowRecord(
                id: id,
                pid: pid,
                appName: appName,
                title: title,
                bounds: bounds,
                layer: layer,
                onScreen: (info[kCGWindowIsOnscreen as String] as? Int ?? 0) != 0,
                isFrontmost: false
            )
        }
    }

    static func frontmostWindow() -> WindowRecord? {
        guard let app = AppSupport.frontmostApplication() else { return nil }

        let cgFallback = interactiveWindows().first(where: { $0.pid == app.processIdentifier })

        guard isAccessibilityTrusted() else {
            if let record = cgFallback {
                return WindowRecord(id: record.id, pid: record.pid, appName: record.appName, title: record.title, bounds: record.bounds, layer: record.layer, onScreen: record.onScreen, isFrontmost: true)
            }
            return nil
        }

        let appElement = axAppElement(pid: app.processIdentifier)
        guard let focused = axElement(appElement, kAXFocusedWindowAttribute) else {
            if let record = cgFallback {
                return WindowRecord(id: record.id, pid: record.pid, appName: record.appName, title: record.title, bounds: record.bounds, layer: record.layer, onScreen: record.onScreen, isFrontmost: true)
            }
            return nil
        }

        let title = axString(focused, kAXTitleAttribute) ?? (cgFallback?.title ?? "")
        let position = axPoint(focused, kAXPositionAttribute) ?? (cgFallback?.bounds.origin ?? .zero)
        let size = axSize(focused, kAXSizeAttribute) ?? (cgFallback?.bounds.size ?? .zero)
        let axBounds = CGRect(origin: position, size: size)
        let id = matchWindowID(pid: app.processIdentifier, title: title, bounds: axBounds) ?? cgFallback?.id
        return WindowRecord(
            id: id,
            pid: app.processIdentifier,
            appName: app.localizedName ?? "Unknown",
            title: title,
            bounds: axBounds,
            layer: 0,
            onScreen: true,
            isFrontmost: true
        )
    }

    static func matchWindowID(pid: pid_t, title: String, bounds: CGRect) -> Int? {
        let candidates = interactiveWindows().filter { $0.pid == pid }
        if let exact = candidates.first(where: { candidate in
            candidate.title == title &&
            abs(candidate.bounds.width - bounds.width) < 12 &&
            abs(candidate.bounds.height - bounds.height) < 12
        }) {
            return exact.id
        }
        if let titleOnly = candidates.first(where: { !$0.title.isEmpty && $0.title == title }) {
            return titleOnly.id
        }
        return candidates.first?.id
    }

    static func frontmostWindowAXElement() -> AXUIElement? {
        guard let app = AppSupport.frontmostApplication() else { return nil }
        guard isAccessibilityTrusted() else { return nil }
        return axElement(axAppElement(pid: app.processIdentifier), kAXFocusedWindowAttribute)
    }

    static func listWindows() -> [WindowRecord] {
        let frontmostID = frontmostWindow()?.id
        if isAccessibilityTrusted() {
            var records: [WindowRecord] = []
            for app in AppSupport.runningUserApplications() {
                for window in axWindows(for: app) {
                    if axBool(window, kAXMinimizedAttribute) == true {
                        continue
                    }
                    guard let position = axPoint(window, kAXPositionAttribute),
                          let size = axSize(window, kAXSizeAttribute),
                          size.width > 40,
                          size.height > 40 else {
                        continue
                    }
                    let title = axString(window, kAXTitleAttribute) ?? ""
                    let bounds = CGRect(origin: position, size: size)
                    let id = matchWindowID(pid: app.processIdentifier, title: title, bounds: bounds)
                    records.append(
                        WindowRecord(
                            id: id,
                            pid: app.processIdentifier,
                            appName: app.localizedName ?? "Unknown",
                            title: title,
                            bounds: bounds,
                            layer: 0,
                            onScreen: true,
                            isFrontmost: id == frontmostID
                        )
                    )
                }
            }
            if !records.isEmpty {
                return records.sorted { lhs, rhs in
                    if lhs.isFrontmost != rhs.isFrontmost {
                        return lhs.isFrontmost && !rhs.isFrontmost
                    }
                    if lhs.appName != rhs.appName {
                        return lhs.appName.localizedCaseInsensitiveCompare(rhs.appName) == .orderedAscending
                    }
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
            }
        }
        return interactiveWindows().map { record in
            WindowRecord(
                id: record.id,
                pid: record.pid,
                appName: record.appName,
                title: record.title,
                bounds: record.bounds,
                layer: record.layer,
                onScreen: record.onScreen,
                isFrontmost: record.id == frontmostID
            )
        }
    }

    static func window(byID id: Int) -> WindowRecord? {
        listWindows().first(where: { $0.id == id })
    }

    static func activateWindow(id: Int) throws -> [String: Any] {
        guard let target = window(byID: id) else {
            throw CUAError(message: "window not found: \(id)")
        }
        if let app = AppSupport.runningUserApplications().first(where: { $0.processIdentifier == target.pid }) {
            _ = app.activate(options: [.activateIgnoringOtherApps])
            if isAccessibilityTrusted() {
                for window in axWindows(for: app) {
                    let title = axString(window, kAXTitleAttribute) ?? ""
                    let position = axPoint(window, kAXPositionAttribute) ?? .zero
                    let size = axSize(window, kAXSizeAttribute) ?? .zero
                    let bounds = CGRect(origin: position, size: size)
                    let sameTitle = !target.title.isEmpty && title == target.title
                    let sameSize = abs(bounds.width - target.bounds.width) < 12 && abs(bounds.height - target.bounds.height) < 12
                    if sameTitle || sameSize {
                        _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                        _ = AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
                        break
                    }
                }
            }
            usleep(150_000)
        }
        return [
            "ok": true,
            "window": frontmostWindow()?.json as Any,
            "targetId": id,
        ]
    }

    static func minimizeFrontmostWindow() throws -> [String: Any] {
        guard isAccessibilityTrusted() else {
            throw CUAError(message: "Accessibility permission is required for window minimize")
        }
        guard let window = frontmostWindowAXElement() else {
            throw CUAError(message: "no frontmost window is available")
        }
        let result = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        guard result == .success else {
            throw CUAError(message: "failed to minimize the frontmost window")
        }
        return ["ok": true, "window": frontmostWindow()?.json as Any]
    }

    static func maximizeFrontmostWindow() throws -> [String: Any] {
        guard isAccessibilityTrusted() else {
            throw CUAError(message: "Accessibility permission is required for window maximize")
        }
        guard let window = frontmostWindowAXElement() else {
            throw CUAError(message: "no frontmost window is available")
        }
        guard let button = axElement(window, kAXZoomButtonAttribute) else {
            throw CUAError(message: "failed to find the zoom button on the frontmost window")
        }
        let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
        guard result == .success else {
            throw CUAError(message: "failed to maximize the frontmost window")
        }
        return ["ok": true, "window": frontmostWindow()?.json as Any]
    }

    static func closeFrontmostWindow() throws -> [String: Any] {
        guard isAccessibilityTrusted() else {
            throw CUAError(message: "Accessibility permission is required for window close")
        }
        guard let window = frontmostWindowAXElement() else {
            throw CUAError(message: "no frontmost window is available")
        }
        guard let button = axElement(window, kAXCloseButtonAttribute) else {
            throw CUAError(message: "failed to find the close button on the frontmost window")
        }
        let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
        guard result == .success else {
            throw CUAError(message: "failed to close the frontmost window")
        }
        return ["ok": true]
    }
}
