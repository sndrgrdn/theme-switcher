import Foundation

enum ControlRequest: Codable {
    case list, current, picker, update
    case set(theme: String)
    case background(step: Int)
}

struct ThemeSummary: Codable {
    let id: String
    let name: String
    let mode: String
    let current: Bool
}

struct ControlResponse: Codable {
    var error: String?
    var themes: [ThemeSummary]?
    var current: String?
    var background: String?
    var report: ApplyReport?

    static func failure(_ message: String) -> ControlResponse { ControlResponse(error: message) }
}

enum ControlSocket {
    static let path = Paths.support.appendingPathComponent("control.sock").path

    static func listen(_ handle: @escaping (ControlRequest) -> ControlResponse) throws {
        signal(SIGPIPE, SIG_IGN)
        try FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        unlink(path)
        let server = try unixSocket(path) { fd, address, length in bind(fd, address, length) }
        chmod(path, 0o600)
        guard Darwin.listen(server, 8) == 0 else { throw posixError("listen") }

        Thread.detachNewThread {
            while true {
                let client = accept(server, nil, nil)
                guard client >= 0 else { continue }
                DispatchQueue.global(qos: .userInitiated).async {
                    let connection = FileHandle(fileDescriptor: client, closeOnDealloc: true)
                    let response = (try? JSONDecoder().decode(ControlRequest.self, from: connection.readDataToEndOfFile()))
                        .map(handle) ?? .failure("unreadable request")
                    try? connection.write(contentsOf: JSONEncoder().encode(response))
                }
            }
        }
    }

    static func connect() throws -> FileHandle {
        let fd = try unixSocket(path) { fd, address, length in Darwin.connect(fd, address, length) }
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }

    static func send(_ request: ControlRequest, over connection: FileHandle) throws -> ControlResponse {
        try connection.write(contentsOf: JSONEncoder().encode(request))
        shutdown(connection.fileDescriptor, SHUT_WR)
        return try JSONDecoder().decode(ControlResponse.self, from: connection.readDataToEndOfFile())
    }

    private static func unixSocket(_ path: String, _ attach: (Int32, UnsafePointer<sockaddr>, socklen_t) -> Int32) throws -> Int32 {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { throw posixError("socket path too long") }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw posixError("socket") }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { attach(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard result == 0 else {
            close(fd)
            throw posixError(path)
        }
        return fd
    }

    private static func posixError(_ context: String) -> Error {
        ShellError(message: "\(context): \(String(cString: strerror(errno)))")
    }
}
