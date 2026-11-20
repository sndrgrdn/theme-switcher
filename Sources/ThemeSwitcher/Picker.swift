import AppKit
import SwiftUI

enum Carousel {
    static let expanded = CGSize(width: 768, height: 475)
    static let slice = CGSize(width: 108, height: 432)
    static let spacing: CGFloat = -30
    static let skew: CGFloat = 28
    static let topMargin: CGFloat = 30
    static let chromeHeight: CGFloat = 104
    static var step: CGFloat { slice.width + spacing }
    static var height: CGFloat { topMargin + expanded.height + chromeHeight }
}

final class PickerModel: ObservableObject {
    let themes: [Theme]
    let palette: Palette
    let images: [String: NSImage]
    @Published var query = ""
    @Published var selectedID: String?
    @Published var shown = false

    init(themes: [Theme], current: String?, images: [String: NSImage]) {
        self.themes = themes
        self.images = images
        palette = themes.first { $0.id == current }?.palette ?? Palette(values: [:])
        selectedID = themes.first { $0.id == current }?.id ?? themes.first?.id
    }

    var matching: [Theme] {
        let needle = query.lowercased()
        guard !needle.isEmpty else { return themes }
        return themes.filter { $0.id.lowercased().contains(needle) || $0.name.lowercased().contains(needle) }
    }

    var selected: Theme? { matching.first { $0.id == selectedID } }

    func move(by direction: Int) {
        let matching = matching
        guard !matching.isEmpty else { return }
        let position = matching.firstIndex { $0.id == selectedID } ?? 0
        selectedID = matching[(position + direction + matching.count) % matching.count].id
    }

    func setQuery(_ next: String) {
        query = next
        guard selected == nil else { return }
        let all = themes.map(\.id)
        let start = selectedID.flatMap { all.firstIndex(of: $0) } ?? 0
        let ids = Set(matching.map(\.id))
        let ordered = all[start...] + all[..<start]
        if let next = ordered.first(where: ids.contains) { selectedID = next }
    }

    func color(_ key: String, _ fallback: Color, opacity: Double = 1) -> Color {
        guard let (r, g, b) = palette[key].flatMap(Palette.rgb) else { return fallback.opacity(opacity) }
        return Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255).opacity(opacity)
    }
}

struct Slant: Shape {
    let skew: CGFloat

    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX + skew, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - skew, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

struct PickerView: View {
    @ObservedObject var model: PickerModel
    let width: CGFloat
    let select: (Theme) -> Void
    let cancel: () -> Void

    private var radius: Int {
        max(1, min(16, Int(((width - Carousel.expanded.width) / (2 * Carousel.step)).rounded(.up)) + 1))
    }

    var body: some View {
        let background = model.color("background", .black)
        let foreground = model.color("foreground", .white)
        let matching = model.matching
        let position = matching.firstIndex { $0.id == model.selectedID } ?? 0
        let visible = matching.indices.filter { abs($0 - position) <= radius }

        ZStack {
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture(perform: cancel)

            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    ForEach(visible, id: \.self) { index in
                        card(matching[index], relative: index - position)
                    }
                }
                .frame(width: width, height: Carousel.expanded.height, alignment: .topLeading)
                .padding(.top, Carousel.topMargin)

                VStack(spacing: 8) {
                    outlined(Text(model.selected?.name ?? (model.query.isEmpty ? "" : "No matches"))
                        .font(.custom("TX-02", size: 24).weight(.semibold)), foreground, background)
                    outlined(Text(model.query).font(.custom("TX-02", size: 14)), foreground.opacity(0.85), background)
                        .opacity(model.query.isEmpty ? 0 : 1)
                }
                .padding(.top, 16)
                .frame(width: Carousel.expanded.width, height: Carousel.chromeHeight, alignment: .top)
            }
            .opacity(model.shown ? 1 : 0)
            .scaleEffect(model.shown ? 1 : 0.96)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: model.selectedID)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: model.query)
        .animation(.easeOut(duration: 0.18), value: model.shown)
    }

    private func card(_ theme: Theme, relative: Int) -> some View {
        let selected = relative == 0
        let size = selected ? Carousel.expanded : Carousel.slice
        let previewX = (width - Carousel.expanded.width) / 2
        let x: CGFloat = selected ? previewX
            : relative < 0 ? previewX + CGFloat(relative) * Carousel.step
            : previewX + Carousel.expanded.width + Carousel.spacing + CGFloat(relative - 1) * Carousel.step
        let y: CGFloat = selected ? 0 : (Carousel.expanded.height - Carousel.slice.height) / 2
        let shape = Slant(skew: Carousel.skew)
        let background = model.color("background", .black)

        return ZStack {
            background
            if let image = model.images[theme.id] {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
            }
            background.opacity(selected ? 0 : 0.42)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .overlay(shape.stroke(selected ? model.color("accent", .accentColor) : model.color("foreground", .white, opacity: 0.28),
                              lineWidth: selected ? 3 : 1))
        .shadow(color: .black.opacity(selected ? 0.45 : 0.2), radius: selected ? 24 : 8, y: selected ? 12 : 4)
        .contentShape(shape)
        .onTapGesture { selected ? select(theme) : (model.selectedID = theme.id) }
        .offset(x: x, y: y)
        .zIndex(selected ? 100 : Double(50 - min(abs(relative), 40)))
    }

    private func outlined(_ text: some View, _ color: Color, _ outline: Color) -> some View {
        text.foregroundStyle(color)
            .lineLimit(1)
            .shadow(color: outline.opacity(0.7), radius: 0, x: 1, y: 1)
            .shadow(color: outline.opacity(0.7), radius: 0, x: -1, y: -1)
            .shadow(color: outline.opacity(0.7), radius: 2)
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
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        let model = PickerModel(themes: themes, current: current, images: images)
        let panel = PickerPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        let width = min(screen.frame.width - 80, Carousel.expanded.width + 13 * Carousel.step + 40)
        panel.contentView = NSHostingView(rootView: PickerView(
            model: model, width: width,
            select: { [weak self] in self?.pick($0) },
            cancel: { [weak self] in self?.close() }
        ).frame(width: screen.frame.width, height: screen.frame.height))
        panel.setFrame(screen.frame, display: false)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event) == true ? nil : event
        }
        self.model = model
        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { model.shown = true }
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
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        switch event.keyCode {
        case 53:
            model.query.isEmpty ? close() : model.setQuery("")
        case 36, 76:
            if let theme = model.selected { pick(theme) }
        case 123: model.move(by: -1)
        case 124: model.move(by: 1)
        case 48: model.move(by: event.modifierFlags.contains(.shift) ? -1 : 1)
        case 51: model.setQuery(String(model.query.dropLast()))
        default:
            guard modifiers.isEmpty, let text = event.characters, text.count == 1,
                  let scalar = text.unicodeScalars.first, scalar.value >= 32, scalar.value != 127
            else { return false }
            model.setQuery(model.query + text)
        }
        return true
    }
}
