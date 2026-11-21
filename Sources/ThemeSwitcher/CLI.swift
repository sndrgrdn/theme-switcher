import Foundation

enum CLI {
    static let usage = """
        Usage: theme-switcher <command> [--json]

        Commands:
          list           List the themes. * marks the current theme.
          current        Print the current theme and its background.
          set <theme>    Apply a theme by id or name, and wait until every app has it.
                         Setting the current theme again moves to its next background.
          background [next | previous]
                         Show the current theme's next or previous background. Defaults to next.
          picker         Open the theme picker.
          update         Fetch the latest themes from Omarchy.
          skill setup    Install the agent skill for Claude Code, Codex, OpenCode, and pi.
                         skill status, skill remove, and skill show manage it.

        --json prints the app's reply as JSON.
        Exit status: 0 on success, 1 when the command or an app failed, 2 on a usage error.
        Theme Switcher starts in the background when it isn't running.
        """

    static func run(_ arguments: [String]) -> Int32? {
        var words = Array(arguments.dropFirst())
        guard let first = words.first, !first.hasPrefix("-psn"), !first.hasPrefix("-NS") else { return nil }
        let json = words.contains("--json")
        words.removeAll { $0 == "--json" }

        let request: ControlRequest
        switch (words.first, words.count) {
        case ("list", 1): request = .list
        case ("current", 1): request = .current
        case ("picker", 1): request = .picker
        case ("update", 1): request = .update
        case ("background", 1): request = .background(step: 1)
        case ("background", 2) where words.last == "next": request = .background(step: 1)
        case ("background", 2) where words.last == "previous": request = .background(step: -1)
        case ("set", 2...): request = .set(theme: words.dropFirst().joined(separator: " "))
        case ("skill", _):
            return Skill.run(Array(words.dropFirst()))
        case ("help", _), ("--help", _), ("-h", _):
            print(usage)
            return 0
        default:
            FileHandle.standardError.write(Data((usage + "\n").utf8))
            return 2
        }

        let response: ControlResponse
        do { response = try ControlSocket.send(request, over: connectStartingApp()) } catch {
            return fail("can't reach Theme Switcher: \(error.localizedDescription)")
        }
        let failed = response.error != nil || response.report?.results.contains { $0.failure != nil } == true

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            print(String(decoding: (try? encoder.encode(response)) ?? Data(), as: UTF8.self))
            return failed ? 1 : 0
        }
        if let error = response.error { return fail(error) }

        for theme in response.themes ?? [] {
            print("\(theme.current ? "*" : " ") \(theme.id.padding(toLength: 22, withPad: " ", startingAt: 0)) \(theme.mode)")
        }
        if let current = response.current {
            print([current, response.background].compactMap { $0 }.joined(separator: "  "))
        }
        if let report = response.report {
            print("Applied \(report.theme)" + (report.background.map { " with \($0)" } ?? ""))
            for result in report.results {
                switch result.outcome {
                case .applied: print("  ok      \(result.target)")
                case .skipped: print("  skipped \(result.target): not installed")
                case .failed(let message): print("  failed  \(result.target): \(message)")
                }
            }
        }
        return failed ? 1 : 0
    }

    private static func connectStartingApp() throws -> FileHandle {
        if let connection = try? ControlSocket.connect() { return connection }

        let launch = Process()
        launch.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        launch.arguments = ["-g", "-b", "garden.sander.theme-switcher"]
        try launch.run()
        launch.waitUntilExit()

        let deadline = Date().addingTimeInterval(10)
        while true {
            do { return try ControlSocket.connect() } catch {
                guard Date() < deadline else { throw error }
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
    }

    private static func fail(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data("theme-switcher: \(message)\n".utf8))
        return 1
    }
}
