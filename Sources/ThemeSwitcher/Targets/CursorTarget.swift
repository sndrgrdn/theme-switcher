import Foundation

struct CursorTarget: ThemeTarget {
    let name = "Cursor"
    let settings = Paths.home.appendingPathComponent("Library/Application Support/Cursor/User/settings.json")
    let extensions = Paths.home.appendingPathComponent(".cursor/extensions")
    let generatedName = "omarchy-theme"
    let generatedID = "local.omarchy-theme"
    private static var failedInstalls = Set<String>()

    func apply(_ applied: AppliedTheme) throws {
        guard Shell.which("cursor") != nil else { throw ShellError(message: "cursor CLI not found") }

        let colorTheme: String
        if let name = try extensionTheme(applied) {
            colorTheme = name
        } else {
            try installGenerated(applied.file("vscode-theme.json"))
            colorTheme = "Omarchy"
        }

        let preferred = applied.theme.mode == .dark ? "workbench.preferredDarkColorTheme" : "workbench.preferredLightColorTheme"
        let text = try String(contentsOf: settings, encoding: .utf8)
        let updated = [preferred, "workbench.colorTheme"].reduce(text) { Files.setJSONString($1, colorTheme, in: $0) }
        if updated != text { try Files.write(updated, to: settings) }
    }

    private func extensionTheme(_ applied: AppliedTheme) throws -> String? {
        guard let descriptor = applied.theme.file("vscode.json") else { return nil }
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: descriptor)) as? [String: Any] ?? [:]
        guard let name = json["name"] as? String,
              name.range(of: #"^[^\p{Cc}"\\]+$"#, options: .regularExpression) != nil
        else { throw ShellError(message: "vscode.json has no usable theme name") }
        guard let id = json["extension"] as? String,
              id.range(of: "^[a-zA-Z0-9._-]+$", options: .regularExpression) != nil,
              !isInstalled(id)
        else { return name }
        guard !Self.failedInstalls.contains(id) else { return nil }
        do {
            try Shell.run("cursor", ["--install-extension", id])
            return name
        } catch {
            Self.failedInstalls.insert(id)
            Log.append("  note   Cursor: \(id) failed to install, using the generated Omarchy theme. \(error.localizedDescription)")
            return nil
        }
    }

    private func registry() -> [[String: Any]] {
        let data = try? Data(contentsOf: extensions.appendingPathComponent("extensions.json"))
        return data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] } ?? []
    }

    private func obsolete() -> [String: Any] {
        let data = try? Data(contentsOf: extensions.appendingPathComponent(".obsolete"))
        return data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
    }

    private func isInstalled(_ id: String) -> Bool {
        let gone = obsolete()
        return registry().contains { entry in
            guard ((entry["identifier"] as? [String: Any])?["id"] as? String)?.lowercased() == id.lowercased() else { return false }
            let location = entry["location"] as? [String: Any]
            let relative = entry["relativeLocation"] as? String
                ?? ((location?["path"] ?? location?["fsPath"]) as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
                ?? ""
            return !relative.isEmpty && gone[relative] == nil
                && FileManager.default.fileExists(atPath: extensions.appendingPathComponent(relative).path)
        }
    }

    private func installGenerated(_ theme: URL) throws {
        let data = try Data(contentsOf: theme)
        let type = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["type"] as? String
        let version = "1.0.\(data.reduce(UInt32(2166136261)) { ($0 ^ UInt32($1)) &* 16777619 })"
        let directory = extensions.appendingPathComponent(generatedName)
        let fm = FileManager.default

        try fm.createDirectory(at: directory.appendingPathComponent("themes"), withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("themes/omarchy-color-theme.json"))
        let package: [String: Any] = [
            "name": generatedName, "displayName": "Omarchy", "description": "Omarchy color theme",
            "publisher": "local", "version": version, "engines": ["vscode": "^1.70.0"], "categories": ["Themes"],
            "contributes": ["themes": [[
                "label": "Omarchy", "uiTheme": type == "light" ? "vs" : "vs-dark",
                "path": "./themes/omarchy-color-theme.json", "_watch": true,
            ]]],
        ]
        try JSONSerialization.data(withJSONObject: package, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            .write(to: directory.appendingPathComponent("package.json"))

        let obsoleteFile = extensions.appendingPathComponent(".obsolete")
        var gone = obsolete()
        if gone.removeValue(forKey: "\(generatedID)-\(version)") != nil {
            try Files.backUp(obsoleteFile)
            if gone.isEmpty {
                try fm.removeItem(at: obsoleteFile)
            } else {
                try JSONSerialization.data(withJSONObject: gone).write(to: obsoleteFile, options: .atomic)
            }
        }

        let entry: [String: Any] = [
            "identifier": ["id": generatedID],
            "version": version,
            "location": ["$mid": 1, "fsPath": directory.path, "external": directory.absoluteString,
                         "path": directory.path, "scheme": "file"],
            "relativeLocation": generatedName,
        ]
        let entries = registry().filter { ($0["identifier"] as? [String: Any])?["id"] as? String != generatedID } + [entry]
        let registryFile = extensions.appendingPathComponent("extensions.json")
        try Files.backUp(registryFile)
        try JSONSerialization.data(withJSONObject: entries, options: .withoutEscapingSlashes).write(to: registryFile, options: .atomic)
    }
}
