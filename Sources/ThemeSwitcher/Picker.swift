import AppKit
import SwiftUI

final class PickerModel: ObservableObject {
    static let columns = 4

    let themes: [Theme]
    let palette: Palette
    let images: [String: NSImage]
    @Published var query = "" { didSet { if query != oldValue { selection = 0 } } }
    @Published var selection = 0

    init(themes: [Theme], current: String?, images: [String: NSImage]) {
        self.themes = themes
        self.images = images
        palette = themes.first { $0.id == current }?.palette ?? Palette(values: [:])
        selection = themes.firstIndex { $0.id == current } ?? 0
    }

    var filtered: [Theme] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return themes }
        return themes.filter { $0.name.lowercased().contains(needle) || $0.id.contains(needle) }
    }

    func move(by offset: Int) {
        let count = filtered.count
        guard count > 0 else { return }
        selection = min(max(selection + offset, 0), count - 1)
    }

    func color(_ key: String, _ fallback: Color) -> Color {
        guard let (r, g, b) = palette[key].flatMap(Palette.rgb) else { return fallback }
        return Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
}

struct PickerView: View {
    @ObservedObject var model: PickerModel
    let choose: (Theme) -> Void
    @FocusState private var searching: Bool

    var body: some View {
        let accent = model.color("accent", .accentColor)
        let foreground = model.color("foreground", .primary)
        VStack(spacing: 16) {
            TextField("Filter themes", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .foregroundStyle(foreground)
                .focused($searching)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(foreground.opacity(0.08)))
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: PickerModel.columns), spacing: 16) {
                        ForEach(Array(model.filtered.enumerated()), id: \.element.id) { index, theme in
                            VStack(spacing: 6) {
                                Group {
                                    if let image = model.images[theme.id] {
                                        Image(nsImage: image).resizable().aspectRatio(16 / 9, contentMode: .fill)
                                    } else {
                                        foreground.opacity(0.1)
                                    }
                                }
                                .frame(height: 128)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .stroke(index == model.selection ? accent : .clear, lineWidth: 3))
                                Text(theme.name)
                                    .font(.system(size: 13, weight: index == model.selection ? .semibold : .regular))
                                    .foregroundStyle(index == model.selection ? accent : foreground)
                            }
                            .id(theme.id)
                            .contentShape(Rectangle())
                            .onTapGesture { choose(theme) }
                        }
                    }
                    .padding(4)
                }
                .onChange(of: model.selection) { _, selection in
                    guard model.filtered.indices.contains(selection) else { return }
                    withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(model.filtered[selection].id) }
                }
                .onAppear {
                    if model.filtered.indices.contains(model.selection) {
                        proxy.scrollTo(model.filtered[model.selection].id, anchor: .center)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 1080, height: 680)
        .background(RoundedRectangle(cornerRadius: 14).fill(model.color("background", Color(nsColor: .windowBackgroundColor))))
        .onAppear { searching = true }
    }
}

final class PickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class PickerController: NSObject, NSWindowDelegate {
    private var panel: PickerPanel?
    private var monitor: Any?
    private var model: PickerModel?
    private let choose: (Theme) -> Void

    init(choose: @escaping (Theme) -> Void) {
        self.choose = choose
    }

    var isOpen: Bool { panel != nil }

    func open(themes: [Theme], current: String?, images: [String: NSImage]) {
        close()
        let model = PickerModel(themes: themes, current: current, images: images)
        let panel = PickerPanel(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 680),
                                styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: PickerView(model: model) { [weak self] in self?.pick($0) })
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - 540, y: frame.midY - 340))
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event) == true ? nil : event
        }
        self.model = model
        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel = nil
        model = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    private func pick(_ theme: Theme) {
        close()
        choose(theme)
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard let model else { return false }
        switch event.keyCode {
        case 53: close()
        case 36, 76:
            if model.filtered.indices.contains(model.selection) { pick(model.filtered[model.selection]) }
        case 123: model.move(by: -1)
        case 124: model.move(by: 1)
        case 125: model.move(by: PickerModel.columns)
        case 126: model.move(by: -PickerModel.columns)
        default: return false
        }
        return true
    }
}
