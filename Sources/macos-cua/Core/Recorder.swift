import Foundation

struct RecordingConfig {
    let enabled: Bool
    let currentSessionID: String?
    let currentSessionPath: String?
    let lastSessionID: String?
    let lastSessionPath: String?
    let updatedAt: String

    static func disabled(now: Date) -> RecordingConfig {
        RecordingConfig(
            enabled: false,
            currentSessionID: nil,
            currentSessionPath: nil,
            lastSessionID: nil,
            lastSessionPath: nil,
            updatedAt: iso8601String(now)
        )
    }

    var json: [String: Any] {
        [
            "enabled": enabled,
            "currentSessionId": currentSessionID as Any,
            "currentSessionPath": currentSessionPath as Any,
            "lastSessionId": lastSessionID as Any,
            "lastSessionPath": lastSessionPath as Any,
            "updatedAt": updatedAt,
        ]
    }
}

struct RecordingSession {
    let id: String
    let directory: URL
}

struct RecorderEnvironment {
    var now: () -> Date = Date.init
    var executablePath: () -> String = { CommandLine.arguments[0] }
    var currentDirectoryPath: () -> String = { FileManager.default.currentDirectoryPath }
    var baseDirectory: () throws -> URL = {
        let fm = FileManager.default
        let root = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("macos-cua", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    var stateSnapshot: () -> [String: Any] = {
        var payload: [String: Any] = [:]
        let pointer = InputSupport.currentPointer()
        payload["pointer"] = [
            "x": Int(pointer.x.rounded()),
            "y": Int(pointer.y.rounded()),
        ]
        payload["frontmostApp"] = AppSupport.frontmostApplication().map(AppSupport.record(for:))?.json as Any
        payload["frontmostWindow"] = WindowSupport.frontmostWindow()?.json as Any
        payload["actionSpace"] = (try? InputSupport.actionSpace()) as Any
        return payload
    }
    var captureScreenshot: (_ target: ScreenshotTarget, _ path: String) throws -> [String: Any] = { target, path in
        try ScreenshotSupport.capture(
            target: target,
            path: path,
            coordinateSpace: .screen,
            coordinateFallback: false,
            reportedBounds: ScreenshotSupport.bounds(for: target)
        )
    }
}

enum Recorder {
    nonisolated(unsafe) static var environment = RecorderEnvironment()

    static func executeInvocation(arguments: [String], command: String, output: CLIOutput, body: () throws -> Void) throws {
        let startedAt = environment.now()
        let sessionBefore = try activeSession()
        let stateBefore = safeStateSnapshot()

        do {
            try body()
            let finishedAt = environment.now()
            let sessionAfter = try activeSession()
            if let session = sessionBefore ?? sessionAfter {
                try persistStep(
                    in: session,
                    arguments: arguments,
                    command: command,
                    output: output.lastEmission,
                    startedAt: startedAt,
                    finishedAt: finishedAt,
                    before: stateBefore,
                    after: safeStateSnapshot(),
                    error: nil
                )
            }
        } catch {
            let finishedAt = environment.now()
            let sessionAfter = try? activeSession()
            if let session = sessionBefore ?? sessionAfter {
                try? persistStep(
                    in: session,
                    arguments: arguments,
                    command: command,
                    output: output.lastEmission,
                    startedAt: startedAt,
                    finishedAt: finishedAt,
                    before: stateBefore,
                    after: safeStateSnapshot(),
                    error: errorMessage(error)
                )
            }
            throw error
        }
    }

    static func enable() throws -> [String: Any] {
        let config = try loadConfig()
        if config.enabled, let session = try activeSession() {
            return [
                "enabled": true,
                "alreadyEnabled": true,
                "sessionId": session.id,
                "sessionPath": session.directory.path,
            ]
        }

        let now = environment.now()
        let session = try createSession(now: now)
        let next = RecordingConfig(
            enabled: true,
            currentSessionID: session.id,
            currentSessionPath: session.directory.path,
            lastSessionID: session.id,
            lastSessionPath: session.directory.path,
            updatedAt: iso8601String(now)
        )
        try saveConfig(next)
        return [
            "enabled": true,
            "alreadyEnabled": false,
            "sessionId": session.id,
            "sessionPath": session.directory.path,
        ]
    }

    static func disable() throws -> [String: Any] {
        let config = try loadConfig()
        guard config.enabled else {
            return [
                "enabled": false,
                "alreadyDisabled": true,
                "lastSessionId": config.lastSessionID as Any,
                "lastSessionPath": config.lastSessionPath as Any,
            ]
        }

        let now = environment.now()
        let next = RecordingConfig(
            enabled: false,
            currentSessionID: nil,
            currentSessionPath: nil,
            lastSessionID: config.currentSessionID ?? config.lastSessionID,
            lastSessionPath: config.currentSessionPath ?? config.lastSessionPath,
            updatedAt: iso8601String(now)
        )
        try saveConfig(next)
        return [
            "enabled": false,
            "alreadyDisabled": false,
            "lastSessionId": next.lastSessionID as Any,
            "lastSessionPath": next.lastSessionPath as Any,
        ]
    }

    static func status() throws -> [String: Any] {
        let config = try loadConfig()
        return config.json
    }

    static func loadConfig() throws -> RecordingConfig {
        let url = try configURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .disabled(now: environment.now())
        }
        let data = try Data(contentsOf: url)
        let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return RecordingConfig(
            enabled: raw["enabled"] as? Bool ?? false,
            currentSessionID: raw["currentSessionId"] as? String,
            currentSessionPath: raw["currentSessionPath"] as? String,
            lastSessionID: raw["lastSessionId"] as? String,
            lastSessionPath: raw["lastSessionPath"] as? String,
            updatedAt: raw["updatedAt"] as? String ?? iso8601String(environment.now())
        )
    }

    static func activeSession() throws -> RecordingSession? {
        let config = try loadConfig()
        guard config.enabled,
              let id = config.currentSessionID,
              let path = config.currentSessionPath else {
            return nil
        }
        return RecordingSession(id: id, directory: URL(fileURLWithPath: path, isDirectory: true))
    }

    private static func createSession(now: Date) throws -> RecordingSession {
        let sessionID = sessionIDString(now: now)
        let directory = try recordsDirectory().appendingPathComponent(sessionID, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("screenshots", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("failures", isDirectory: true), withIntermediateDirectories: true)

        let manifest: [String: Any] = [
            "id": sessionID,
            "startedAt": iso8601String(now),
            "cwd": environment.currentDirectoryPath(),
            "executablePath": environment.executablePath(),
            "actionsLogPath": directory.appendingPathComponent("actions.jsonl").path,
            "replayScriptPath": directory.appendingPathComponent("replay.sh").path,
            "tracePath": directory.appendingPathComponent("trace.json").path,
        ]
        try writeJSON(manifest, to: directory.appendingPathComponent("manifest.json"))
        try writeJSON(
            [
                "id": sessionID,
                "cwd": environment.currentDirectoryPath(),
                "executablePath": environment.executablePath(),
                "startedAt": iso8601String(now),
                "updatedAt": iso8601String(now),
                "actionsLogPath": directory.appendingPathComponent("actions.jsonl").path,
                "replayScriptPath": directory.appendingPathComponent("replay.sh").path,
                "stepCount": 0,
                "lastStep": NSNull(),
            ],
            to: directory.appendingPathComponent("trace.json")
        )
        try writeReplayHeader(to: directory.appendingPathComponent("replay.sh"))
        return RecordingSession(id: sessionID, directory: directory)
    }

    private static func persistStep(
        in session: RecordingSession,
        arguments: [String],
        command: String,
        output: CLIEmission?,
        startedAt: Date,
        finishedAt: Date,
        before: [String: Any],
        after: [String: Any],
        error: String?
    ) throws {
        let traceURL = session.directory.appendingPathComponent("trace.json")
        let manifest = try readJSONObject(at: session.directory.appendingPathComponent("manifest.json"))
        let actionsLogURL = session.directory.appendingPathComponent("actions.jsonl")
        let replayURL = session.directory.appendingPathComponent("replay.sh")
        let index = (try countJSONLines(in: actionsLogURL)) + 1

        var artifacts: [String: Any] = [:]
        if command == "screenshot",
           let screenshotPath = output?.payload as? [String: Any],
           let path = screenshotPath["path"] as? String {
            artifacts["timelineScreenshot"] = [
                "path": path,
                "capturedBy": "command-output",
            ]
        } else if let timeline = captureArtifact(
            in: session.directory.appendingPathComponent("screenshots", isDirectory: true),
            filename: "\(stepPrefix(index, command: command)).png",
            target: .screen
        ) {
            artifacts["timelineScreenshot"] = timeline
        }

        if error != nil {
            if let failure = captureArtifact(
                in: session.directory.appendingPathComponent("failures", isDirectory: true),
                filename: "\(stepPrefix(index, command: command))-failure.png",
                target: .screen
            ) {
                artifacts["failureScreenshot"] = failure
            }
        }

        let replay: [String: Any] = [
            "argv": arguments,
            "executablePath": environment.executablePath(),
            "commandLine": shellCommand(executablePath: environment.executablePath(), arguments: arguments),
        ]
        let lines = output?.lines
        let step: [String: Any] = normalizeJSONValue([
            "index": index,
            "command": command,
            "status": error == nil ? "ok" : "failed",
            "startedAt": iso8601String(startedAt),
            "finishedAt": iso8601String(finishedAt),
            "durationMs": Int(finishedAt.timeIntervalSince(startedAt) * 1000),
            "cwd": environment.currentDirectoryPath(),
            "arguments": arguments,
            "before": before,
            "after": after,
            "output": output?.payload as Any,
            "human": output?.human as Any,
            "lines": lines as Any,
            "error": error as Any,
            "artifacts": artifacts,
            "replay": replay,
        ]) as? [String: Any] ?? [:]

        try appendJSONLine(step, to: actionsLogURL)
        try appendReplayCommand(replay["commandLine"] as? String ?? "", to: replayURL)
        try writeJSON(
            [
                "id": manifest["id"] as Any,
                "cwd": manifest["cwd"] as Any,
                "executablePath": manifest["executablePath"] as Any,
                "startedAt": manifest["startedAt"] as Any,
                "updatedAt": iso8601String(finishedAt),
                "actionsLogPath": manifest["actionsLogPath"] as Any,
                "replayScriptPath": manifest["replayScriptPath"] as Any,
                "stepCount": index,
                "lastStep": [
                    "index": index,
                    "command": command,
                    "status": error == nil ? "ok" : "failed",
                    "finishedAt": iso8601String(finishedAt),
                ],
            ],
            to: traceURL
        )
    }

    private static func captureArtifact(in directory: URL, filename: String, target: ScreenshotTarget) -> [String: Any]? {
        let path = directory.appendingPathComponent(filename).path
        do {
            return try environment.captureScreenshot(target, path)
        } catch {
            return [
                "error": errorMessage(error),
                "path": path,
            ]
        }
    }

    private static func safeStateSnapshot() -> [String: Any] {
        normalizeJSONValue(environment.stateSnapshot()) as? [String: Any] ?? [:]
    }

    private static func configURL() throws -> URL {
        try environment.baseDirectory().appendingPathComponent("recording.json")
    }

    private static func recordsDirectory() throws -> URL {
        let url = try environment.baseDirectory().appendingPathComponent("records", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func saveConfig(_ config: RecordingConfig) throws {
        try writeJSON(config.json, to: try configURL())
    }

    private static func readJSONObject(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    private static func writeJSON(_ payload: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: normalizeJSONValue(payload), options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }

    private static func appendJSONLine(_ payload: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: normalizeJSONValue(payload), options: [.sortedKeys])
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.write(contentsOf: Data("\n".utf8))
        } else {
            var output = Data()
            output.append(data)
            output.append(Data("\n".utf8))
            try output.write(to: url)
        }
    }

    private static func writeReplayHeader(to url: URL) throws {
        let script = "#!/usr/bin/env bash\nset -euo pipefail\n\n"
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private static func appendReplayCommand(_ commandLine: String, to url: URL) throws {
        guard !commandLine.isEmpty else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            try writeReplayHeader(to: url)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((commandLine + "\n").utf8))
    }

    private static func shellCommand(executablePath: String, arguments: [String]) -> String {
        ([executablePath] + arguments).map(shellEscape).joined(separator: " ")
    }

    private static func shellEscape(_ raw: String) -> String {
        guard !raw.isEmpty else { return "''" }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._/:")
        if raw.unicodeScalars.allSatisfy(allowed.contains) {
            return raw
        }
        return "'" + raw.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func stepPrefix(_ index: Int, command: String) -> String {
        String(format: "%04d-%@", index, sanitizedComponent(command))
    }

    private static func sanitizedComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let string = String(scalars)
        return string.isEmpty ? "step" : string
    }

    private static func sessionIDString(now: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: now) + "-" + UUID().uuidString.lowercased()
    }

    private static func countJSONLines(in url: URL) throws -> Int {
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return 0 }
        return String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .count
    }
}

private func iso8601String(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

private func errorMessage(_ error: Error) -> String {
    if let cuaError = error as? CUAError {
        return cuaError.message
    }
    if let localized = error as? LocalizedError, let message = localized.errorDescription {
        return message
    }
    return error.localizedDescription
}
