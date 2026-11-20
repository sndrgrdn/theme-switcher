import Foundation

struct PiTarget: ThemeTarget {
    let name = "pi"
    let agent = Paths.home.appendingPathComponent(".pi/agent")

    func apply(_ applied: AppliedTheme) throws {
        try Files.write(String(contentsOf: applied.file("pi.json"), encoding: .utf8),
                        to: agent.appendingPathComponent("themes/omarchy-system.json"))
        try setTheme("omarchy-system", in: agent.appendingPathComponent("settings.json"))
    }
}

struct ClaudeCodeTarget: ThemeTarget {
    let name = "Claude Code"

    func apply(_ applied: AppliedTheme) throws {
        let config = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) }
            ?? Paths.home.appendingPathComponent(".claude")
        try Files.write(String(contentsOf: applied.file("claude.json"), encoding: .utf8),
                        to: config.appendingPathComponent("themes/omarchy.json"))
        try setTheme("custom:omarchy", in: config.appendingPathComponent("settings.json"))
    }
}

private func setTheme(_ theme: String, in settings: URL) throws {
    let text = (try? String(contentsOf: settings, encoding: .utf8)) ?? "{\n}\n"
    let updated = Files.setJSONString("theme", theme, in: text)
    let parsed = try? JSONSerialization.jsonObject(with: Data(updated.utf8)) as? [String: Any]
    guard parsed?["theme"] as? String == theme else {
        throw ShellError(message: "could not set theme in \(settings.path)")
    }
    if updated != text { try Files.write(updated, to: settings) }
}
