import Foundation

struct CLIEmission {
    let payload: Any
    let human: String?
    let lines: [String]?
}

final class CLIOutput {
    let json: Bool
    private(set) var lastEmission: CLIEmission?

    init(json: Bool) {
        self.json = json
    }

    func emit(_ payload: Any, human: String? = nil, lines: [String]? = nil) throws {
        let normalized = normalizeJSONValue(payload)
        lastEmission = CLIEmission(payload: normalized, human: human, lines: lines)
        if json {
            guard JSONSerialization.isValidJSONObject(normalized) else {
                throw CUAError(message: "payload is not valid JSON")
            }
            let data = try JSONSerialization.data(withJSONObject: normalized, options: [.prettyPrinted, .sortedKeys])
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

func normalizeJSONValue(_ value: Any) -> Any {
    let mirror = Mirror(reflecting: value)
    if mirror.displayStyle == .optional {
        guard let child = mirror.children.first else { return NSNull() }
        return normalizeJSONValue(child.value)
    }

    switch value {
    case let dictionary as [String: Any]:
        return dictionary.mapValues(normalizeJSONValue)
    case let array as [Any]:
        return array.map(normalizeJSONValue)
    case let string as String:
        return string
    case let bool as Bool:
        return bool
    case let int as Int:
        return int
    case let int32 as Int32:
        return Int(int32)
    case let double as Double:
        return double
    case let number as NSNumber:
        return number
    case let date as Date:
        return date.ISO8601Format()
    case let url as URL:
        return url.path
    case is NSNull:
        return NSNull()
    default:
        return String(describing: value)
    }
}
