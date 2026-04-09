import AppKit
import Foundation

enum AppSupport {
    static func runningUserApplications() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { app in
                app.activationPolicy == .regular &&
                !app.isTerminated &&
                (app.localizedName?.isEmpty == false)
            }
            .sorted { lhs, rhs in
                let lhsName = lhs.localizedName ?? ""
                let rhsName = rhs.localizedName ?? ""
                return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
            }
    }

    static func record(for app: NSRunningApplication) -> AppRecord {
        AppRecord(
            pid: app.processIdentifier,
            name: app.localizedName ?? "Unknown",
            bundleID: app.bundleIdentifier,
            isActive: app.isActive,
            isHidden: app.isHidden,
            isTerminated: app.isTerminated
        )
    }

    static func frontmostApplication() -> NSRunningApplication? {
        NSWorkspace.shared.frontmostApplication
    }

    static func findRunningApplication(matching query: String) -> NSRunningApplication? {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        if normalized.contains("."),
           let exactBundle = runningUserApplications().first(where: { $0.bundleIdentifier?.caseInsensitiveCompare(normalized) == .orderedSame }) {
            return exactBundle
        }

        if let exactName = runningUserApplications().first(where: { ($0.localizedName ?? "").caseInsensitiveCompare(normalized) == .orderedSame }) {
            return exactName
        }

        return runningUserApplications().first(where: { ($0.localizedName ?? "").localizedCaseInsensitiveContains(normalized) })
    }

    @discardableResult
    static func activate(query: String) throws -> [String: Any] {
        if let app = findRunningApplication(matching: query) {
            app.unhide()
            let ok = app.activate(options: [.activateIgnoringOtherApps])
            return [
                "ok": ok,
                "launched": false,
                "app": record(for: app).json,
            ]
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = query.contains(".") ? ["-b", query] : ["-a", query]
        let stderr = Pipe()
        process.standardError = stderr
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw CUAError(message: "failed to launch app: \(error.localizedDescription)")
        }
        if process.terminationStatus != 0 {
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw CUAError(message: message?.isEmpty == false ? message! : "failed to launch app: \(query)")
        }
        usleep(350_000)
        let app = findRunningApplication(matching: query) ?? frontmostApplication()
        return [
            "ok": true,
            "launched": true,
            "app": app.map(record(for:))?.json as Any,
        ]
    }
}
