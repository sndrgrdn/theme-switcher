import Foundation

enum Skill {
    static let guide = """
        # Theme Switcher

        Change the Mac's theme with the `theme-switcher` command. A theme sets macOS light or dark mode, the wallpaper, and the colours of SketchyBar, dinky, Rex, Cursor, pi, Claude Code, OpenCode, Herdr, and Ghostty in one step. Apply a theme only when the user asks for a change, because it changes their whole desktop.

        ## Choose a theme

        Run `theme-switcher list --json`. Each entry in `themes` has an `id`, a `name`, a `mode` of `light` or `dark`, and `current`.

        - Match the user's words to a theme's `id` or `name`.
        - For "a light theme" or "a dark theme", choose among the entries with that `mode`.
        - When nothing matches, show the user the closest ids and ask.

        ## Apply it

        1. Run `theme-switcher current --json`. When `current` is already the theme the user wants, tell them so and stop. Setting the current theme again moves it to its next wallpaper, so run `set` on the current theme only when the user asks for another wallpaper.
        2. Run `theme-switcher set <id> --json`. The command returns after every app has the theme.
        3. Read `report.results`. Each entry has a `target` and a `status`:
           - `applied`: the app has the theme.
           - `skipped`: the app isn't installed.
           - `failed`: the app didn't change. Tell the user the `target` and its `message`.

        The command exits with 1 when any app failed, and with 2 on a usage error.

        ## Other commands

        - `theme-switcher picker` opens the picker for the user. It returns at once and doesn't report their choice.
        - `theme-switcher update` fetches the latest themes from Omarchy. It needs the network and can take a while.

        When `theme-switcher` can't reach the app, it starts Theme Switcher in the background. If that fails, the error names the cause.
        """

    private static let stubVersion = "1"
    private static let stub = """
        ---
        name: theme-switcher
        description: Use the theme-switcher CLI to change the Mac's theme, light or dark mode, or wallpaper, and to list the available themes.
        metadata:
          theme-switcher-stub: "\(stubVersion)"
        ---
        <!-- Installed by "theme-switcher skill setup". Remove it with "theme-switcher skill remove". -->

        Run `theme-switcher skill show` and follow the guide it prints. The guide comes from the installed command, so it matches that version.

        """

    private static let destinations: [(agents: String, homes: [String], folder: URL)] = [
        ("Claude Code", [".claude"], Paths.home.appendingPathComponent(".claude/skills/theme-switcher")),
        ("Codex, OpenCode, and pi", [".agents", ".codex", ".config/opencode", ".pi"],
         Paths.home.appendingPathComponent(".agents/skills/theme-switcher")),
    ]

    private static func found(_ homes: [String]) -> Bool {
        homes.contains { FileManager.default.fileExists(atPath: Paths.home.appendingPathComponent($0).path) }
    }

    static func run(_ words: [String]) -> Int32 {
        switch words.first {
        case "show":
            print(guide)
        case "setup":
            for (agents, homes, folder) in destinations {
                guard found(homes) else {
                    print("\(agents): not found")
                    continue
                }
                do {
                    guard state(of: folder) != .foreign else {
                        print("\(agents): skipped \(display(folder)), which holds a skill Theme Switcher didn't install")
                        continue
                    }
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try stub.write(to: folder.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
                    print("\(agents): installed \(display(folder))")
                } catch {
                    print("\(agents): failed, \(error.localizedDescription)")
                    return 1
                }
            }
        case "remove":
            for (agents, _, folder) in destinations where state(of: folder) == .current || state(of: folder) == .outdated {
                do {
                    try FileManager.default.removeItem(at: folder)
                    print("\(agents): removed \(display(folder))")
                } catch {
                    print("\(agents): failed, \(error.localizedDescription)")
                    return 1
                }
            }
        case "status", nil:
            for (agents, homes, folder) in destinations {
                guard found(homes) else {
                    print("\(agents): not found")
                    continue
                }
                print("\(agents): \(state(of: folder).rawValue.padding(toLength: 9, withPad: " ", startingAt: 0)) \(display(folder))")
            }
        default:
            FileHandle.standardError.write(Data("Usage: theme-switcher skill [status | setup | remove | show]\n".utf8))
            return 2
        }
        return 0
    }

    private enum State: String {
        case current, outdated, missing, foreign
    }

    private static func state(of folder: URL) -> State {
        guard let text = try? String(contentsOf: folder.appendingPathComponent("SKILL.md"), encoding: .utf8) else {
            return FileManager.default.fileExists(atPath: folder.path) ? .foreign : .missing
        }
        if text == stub { return .current }
        return text.contains("theme-switcher-stub:") ? .outdated : .foreign
    }

    private static func display(_ folder: URL) -> String {
        "~" + folder.path.dropFirst(Paths.home.path.count)
    }
}
