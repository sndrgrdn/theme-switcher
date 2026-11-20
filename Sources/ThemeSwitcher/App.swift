import AppKit
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private lazy var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let queue = DispatchQueue(label: "theme-switcher.apply")
    private lazy var picker = PickerController { [weak self] in self?.apply($0) }
    private var hotKey: HotKey?
    private var themes: [Theme] = []
    private var status: String?
    private var failures: [TargetFailure] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem.button?.image = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: "Theme Switcher")
        statusItem.menu = NSMenu()
        statusItem.menu?.delegate = self

        hotKey = HotKey(keyCode: kVK_Space, modifiers: controlKey | optionKey | cmdKey) { [weak self] in
            self?.togglePicker()
        }
        if hotKey == nil { status = "⌃⌥⌘Space is taken by another app" }

        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURL(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass),
                                                     andEventID: AEEventID(kAEGetURL))
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                                          object: nil, queue: .main) { _ in
            WallpaperTarget.followActiveSpace()
        }
        reload()
        if themes.isEmpty { updateThemes() }
    }

    private func reload() {
        themes = ThemeLibrary.load()
        let themes = themes
        DispatchQueue.global(qos: .utility).async { Previews.warm(themes) }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        reload()
        let current = ThemeState.load().theme
        menu.removeAllItems()

        let header = NSMenuItem(title: current.map(Theme.displayName) ?? "No theme", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        if let status { menu.addItem(disabled: status) }
        for failure in failures { menu.addItem(disabled: "⚠︎ \(failure.target): \(failure.message)") }
        menu.addItem(.separator())

        for theme in themes {
            let item = NSMenuItem(title: theme.name, action: #selector(chooseTheme(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = theme.id
            item.state = theme.id == current ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(action: "Open Picker…", #selector(openPicker), target: self)
        menu.addItem(action: "Update Themes", #selector(updateThemes), target: self)
        menu.addItem(action: "Quit", #selector(NSApplication.terminate(_:)), target: NSApp)
    }

    @objc private func chooseTheme(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let theme = themes.first(where: { $0.id == id }) else { return }
        apply(theme)
    }

    @objc private func openPicker() {
        reload()
        picker.open(themes: themes, current: ThemeState.load().theme)
    }

    private func togglePicker() {
        picker.isOpen ? picker.close() : openPicker()
    }

    @objc private func updateThemes() {
        status = "Updating themes…"
        queue.async {
            let result: String?
            do { try ThemeLibrary.sync(); result = nil } catch { result = "Update failed: \(error.localizedDescription)" }
            DispatchQueue.main.async {
                self.status = result
                self.reload()
            }
        }
    }

    private func apply(_ theme: Theme) {
        status = "Applying \(theme.name)…"
        queue.async {
            let failures: [TargetFailure]
            do { failures = try ThemeApplier.apply(theme) } catch {
                failures = [TargetFailure(target: theme.name, message: error.localizedDescription)]
            }
            DispatchQueue.main.async {
                self.status = nil
                self.failures = failures
            }
        }
    }

    @objc private func handleURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: string) else { return }
        switch url.host {
        case "picker": openPicker()
        case "set":
            reload()
            let id = ThemeLibrary.normalize(url.lastPathComponent.removingPercentEncoding ?? "", among: themes)
            if let theme = themes.first(where: { $0.id == id }) { apply(theme) }
        default: break
        }
    }
}

private extension NSMenu {
    func addItem(disabled title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        addItem(item)
    }

    func addItem(action title: String, _ selector: Selector, target: AnyObject) {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = target
        addItem(item)
    }
}
