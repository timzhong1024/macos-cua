import Foundation

struct CUAError: Error {
    let message: String
}

@discardableResult
func requireValue<T>(_ value: T?, _ message: String) throws -> T {
    guard let value else {
        throw CUAError(message: message)
    }
    return value
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func parseInt(_ raw: String, name: String) throws -> Int {
    guard let value = Int(raw) else {
        throw CUAError(message: "invalid \(name): \(raw)")
    }
    return value
}
