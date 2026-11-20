import Foundation

struct Theme: Identifiable {
    let id: String
    let directories: [URL]
    let palette: Palette
    let backgrounds: [URL]

    var name: String { Theme.displayName(id) }
    var mode: Mode { palette.mode }
    var preview: URL? { file("preview.png") }

    func file(_ name: String) -> URL? {
        directories.reversed().map { $0.appendingPathComponent(name) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func displayName(_ id: String) -> String {
        id.split(separator: "-", omittingEmptySubsequences: false)
            .map { word in word.first.map { $0.isLowercase ? $0.uppercased() + word.dropFirst() : String(word) } ?? "" }
            .joined(separator: " ")
    }
}

enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let support = home.appendingPathComponent("Library/Application Support/Theme Switcher")
    static let omarchy = support.appendingPathComponent("omarchy")
    static let officialThemes = omarchy.appendingPathComponent("themes")
    static let userThemes = home.appendingPathComponent(".config/theme-switcher/themes")
    static let current = support.appendingPathComponent("current")
    static let next = support.appendingPathComponent("next")
    static let state = support.appendingPathComponent("state.json")
    static let backups = support.appendingPathComponent("backups")
    static let log = support.appendingPathComponent("apply.log")
    static let templates = Bundle.main.resourceURL!.appendingPathComponent("templates")
}

struct ThemeLibrary {
    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "bmp", "webp", "heic"]

    static func load() -> [Theme] {
        let ids = Set(subdirectories(Paths.officialThemes) + subdirectories(Paths.userThemes))
        return ids.sorted().compactMap(theme)
    }

    static func theme(_ id: String) -> Theme? {
        let directories = [Paths.officialThemes, Paths.userThemes]
            .map { $0.appendingPathComponent(id) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        let colors = directories.reversed().map { $0.appendingPathComponent("colors.toml") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
        guard let colors else { return nil }
        let lightMode = directories.contains { FileManager.default.fileExists(atPath: $0.appendingPathComponent("light.mode").path) }
        guard let palette = try? Palette(colorsFile: colors, lightModeFile: lightMode) else { return nil }

        var backgrounds: [String: URL] = [:]
        for directory in directories {
            let folder = directory.appendingPathComponent("backgrounds")
            for file in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            where imageExtensions.contains(file.pathExtension.lowercased()) {
                backgrounds[file.lastPathComponent] = file
            }
        }
        return Theme(id: id, directories: directories, palette: palette,
                     backgrounds: backgrounds.keys.sorted().map { backgrounds[$0]! })
    }

    static func normalize(_ name: String, among themes: [Theme]) -> String {
        let stripped = name.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        if themes.contains(where: { $0.id == stripped }) { return stripped }
        return stripped.lowercased().replacingOccurrences(of: " ", with: "-")
    }

    private static func subdirectories(_ url: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
            .filter { (try? $0.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent)
            .filter { !$0.hasPrefix(".") }
    }

    static func sync() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: Paths.omarchy.appendingPathComponent(".git").path) {
            try Shell.run("git", ["-C", Paths.omarchy.path, "fetch", "--depth", "1", "--filter=blob:none", "origin", "HEAD"])
            try Shell.run("git", ["-C", Paths.omarchy.path, "reset", "--hard", "FETCH_HEAD"])
        } else {
            try fm.createDirectory(at: Paths.support, withIntermediateDirectories: true)
            let staging = Paths.support.appendingPathComponent("omarchy.clone")
            try? fm.removeItem(at: staging)
            try Shell.run("git", ["clone", "--depth", "1", "--filter=blob:none", "--sparse",
                                  "https://github.com/basecamp/omarchy.git", staging.path])
            try Shell.run("git", ["-C", staging.path, "sparse-checkout", "set", "themes"])
            try fm.moveItem(at: staging, to: Paths.omarchy)
        }
    }
}
