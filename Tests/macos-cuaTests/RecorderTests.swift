import XCTest
@testable import macos_cua

final class RecorderTests: XCTestCase {
    private var originalEnvironment: RecorderEnvironment!
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        originalEnvironment = Recorder.environment
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        var environment = RecorderEnvironment()
        environment.now = { Date(timeIntervalSince1970: 1_710_000_000) }
        environment.executablePath = { "/tmp/macos-cua" }
        environment.currentDirectoryPath = { "/tmp/workdir" }
        environment.baseDirectory = { self.tempDirectory }
        environment.stateSnapshot = {
            [
                "pointer": ["x": 10, "y": 20],
                "frontmostApp": ["name": "Notes"],
            ]
        }
        environment.captureScreenshot = { _, path in
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("png".utf8).write(to: url)
            return ["path": path, "target": "screen"]
        }
        Recorder.environment = environment
    }

    override func tearDownWithError() throws {
        Recorder.environment = originalEnvironment
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try super.tearDownWithError()
    }

    func testEnableCreatesPersistentSession() throws {
        let payload = try Recorder.enable()
        XCTAssertEqual(payload["enabled"] as? Bool, true)
        XCTAssertEqual(payload["alreadyEnabled"] as? Bool, false)

        let config = try Recorder.loadConfig()
        XCTAssertTrue(config.enabled)
        XCTAssertNotNil(config.currentSessionPath)

        let sessionPath = try XCTUnwrap(config.currentSessionPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sessionPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: URL(fileURLWithPath: sessionPath).appendingPathComponent("trace.json").path))
    }

    func testExecuteInvocationPersistsTraceAndReplayScript() throws {
        _ = try Recorder.enable()
        let output = CLIOutput(json: false)

        try Recorder.executeInvocation(arguments: ["wait", "10"], command: "wait", output: output) {
            try output.emit(["ok": true], human: "waited")
        }

        let session = try XCTUnwrap(Recorder.activeSession())
        let lines = try String(contentsOf: session.directory.appendingPathComponent("actions.jsonl"))
            .split(whereSeparator: \.isNewline)
        XCTAssertEqual(lines.count, 1)
        let stepData = Data(lines[0].utf8)
        let step = try XCTUnwrap(JSONSerialization.jsonObject(with: stepData) as? [String: Any])
        XCTAssertEqual(step["command"] as? String, "wait")
        XCTAssertEqual(step["status"] as? String, "ok")

        let artifacts = step["artifacts"] as? [String: Any]
        XCTAssertNotNil(artifacts?["timelineScreenshot"])

        let traceData = try Data(contentsOf: session.directory.appendingPathComponent("trace.json"))
        let trace = try XCTUnwrap(JSONSerialization.jsonObject(with: traceData) as? [String: Any])
        XCTAssertEqual(trace["stepCount"] as? Int, 1)

        let replayScript = try String(contentsOf: session.directory.appendingPathComponent("replay.sh"))
        XCTAssertTrue(replayScript.contains("/tmp/macos-cua wait 10"))
    }

    func testFailedInvocationCapturesFailureSnapshot() throws {
        _ = try Recorder.enable()
        let output = CLIOutput(json: false)

        XCTAssertThrowsError(
            try Recorder.executeInvocation(arguments: ["click", "1", "2"], command: "click", output: output) {
                throw CUAError(message: "boom")
            }
        )

        let session = try XCTUnwrap(Recorder.activeSession())
        let lines = try String(contentsOf: session.directory.appendingPathComponent("actions.jsonl"))
            .split(whereSeparator: \.isNewline)
        let step = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? [String: Any])
        XCTAssertEqual(step["status"] as? String, "failed")
        let artifacts = step["artifacts"] as? [String: Any]
        XCTAssertNotNil(artifacts?["failureScreenshot"])
    }
}
