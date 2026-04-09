import Foundation

struct CLIOutput {
    let json: Bool

    func emit(_ payload: Any, human: String? = nil, lines: [String]? = nil) throws {
        if json {
            guard JSONSerialization.isValidJSONObject(payload) else {
                throw CUAError(message: "payload is not valid JSON")
            }
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
            return
        }
        if let lines, !lines.isEmpty {
            print(lines.joined(separator: "\n"))
            return
        }
        if let human {
            print(human)
        }
    }
}
