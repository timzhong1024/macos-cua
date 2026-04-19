import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum WindowSupport {
    static let duplicateTitleHint = "Duplicate window titles detected; use screen-space to bring the target window frontmost first."

    static func isAccessibilityTrusted() -> Bool {
        PermissionSupport.isGranted(.accessibility)
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

    static func cgWindowCandidates(pid: pid_t) -> [WindowRecord] {
        let onScreen = interactiveWindows().filter { $0.pid == pid }
        if !onScreen.isEmpty {
            return onScreen
        }

        let all = interactiveWindows(onScreenOnly: false).filter { $0.pid == pid }
        var deduped: [WindowRecord] = []
        var seenIDs = Set<Int>()
        for record in all {
            if let id = record.id {
                if seenIDs.insert(id).inserted {
                    deduped.append(record)
                }
            } else {
                deduped.append(record)
            }
        }
        return deduped
    }

    static func record(for window: AXUIElement, app: NSRunningApplication, cgFallback: WindowRecord? = nil) -> WindowRecord? {
        guard let position = axPoint(window, kAXPositionAttribute),
              let size = axSize(window, kAXSizeAttribute),
              size.width > 1,
              size.height > 1 else {
            return nil
        }
        let title = axString(window, kAXTitleAttribute) ?? (cgFallback?.title ?? "")
        let bounds = CGRect(origin: position, size: size)
        let id = matchWindowID(pid: app.processIdentifier, title: title, bounds: bounds) ?? cgFallback?.id
        return WindowRecord(
            id: id,
            pid: app.processIdentifier,
            appName: app.localizedName ?? "Unknown",
            title: title,
            bounds: bounds,
            layer: 0,
            onScreen: true,
            isFrontmost: true
        )
    }

    static func frontmostAXWindowElement(for app: NSRunningApplication, cgFallback: WindowRecord?) -> AXUIElement? {
        guard isAccessibilityTrusted() else { return nil }

        let appElement = axAppElement(pid: app.processIdentifier)
        let main = axElement(appElement, kAXMainWindowAttribute)
        let focused = axElement(appElement, kAXFocusedWindowAttribute)
        let candidates = [main, focused].compactMap { $0 } + axWindows(for: app)

        if let fallbackID = cgFallback?.id {
            for window in candidates {
                guard let record = record(for: window, app: app, cgFallback: cgFallback) else {
                    continue
                }
                if record.id == fallbackID {
                    return window
                }
            }
        }

        return main ?? focused ?? candidates.first
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

        guard let axWindow = frontmostAXWindowElement(for: app, cgFallback: cgFallback) else {
            if let record = cgFallback {
                return WindowRecord(id: record.id, pid: record.pid, appName: record.appName, title: record.title, bounds: record.bounds, layer: record.layer, onScreen: record.onScreen, isFrontmost: true)
            }
            return nil
        }
        return record(for: axWindow, app: app, cgFallback: cgFallback)
    }

    static func matchWindowID(pid: pid_t, title: String, bounds: CGRect) -> Int? {
        let candidates = cgWindowCandidates(pid: pid)
        guard !candidates.isEmpty else { return nil }
        if candidates.count == 1 {
            return candidates[0].id
        }

        let exactTitleMatches = candidates.filter { !$0.title.isEmpty && $0.title == title }
        if exactTitleMatches.count == 1 {
            return exactTitleMatches[0].id
        }

        let targetArea = max(1, bounds.width * bounds.height)
        let ranked = candidates
            .filter { $0.id != nil }
            .map { candidate -> (record: WindowRecord, score: Double) in
                var score = 0.0

                if !title.isEmpty && candidate.title == title {
                    score += 1_000
                } else if title.isEmpty && candidate.title.isEmpty {
                    score += 100
                } else if !title.isEmpty && !candidate.title.isEmpty {
                    if candidate.title.localizedCaseInsensitiveContains(title) || title.localizedCaseInsensitiveContains(candidate.title) {
                        score += 250
                    }
                }

                let widthDelta = abs(candidate.bounds.width - bounds.width)
                let heightDelta = abs(candidate.bounds.height - bounds.height)
                score -= min(600, widthDelta + heightDelta)

                let candidateArea = max(1, candidate.bounds.width * candidate.bounds.height)
                let areaRatio = min(candidateArea, targetArea) / max(candidateArea, targetArea)
                score += areaRatio * 200

                if candidate.onScreen {
                    score += 25
                }

                return (candidate, score)
            }
            .sorted {
                if $0.score == $1.score {
                    return ($0.record.id ?? -1) < ($1.record.id ?? -1)
                }
                return $0.score > $1.score
            }

        return ranked.first?.record.id ?? candidates.first?.id
    }

    static func frontmostWindowAXElement() -> AXUIElement? {
        guard let app = AppSupport.frontmostApplication() else { return nil }
        let cgFallback = interactiveWindows().first(where: { $0.pid == app.processIdentifier })
        return frontmostAXWindowElement(for: app, cgFallback: cgFallback)
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

    static func hasDuplicateTitle(_ target: WindowRecord, in windows: [WindowRecord]? = nil) -> Bool {
        let candidates = (windows ?? listWindows()).filter { $0.pid == target.pid && $0.title == target.title }
        return candidates.count > 1
    }

    static func duplicateTitleWindows(in windows: [WindowRecord]) -> [WindowRecord] {
        var counts: [String: Int] = [:]
        for window in windows {
            counts["\(window.pid)|\(window.title)"] = (counts["\(window.pid)|\(window.title)"] ?? 0) + 1
        }
        return windows.filter { (counts["\($0.pid)|\($0.title)"] ?? 0) > 1 }
    }

    static func window(byID id: Int) -> WindowRecord? {
        listWindows().first(where: { $0.id == id })
    }

    static func resolveTargetWindow(id: Int?) throws -> WindowRecord {
        if let id {
            guard let target = window(byID: id) else {
                throw CUAError(message: "window not found: \(id)")
            }
            return target
        }
        guard let frontmost = frontmostWindow() else {
            throw CUAError(message: "no frontmost window is available")
        }
        return frontmost
    }

    static func runningApplication(pid: pid_t) -> NSRunningApplication? {
        AppSupport.runningUserApplications().first(where: { $0.processIdentifier == pid })
    }

    static func windowPayload(for target: WindowRecord) -> [String: Any]? {
        if let id = target.id, let refreshed = window(byID: id) {
            return refreshed.json
        }
        if let app = runningApplication(pid: target.pid),
           let axWindow = axWindowElement(for: target, includeMinimized: true),
           let refreshed = record(for: axWindow, app: app) {
            return refreshed.json
        }
        return nil
    }

    static func axWindowElement(for target: WindowRecord, includeMinimized: Bool = false) -> AXUIElement? {
        guard isAccessibilityTrusted(),
              let app = runningApplication(pid: target.pid) else {
            return nil
        }

        var fallback: AXUIElement?
        for window in axWindows(for: app) {
            if !includeMinimized, axBool(window, kAXMinimizedAttribute) == true {
                continue
            }
            guard let position = axPoint(window, kAXPositionAttribute),
                  let size = axSize(window, kAXSizeAttribute) else {
                continue
            }
            let title = axString(window, kAXTitleAttribute) ?? ""
            let bounds = CGRect(origin: position, size: size)
            let matchedID = matchWindowID(pid: target.pid, title: title, bounds: bounds)
            if let matchedID, matchedID == target.id {
                return window
            }
            if target.id == nil,
               title == target.title,
               abs(bounds.origin.x - target.bounds.origin.x) < 2,
               abs(bounds.origin.y - target.bounds.origin.y) < 2,
               abs(bounds.width - target.bounds.width) < 2,
               abs(bounds.height - target.bounds.height) < 2 {
                return window
            }
            if fallback == nil,
               title == target.title,
               abs(bounds.origin.x - target.bounds.origin.x) < 12,
               abs(bounds.origin.y - target.bounds.origin.y) < 12,
               abs(bounds.width - target.bounds.width) < 12,
               abs(bounds.height - target.bounds.height) < 12 {
                fallback = window
            }
        }
        return fallback
    }

    static func activateWindow(id: Int) throws -> [String: Any] {
        let target = try resolveTargetWindow(id: id)
        guard let app = runningApplication(pid: target.pid) else {
            throw CUAError(message: "window app is no longer running: \(id)")
        }
        let windowsBefore = listWindows()
        let duplicateTitle = hasDuplicateTitle(target, in: windowsBefore)

        let appActivated = AppSupport.activateApplication(app)
        if isAccessibilityTrusted() {
            guard let window = axWindowElement(for: target, includeMinimized: true) else {
                throw CUAError(message: "failed to resolve AX window for \(id)")
            }
            if axBool(window, kAXMinimizedAttribute) == true {
                _ = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            }
            _ = AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
            _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }

        usleep(250_000)
        let frontmost = frontmostWindow()
        let frontmostPID = AppSupport.frontmostApplication()?.processIdentifier
        let targetWindowCount = listWindows().filter { $0.pid == target.pid }.count
        let sameTargetWindow = frontmost?.id == target.id
        let sameTargetApp = frontmostPID == target.pid
        let targetMain = axWindowElement(for: target, includeMinimized: true).flatMap { axBool($0, kAXMainAttribute) } == true
        let ok = appActivated && (sameTargetWindow || targetMain || (sameTargetApp && targetWindowCount <= 1))
        var payload: [String: Any] = [
            "ok": ok,
            "targetId": id,
        ]
        payload["window"] = windowPayload(for: target) as Any
        if frontmost?.id != target.id || frontmost?.pid != target.pid {
            payload["frontmostWindow"] = frontmost?.json as Any
        }
        if duplicateTitle {
            payload["hint"] = duplicateTitleHint
            payload["fallbackSuggested"] = "screen-space"
        }
        return payload
    }

    static func maximizeWindow(id: Int?) throws -> [String: Any] {
        try PermissionSupport.require(.accessibility, for: "window maximize")
        let target = try resolveTargetWindow(id: id)
        guard let axWindow = axWindowElement(for: target, includeMinimized: true) else {
            throw CUAError(message: "failed to resolve AX window\(id.map { " \($0)" } ?? "")")
        }
        if let app = runningApplication(pid: target.pid) {
            _ = AppSupport.activateApplication(app)
            _ = AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
            _ = AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
        }
        guard let button = axElement(axWindow, kAXZoomButtonAttribute) else {
            throw CUAError(message: "failed to find the zoom button on window\(id.map { " \($0)" } ?? "")")
        }
        let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
        guard result == .success else {
            throw CUAError(message: "failed to maximize window\(id.map { " \($0)" } ?? "")")
        }
        usleep(150_000)
        let frontmost = frontmostWindow()
        var payload: [String: Any] = [
            "ok": true,
            "targetId": target.id as Any,
        ]
        payload["window"] = windowPayload(for: target) as Any
        if frontmost?.id != target.id || frontmost?.pid != target.pid {
            payload["frontmostWindow"] = frontmost?.json as Any
        }
        return payload
    }

    static func closeWindow(id: Int?) throws -> [String: Any] {
        try PermissionSupport.require(.accessibility, for: "window close")
        let target = try resolveTargetWindow(id: id)
        guard let axWindow = axWindowElement(for: target, includeMinimized: true) else {
            throw CUAError(message: "failed to resolve AX window\(id.map { " \($0)" } ?? "")")
        }
        if let app = runningApplication(pid: target.pid) {
            _ = AppSupport.activateApplication(app)
            _ = AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
            _ = AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
        }
        guard let button = axElement(axWindow, kAXCloseButtonAttribute) else {
            throw CUAError(message: "failed to find the close button on window\(id.map { " \($0)" } ?? "")")
        }
        let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
        guard result == .success else {
            throw CUAError(message: "failed to close window\(id.map { " \($0)" } ?? "")")
        }
        usleep(350_000)
        return [
            "ok": target.id.flatMap { window(byID: $0) } == nil,
            "targetId": target.id as Any,
        ]
    }
}
