import Foundation

struct ShellError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum Shell {
    static let searchPath = [
        "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
        Paths.home.appendingPathComponent(".local/bin").path,
        Paths.home.appendingPathComponent("Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS").path,
    ]

    static func which(_ command: String) -> String? {
        searchPath.map { "\($0)/\(command)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    @discardableResult
    static func run(_ command: String, _ arguments: [String]) throws -> String {
        guard let executable = which(command) else { throw ShellError(message: "\(command) not found") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = searchPath.joined(separator: ":")
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            throw ShellError(message: "\(command) \(arguments.first ?? "") exited \(process.terminationStatus): \(text)")
        }
        return text
    }
}
