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

    static func signal(_ signal: Int32, to name: String, onlyWithTerminal: Bool = false) {
        var pids = [pid_t](repeating: 0, count: Int(proc_listallpids(nil, 0)) + 64)
        let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        for pid in pids.prefix(max(count, 0)) where pid > 0 {
            var buffer = [CChar](repeating: 0, count: 64)
            if proc_name(pid, &buffer, UInt32(buffer.count)) > 0, String(cString: buffer) == name,
               !onlyWithTerminal || hasTerminal(pid) {
                kill(pid, signal)
            }
        }
    }

    private static func hasTerminal(_ pid: pid_t) -> Bool {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size && info.e_tdev != UInt32.max
    }
}
