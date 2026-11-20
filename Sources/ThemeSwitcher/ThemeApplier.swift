import Foundation

struct AppliedTheme {
    let theme: Theme
    let background: URL?

    var palette: Palette { theme.palette }

    func file(_ name: String) -> URL { Paths.current.appendingPathComponent(name) }
}

protocol ThemeTarget {
    var name: String { get }
    func apply(_ applied: AppliedTheme) throws
}

struct TargetFailure {
    let target: String
    let message: String
}

struct ThemeState: Codable {
    var theme: String?
    var backgrounds: [String: Int] = [:]

    static func load() -> ThemeState {
        (try? JSONDecoder().decode(ThemeState.self, from: Data(contentsOf: Paths.state))) ?? ThemeState()
    }

    func save() throws {
        try FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: Paths.state, options: .atomic)
    }
}

enum ThemeApplier {
    static let targets: [ThemeTarget] = [
        AppearanceTarget(),
        WallpaperTarget(),
        SketchyBarTarget(),
        DinkyTarget(),
        RexTarget(),
        CursorTarget(),
        PiTarget(),
        ClaudeCodeTarget(),
    ]

    static func apply(_ theme: Theme) throws -> [TargetFailure] {
        var state = ThemeState.load()
        var background: URL?
        if !theme.backgrounds.isEmpty {
            let remembered = state.backgrounds[theme.id]
            let index = state.theme == theme.id ? ((remembered ?? -1) + 1) % theme.backgrounds.count
                                                : min(remembered ?? 0, theme.backgrounds.count - 1)
            state.backgrounds[theme.id] = index
            background = theme.backgrounds[index]
        }

        try stage(theme)
        state.theme = theme.id
        try state.save()

        let applied = AppliedTheme(theme: theme, background: background)
        var log = ["\(Date()) \(theme.id) background=\(background?.lastPathComponent ?? "none")"]
        var failures: [TargetFailure] = []
        for target in targets {
            do {
                try target.apply(applied)
                log.append("  ok     \(target.name)")
            } catch {
                failures.append(TargetFailure(target: target.name, message: error.localizedDescription))
                log.append("  FAILED \(target.name): \(error.localizedDescription)")
            }
        }
        try? (log.joined(separator: "\n") + "\n").write(to: Paths.log, atomically: true, encoding: .utf8)
        return failures
    }

    private static func stage(_ theme: Theme) throws {
        let fm = FileManager.default
        try? fm.removeItem(at: Paths.next)
        try fm.createDirectory(at: Paths.next, withIntermediateDirectories: true)

        let renderer = TemplateRenderer(palette: theme.palette)
        for template in try fm.contentsOfDirectory(at: Paths.templates, includingPropertiesForKeys: nil)
        where template.pathExtension == "tpl" {
            let name = template.deletingPathExtension().lastPathComponent
            let destination = Paths.next.appendingPathComponent(name)
            if let shipped = theme.file(name) {
                try fm.copyItem(at: shipped, to: destination)
            } else {
                try renderer.render(String(contentsOf: template, encoding: .utf8))
                    .write(to: destination, atomically: false, encoding: .utf8)
            }
        }

        try? fm.removeItem(at: Paths.current)
        try fm.moveItem(at: Paths.next, to: Paths.current)
    }
}

enum Files {
    static func write(_ text: String, to url: URL) throws {
        let target = url.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try backUp(target)
        try text.write(to: target, atomically: true, encoding: .utf8)
    }

    static func backUp(_ url: URL) throws {
        let fm = FileManager.default
        let backup = Paths.backups.appendingPathComponent(url.path.replacingOccurrences(of: "/", with: "%"))
        guard fm.fileExists(atPath: url.path), !fm.fileExists(atPath: backup.path) else { return }
        try fm.createDirectory(at: Paths.backups, withIntermediateDirectories: true)
        try fm.copyItem(at: url, to: backup)
    }

    static func setJSONString(_ key: String, _ value: String, in text: String) -> String {
        let pattern = "(\"\(NSRegularExpression.escapedPattern(for: key))\"\\s*:\\s*\")[^\"]*(\")"
        let regex = try! NSRegularExpression(pattern: pattern)
        if let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            let replacement = regex.replacementString(for: match, in: text, offset: 0,
                                                      template: "$1\(NSRegularExpression.escapedTemplate(for: value))$2")
            return (text as NSString).replacingCharacters(in: match.range, with: replacement)
        }

        guard let brace = text.firstIndex(of: "{") else { return "{\n  \"\(key)\": \"\(value)\"\n}\n" }
        let rest = text[text.index(after: brace)...]
        if rest.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("}") {
            return String(text[...brace]) + "\n  \"\(key)\": \"\(value)\"\n" + rest.drop(while: \.isWhitespace)
        }
        let indent = rest.split(separator: "\n", omittingEmptySubsequences: false).dropFirst().first?
            .prefix { $0 == " " || $0 == "\t" } ?? "  "
        return String(text[...brace]) + "\n\(indent)\"\(key)\": \"\(value)\"," + rest
    }
}
