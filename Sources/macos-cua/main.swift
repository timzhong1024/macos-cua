import Foundation

do {
    try CLI.run(arguments: Array(CommandLine.arguments.dropFirst()))
} catch let error as CUAError {
    fail(error.message)
} catch {
    fail(error.localizedDescription)
}
