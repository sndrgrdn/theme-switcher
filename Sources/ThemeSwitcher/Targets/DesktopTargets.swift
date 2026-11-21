import Foundation

struct SketchyBarTarget: ThemeTarget {
    let name = "SketchyBar"
    var isInstalled: Bool { Shell.which("sketchybar") != nil }

    func apply(_ applied: AppliedTheme) throws {
        try Shell.run("sketchybar", ["--reload"])
    }
}

struct DinkyTarget: ThemeTarget {
    let name = "dinky"
    let config = Paths.home.appendingPathComponent(".config/dinky/dinky.toml")
    var isInstalled: Bool { FileManager.default.fileExists(atPath: config.path) }

    func apply(_ applied: AppliedTheme) throws {
        let colors = [
            "active-color": "#\(strip(applied.palette["accent"]))ff",
            "inactive-color": "#\(strip(applied.palette["muted"]))aa",
        ]
        let text = try String(contentsOf: config, encoding: .utf8)
        var section = ""
        var replaced = Set<String>()
        let lines = text.components(separatedBy: "\n").map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                section = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                return line
            }
            guard section == "borders",
                  let key = colors.keys.first(where: { trimmed.range(of: "^\($0)\\s*=", options: .regularExpression) != nil })
            else { return line }
            replaced.insert(key)
            return line.prefix { $0 == " " || $0 == "\t" } + "\(key) = '\(colors[key]!)'"
        }
        guard replaced.count == colors.count else { throw ShellError(message: "dinky.toml [borders] lacks active-color or inactive-color") }

        let updated = lines.joined(separator: "\n")
        if updated != text { try Files.write(updated, to: config) }
    }

    private func strip(_ color: String?) -> String {
        String((color ?? "").drop { $0 == "#" })
    }
}

struct RexTarget: ThemeTarget {
    let name = "Rex"
    var isInstalled: Bool { Shell.which("rex") != nil }

    func apply(_ applied: AppliedTheme) throws {
        let backup = Paths.backups.appendingPathComponent("com.superlogical.rex.plist")
        if !FileManager.default.fileExists(atPath: backup.path) {
            try FileManager.default.createDirectory(at: Paths.backups, withIntermediateDirectories: true)
            try Shell.run("defaults", ["export", "com.superlogical.rex", backup.path])
        }

        let theme = Paths.support.appendingPathComponent("rex/Omarchy \(applied.theme.name)")
        try FileManager.default.createDirectory(at: theme.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: theme)
        try FileManager.default.copyItem(at: applied.file("ghostty.conf"), to: theme)

        try Shell.run("rex", ["do", "client.theme.import", "path=\(theme.path)"])
        try Shell.run("rex", ["do", "client.setting.interface.appearance.scheme", "value=\(applied.theme.mode.rawValue)"])
    }
}

struct HerdrTarget: ThemeTarget {
    let name = "Herdr"
    let home = ProcessInfo.processInfo.environment["HERDR_APP_HOME"].map { URL(fileURLWithPath: $0) }
        ?? Paths.home.appendingPathComponent(".config/herdr-app")
    var isInstalled: Bool { FileManager.default.fileExists(atPath: home.path) }

    func apply(_ applied: AppliedTheme) throws {
        try Files.write(String(contentsOf: applied.file("herdr-app.json"), encoding: .utf8),
                        to: home.appendingPathComponent("themes/omarchy.json"))
        try setTheme("omarchy", in: home.appendingPathComponent("settings.json"))
    }
}

struct GhosttyTarget: ThemeTarget {
    let name = "Ghostty"
    var isInstalled: Bool {
        [URL(fileURLWithPath: "/Applications"), Paths.home.appendingPathComponent("Applications")]
            .contains { FileManager.default.fileExists(atPath: $0.appendingPathComponent("Ghostty.app").path) }
    }

    func apply(_ applied: AppliedTheme) throws {
        let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0) }
        let directories = [xdg, Paths.home.appendingPathComponent(".config")].compactMap { $0?.appendingPathComponent("ghostty") }
            + [Paths.home.appendingPathComponent("Library/Application Support/com.mitchellh.ghostty")]
        let config = directories.flatMap { [$0.appendingPathComponent("config.ghostty"), $0.appendingPathComponent("config")] }
            .first { FileManager.default.fileExists(atPath: $0.path) }
            ?? Paths.home.appendingPathComponent(".config/ghostty/config")

        let line = "theme = \"\(applied.file("ghostty.conf").path)\""
        let text = (try? String(contentsOf: config, encoding: .utf8)) ?? ""
        var lines = text.components(separatedBy: "\n")
        var replaced = false
        for (index, existing) in lines.enumerated()
        where existing.range(of: #"^\s*theme\s*="#, options: .regularExpression) != nil {
            lines[index] = line
            replaced = true
        }
        if !replaced {
            if lines.last == "" { lines.removeLast() }
            lines += [line, ""]
        }

        let updated = lines.joined(separator: "\n")
        if updated != text { try Files.write(updated, to: config) }
        Shell.signal(SIGUSR2, to: "ghostty")
    }
}

struct HunkTarget: ThemeTarget {
    let name = "Hunk"
    var isInstalled: Bool { Shell.which("hunk") != nil }

    func apply(_ applied: AppliedTheme) throws {
        Shell.signal(SIGWINCH, to: "hunk")
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { Shell.signal(SIGWINCH, to: "hunk") }
    }
}
