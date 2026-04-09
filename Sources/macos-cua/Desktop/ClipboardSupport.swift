import AppKit
import Foundation

enum ClipboardSupport {
    static func getText() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pbpaste")
        let stdout = Pipe()
        process.standardOutput = stdout
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CUAError(message: "pbpaste failed")
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func setText(_ text: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pbcopy")
        let stdin = Pipe()
        process.standardInput = stdin
        try process.run()
        stdin.fileHandleForWriting.write(Data(text.utf8))
        try stdin.fileHandleForWriting.close()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CUAError(message: "pbcopy failed")
        }
    }

    static func copySelection() throws {
        try InputSupport.keypress("cmd+c")
    }

    static func pasteClipboard() throws {
        try InputSupport.keypress("cmd+v")
    }
}
