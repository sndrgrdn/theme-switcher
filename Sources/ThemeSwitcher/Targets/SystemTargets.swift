import AppKit

struct AppearanceTarget: ThemeTarget {
    let name = "macOS appearance"

    func apply(_ applied: AppliedTheme) throws {
        let dark = applied.theme.mode == .dark
        let source = "tell application \"System Events\" to tell appearance preferences to set dark mode to \(dark)"
        var error: NSDictionary?
        DispatchQueue.main.sync { _ = NSAppleScript(source: source)?.executeAndReturnError(&error) }
        guard let error else { return }
        if error[NSAppleScript.errorNumber] as? Int == -1743 {
            throw ShellError(message: "Allow Theme Switcher to control System Events in System Settings › Privacy & Security › Automation")
        }
        throw ShellError(message: error[NSAppleScript.errorMessage] as? String ?? "AppleScript failed")
    }
}

struct WallpaperTarget: ThemeTarget {
    let name = "Wallpaper"

    func apply(_ applied: AppliedTheme) throws {
        guard let background = applied.background else { throw ShellError(message: "\(applied.theme.name) has no backgrounds") }
        try DispatchQueue.main.sync { try Self.show(background) }
    }

    static func followActiveSpace() {
        let state = ThemeState.load()
        guard let id = state.theme, let index = state.backgrounds[id], let theme = ThemeLibrary.theme(id),
              theme.backgrounds.indices.contains(index) else { return }
        try? show(theme.backgrounds[index])
    }

    static func show(_ background: URL) throws {
        for screen in NSScreen.screens where NSWorkspace.shared.desktopImageURL(for: screen) != background {
            try NSWorkspace.shared.setDesktopImageURL(background, for: screen, options: [:])
        }
    }
}
