import AppKit
import Carbon
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private lazy var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let queue = DispatchQueue(label: "theme-switcher.apply")
    private lazy var picker = PickerController { [weak self] in self?.apply($0) }
    private var hotKey: HotKey?
    private var themes: [Theme] = []
    private var status: String?
    private var results: [TargetResult] = []

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
        do { try ControlSocket.listen { [weak self] in self?.respond(to: $0) ?? .failure("Theme Switcher is quitting") } } catch {
            status = "Command line unavailable: \(error.localizedDescription)"
        }
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
        for result in results { if let failure = result.failure { menu.addItem(disabled: "⚠︎ \(result.target): \(failure)") } }
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
        menu.addItem(action: "Update Themes", #selector(chooseUpdateThemes), target: self)
        menu.addItem(.separator())
        let login = menu.addItem(action: "Start at Login", #selector(toggleStartAtLogin), target: self)
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(action: "Quit", #selector(NSApplication.terminate(_:)), target: NSApp)
    }

    @objc private func chooseTheme(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let theme = themes.first(where: { $0.id == id }) else { return }
        apply(theme)
    }

    @objc private func toggleStartAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            status = nil
        } catch {
            status = "Start at Login failed: \(error.localizedDescription)"
        }
    }

    @objc private func openPicker() {
        reload()
        picker.open(themes: themes, current: ThemeState.load().theme)
    }

    private func togglePicker() {
        picker.isOpen ? picker.close() : openPicker()
    }

    @objc private func chooseUpdateThemes() {
        updateThemes()
    }

    private func updateThemes(then completion: ((String?) -> Void)? = nil) {
        status = "Updating themes…"
        queue.async {
            let failure: String?
            do { try ThemeLibrary.sync(); failure = nil } catch { failure = "Update failed: \(error.localizedDescription)" }
            DispatchQueue.main.async {
                self.status = failure
                self.reload()
                completion?(failure)
            }
        }
    }

    private func apply(_ theme: Theme, then completion: ((Result<ApplyReport, Error>) -> Void)? = nil) {
        status = "Applying \(theme.name)…"
        queue.async {
            let result = Result { try ThemeApplier.apply(theme) }
            DispatchQueue.main.async {
                self.status = nil
                switch result {
                case .success(let report): self.results = report.results
                case .failure(let error): self.results = [TargetResult(target: theme.name, outcome: .failed(error.localizedDescription))]
                }
                completion?(result)
            }
        }
    }

    private func respond(to request: ControlRequest) -> ControlResponse {
        switch request {
        case .list:
            let themes = DispatchQueue.main.sync { reload(); return self.themes }
            let current = ThemeState.load().theme
            return ControlResponse(themes: themes.map {
                ThemeSummary(id: $0.id, name: $0.name, mode: $0.mode.rawValue, current: $0.id == current)
            })
        case .current:
            let state = ThemeState.load()
            guard let id = state.theme else { return .failure("no theme applied yet") }
            let backgrounds = ThemeLibrary.theme(id)?.backgrounds ?? []
            let background = state.backgrounds[id].flatMap { backgrounds.indices.contains($0) ? backgrounds[$0] : nil }
            return ControlResponse(current: id, background: background?.lastPathComponent)
        case .picker:
            DispatchQueue.main.async { self.openPicker() }
            return ControlResponse()
        case .update:
            return wait { done in self.updateThemes { done($0.map(ControlResponse.failure) ?? ControlResponse()) } }
        case .set(let name):
            guard let theme = DispatchQueue.main.sync(execute: { self.theme(named: name) }) else {
                return .failure("no theme named \(name)")
            }
            return wait { done in
                self.apply(theme) { result in
                    switch result {
                    case .success(let report): done(ControlResponse(report: report))
                    case .failure(let error): done(.failure(error.localizedDescription))
                    }
                }
            }
        }
    }

    private func theme(named name: String) -> Theme? {
        reload()
        let id = ThemeLibrary.normalize(name, among: themes)
        return themes.first { $0.id == id }
    }

    private func wait(_ start: @escaping (@escaping (ControlResponse) -> Void) -> Void) -> ControlResponse {
        let semaphore = DispatchSemaphore(value: 0)
        var response = ControlResponse()
        DispatchQueue.main.async {
            start { response = $0; semaphore.signal() }
        }
        semaphore.wait()
        return response
    }

    @objc private func handleURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: string) else { return }
        switch url.host {
        case "picker": openPicker()
        case "set":
            if let theme = theme(named: url.lastPathComponent.removingPercentEncoding ?? "") { apply(theme) }
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

    @discardableResult
    func addItem(action title: String, _ selector: Selector, target: AnyObject) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = target
        addItem(item)
        return item
    }
}
