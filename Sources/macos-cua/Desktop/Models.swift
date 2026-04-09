import Foundation
import CoreGraphics

struct AppRecord {
    let pid: Int32
    let name: String
    let bundleID: String?
    let isActive: Bool
    let isHidden: Bool
    let isTerminated: Bool

    var json: [String: Any] {
        [
            "pid": Int(pid),
            "name": name,
            "bundleId": bundleID as Any,
            "active": isActive,
            "hidden": isHidden,
            "terminated": isTerminated,
        ]
    }

    var line: String {
        var suffix: [String] = []
        if isActive { suffix.append("frontmost") }
        if isHidden { suffix.append("hidden") }
        let flags = suffix.isEmpty ? "" : " [" + suffix.joined(separator: ", ") + "]"
        if let bundleID {
            return "\(name) (pid \(pid), \(bundleID))\(flags)"
        }
        return "\(name) (pid \(pid))\(flags)"
    }
}

struct WindowRecord {
    let id: Int?
    let pid: Int32
    let appName: String
    let title: String
    let bounds: CGRect
    let layer: Int
    let onScreen: Bool
    let isFrontmost: Bool

    var json: [String: Any] {
        [
            "id": id as Any,
            "pid": Int(pid),
            "appName": appName,
            "title": title,
            "bounds": rectJSON(bounds),
            "layer": layer,
            "onScreen": onScreen,
            "frontmost": isFrontmost,
        ]
    }

    var line: String {
        let titleValue = title.isEmpty ? "<untitled>" : title
        let prefix = isFrontmost ? "*" : "-"
        let idValue = id.map(String.init) ?? "n/a"
        return "\(prefix) [\(idValue)] \(appName) | \(titleValue) | \(Int(bounds.origin.x)),\(Int(bounds.origin.y)) \(Int(bounds.size.width))x\(Int(bounds.size.height))"
    }
}

func rectJSON(_ rect: CGRect) -> [String: Any] {
    [
        "x": Int(rect.origin.x.rounded()),
        "y": Int(rect.origin.y.rounded()),
        "width": Int(rect.size.width.rounded()),
        "height": Int(rect.size.height.rounded()),
    ]
}
