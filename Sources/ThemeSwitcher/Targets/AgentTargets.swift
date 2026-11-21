import Foundation

struct PiTarget: ThemeTarget {
    let name = "pi"
    let agent = Paths.home.appendingPathComponent(".pi/agent")
    var isInstalled: Bool { FileManager.default.fileExists(atPath: agent.path) }

    func apply(_ applied: AppliedTheme) throws {
        try Files.write(String(contentsOf: applied.file("pi.json"), encoding: .utf8),
                        to: agent.appendingPathComponent("themes/omarchy-system.json"))
        try setTheme("omarchy-system", in: agent.appendingPathComponent("settings.json"))
    }
}

struct ClaudeCodeTarget: ThemeTarget {
    let name = "Claude Code"
    let config = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) }
        ?? Paths.home.appendingPathComponent(".claude")
    var isInstalled: Bool { FileManager.default.fileExists(atPath: config.path) }

    func apply(_ applied: AppliedTheme) throws {
        try Files.write(String(contentsOf: applied.file("claude.json"), encoding: .utf8),
                        to: config.appendingPathComponent("themes/omarchy.json"))
        try setTheme("custom:omarchy", in: config.appendingPathComponent("settings.json"))
    }
}

struct OpencodeTarget: ThemeTarget {
    let name = "OpenCode"
    let config = (ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0) }
        ?? Paths.home.appendingPathComponent(".config")).appendingPathComponent("opencode")
    var isInstalled: Bool { FileManager.default.fileExists(atPath: config.path) }

    func apply(_ applied: AppliedTheme) throws {
        try Files.write(String(contentsOf: applied.file("opencode.json"), encoding: .utf8),
                        to: config.appendingPathComponent("themes/omarchy.json"))

        let cli = config.appendingPathComponent("cli.json")
        var settings: [String: Any] = [:]
        if let data = try? Data(contentsOf: cli) {
            guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ShellError(message: "could not parse \(cli.path)")
            }
            settings = parsed
        }
        var theme = settings["theme"] as? [String: Any] ?? [:]
        if theme["name"] as? String != "omarchy" {
            theme["name"] = "omarchy"
            settings["theme"] = theme
            let data = try JSONSerialization.data(withJSONObject: settings,
                                                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try Files.write(String(decoding: data, as: UTF8.self) + "\n", to: cli)
        }

        Shell.signal(SIGUSR2, to: "opencode", onlyWithTerminal: true)
    }
}

func setTheme(_ theme: String, in settings: URL) throws {
    let text = (try? String(contentsOf: settings, encoding: .utf8)) ?? "{\n}\n"
    let updated = Files.setJSONString("theme", theme, in: text)
    let parsed = try? JSONSerialization.jsonObject(with: Data(updated.utf8)) as? [String: Any]
    guard parsed?["theme"] as? String == theme else {
        throw ShellError(message: "could not set theme in \(settings.path)")
    }
    if updated != text { try Files.write(updated, to: settings) }
}
