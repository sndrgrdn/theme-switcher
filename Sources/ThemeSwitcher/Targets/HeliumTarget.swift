import AppKit

struct HeliumTarget: ThemeTarget {
    let name = "Helium"
    var isInstalled: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: HeliumPolicy.bundleID) != nil }

    func apply(_ applied: AppliedTheme) throws {
        switch HeliumPolicy.state {
        case .current: break
        case .outdated: throw ShellError(message: "Run theme-switcher helium setup again to update the Helium helper")
        case .missing: throw ShellError(message: "Run theme-switcher helium setup to let Theme Switcher colour Helium")
        }
        try Shell.run("sudo", ["-n", HeliumPolicy.helper, color(applied.theme)])
        HeliumPolicy.reload()
    }

    private func color(_ theme: Theme) -> String {
        if let file = theme.file("chromium.theme"),
           let channels = try? String(contentsOf: file, encoding: .utf8)
               .split(separator: ",").map({ Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }),
           channels.count == 3, let r = channels[0], let g = channels[1], let b = channels[2] {
            return String(format: "#%02x%02x%02x", r, g, b)
        }
        return theme.palette["background"].flatMap { Palette.isHex($0) ? $0.lowercased() : nil } ?? "#1c2027"
    }
}

enum HeliumPolicy {
    static let bundleID = "net.imput.helium"
    static let helper = "/Library/PrivilegedHelperTools/garden.sander.theme-switcher.helium"
    static let sudoers = "/etc/sudoers.d/theme-switcher-helium"

    private static let script = """
        #!/bin/sh
        set -eu
        PATH=/usr/bin:/bin:/usr/sbin:/sbin
        export PATH
        user=${SUDO_USER:-}
        case $user in ''|*/*|.*) echo "run this through sudo" >&2; exit 64 ;; esac
        id -u "$user" >/dev/null
        directory="/Library/Managed Preferences/$user"
        plist="$directory/\(bundleID).plist"
        [ $# -eq 1 ] || { echo "usage: $0 '#rrggbb' | --remove" >&2; exit 64; }
        case $1 in
          --remove) rm -f "$plist" ;;
          \\#[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])
            mkdir -p "$directory"
            tmp=$(mktemp)
            plutil -create xml1 "$tmp"
            plutil -insert BrowserThemeColor -string "$1" "$tmp"
            install -m 644 -o root -g wheel "$tmp" "$plist"
            rm -f "$tmp"
            ;;
          *) echo "usage: $0 '#rrggbb' | --remove" >&2; exit 64 ;;
        esac

        """

    enum State: String {
        case current = "set up", outdated, missing = "not set up"
    }

    static var state: State {
        guard FileManager.default.fileExists(atPath: sudoers),
              let installed = try? String(contentsOfFile: helper, encoding: .utf8) else { return .missing }
        return installed == script ? .current : .outdated
    }

    static func reload() {
        typealias Changed = @convention(c) (CFArray) -> Void
        if let symbol = dlsym(dlopen(nil, RTLD_NOW), "_CFPreferencesManagementStatusChangedForDomains") {
            unsafeBitCast(symbol, to: Changed.self)([bundleID] as CFArray)
        }
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            guard let executable = app.executableURL else { continue }
            try? Shell.run(executable.path, ["--refresh-platform-policy", "--no-startup-window"])
        }
    }

    static func run(_ words: [String]) -> Int32 {
        switch words.first {
        case "setup":
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: folder) }
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try script.write(to: folder.appendingPathComponent("helper"), atomically: true, encoding: .utf8)
                try "\(NSUserName()) ALL=(root) NOPASSWD: \(helper)\n"
                    .write(to: folder.appendingPathComponent("sudoers"), atomically: true, encoding: .utf8)
            } catch {
                return fail(error.localizedDescription)
            }
            print("Theme Switcher needs your password once to install the Helium helper.")
            let install = """
                set -e
                visudo -cqf "$2"
                install -d -m 755 -o root -g wheel /Library/PrivilegedHelperTools
                install -m 755 -o root -g wheel "$1" '\(helper)'
                install -m 440 -o root -g wheel "$2" '\(sudoers)'
                """
            guard sudo(install, folder.appendingPathComponent("helper").path, folder.appendingPathComponent("sudoers").path)
            else { return fail("setup failed") }
            print("Helium: set up. The next theme you pick colours Helium.")
        case "remove":
            guard FileManager.default.fileExists(atPath: helper) || FileManager.default.fileExists(atPath: sudoers) else {
                print("Helium: not set up")
                return 0
            }
            let remove = """
                [ -x '\(helper)' ] && '\(helper)' --remove
                rm -f '\(helper)' '\(sudoers)'
                """
            guard sudo(remove) else { return fail("remove failed") }
            reload()
            print("Helium: removed the helper and Helium's theme colour")
        case "status", nil:
            print("Helium: \(state.rawValue)")
        default:
            FileHandle.standardError.write(Data("Usage: theme-switcher helium [status | setup | remove]\n".utf8))
            return 2
        }
        return 0
    }

    private static func sudo(_ script: String, _ arguments: String...) -> Bool {
        let argv = (["/usr/bin/sudo", "/bin/sh", "-c", script, "sh"] + arguments).map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var pid: pid_t = 0
        guard posix_spawn(&pid, argv[0], nil, nil, argv, environ) == 0 else { return false }
        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
        return status == 0
    }

    private static func fail(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data("theme-switcher: \(message)\n".utf8))
        return 1
    }
}
