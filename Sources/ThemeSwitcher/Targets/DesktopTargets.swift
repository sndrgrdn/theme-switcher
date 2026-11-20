import Foundation

struct SketchyBarTarget: ThemeTarget {
    let name = "SketchyBar"

    func apply(_ applied: AppliedTheme) throws {
        try Shell.run("sketchybar", ["--reload"])
    }
}

struct DinkyTarget: ThemeTarget {
    let name = "dinky"
    let config = Paths.home.appendingPathComponent(".config/dinky/dinky.toml")

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
