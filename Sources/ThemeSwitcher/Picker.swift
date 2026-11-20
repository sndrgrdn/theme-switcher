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

    static func frame(relative: Int, previewX: CGFloat) -> CGRect {
        let size = relative == 0 ? expanded : slice
        let x: CGFloat = relative == 0 ? previewX
            : relative < 0 ? previewX + CGFloat(relative) * step
            : previewX + expanded.width + spacing + CGFloat(relative - 1) * step
        return CGRect(x: x, y: (expanded.height - size.height) / 2, width: size.width, height: size.height)
    }

    static func contains(_ point: CGPoint, in rect: CGRect) -> Bool {
        guard rect.minY...rect.maxY ~= point.y else { return false }
        let shift = skew * (rect.maxY - point.y) / rect.height
        return rect.minX + shift...rect.maxX - skew + shift ~= point.x
    }

    static var motion: Animation? {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .spring(duration: 0.22, bounce: 0)
    }
}

final class PickerModel: ObservableObject {
    let themes: [Theme]
    let palette: Palette
    @Published private(set) var images: [String: NSImage] = [:]
    @Published private(set) var query = ""
    @Published private(set) var selectedID: String?
    @Published var hoveredID: String?
    @Published var pressedID: String?
    private var loading = true

    var width: CGFloat = 0
    var origin: CGPoint = .zero

    var previewX: CGFloat { (width - Carousel.expanded.width) / 2 }

    var radius: Int {
        max(1, min(16, Int(((width - Carousel.expanded.width) / (2 * Carousel.step)).rounded(.up)) + 1))
    }

    func hit(_ point: CGPoint) -> Theme? {
        let local = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
        let matching = matching
        let position = matching.firstIndex { $0.id == selectedID } ?? 0
        return matching.indices
            .filter { abs($0 - position) <= radius }
            .sorted { abs($0 - position) < abs($1 - position) }
            .first { Carousel.contains(local, in: Carousel.frame(relative: $0 - position, previewX: previewX)) }
            .map { matching[$0] }
    }

    init(themes: [Theme], current: String?) {
        self.themes = themes
        palette = themes.first { $0.id == current }?.palette ?? Palette(values: [:])
        selectedID = themes.first { $0.id == current }?.id ?? themes.first?.id
    }

    var matching: [Theme] {
        let needle = query.lowercased()
        guard !needle.isEmpty else { return themes }
        return themes.filter { $0.id.lowercased().contains(needle) || $0.name.lowercased().contains(needle) }
    }

    var selected: Theme? { matching.first { $0.id == selectedID } }

    func loadImages() {
        let order = themes.enumerated().sorted { lhs, rhs in
            distance(lhs.offset) < distance(rhs.offset)
        }.map(\.element)
        if let first = order.first, let image = Previews.image(first) { images[first.id] = image }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            for theme in order.dropFirst() {
                guard self?.loading == true else { return }
                guard let image = Previews.image(theme) else { continue }
                DispatchQueue.main.async { self?.images[theme.id] = image }
            }
        }
    }

    func stopLoading() {
        loading = false
    }

    func move(by direction: Int) {
        let matching = matching
        guard !matching.isEmpty else { return }
        let position = matching.firstIndex { $0.id == selectedID } ?? 0
        select(matching[(position + direction + matching.count) % matching.count])
    }

    func select(_ theme: Theme) {
        guard theme.id != selectedID else { return }
        withAnimation(Carousel.motion) { selectedID = theme.id }
    }

    func setQuery(_ next: String) {
        query = next
        guard selected == nil else { return }
        let all = themes.map(\.id)
        let start = selectedID.flatMap { all.firstIndex(of: $0) } ?? 0
        let ids = Set(matching.map(\.id))
        if let next = (all[start...] + all[..<start]).first(where: ids.contains) { selectedID = next }
    }

    func color(_ key: String, _ fallback: Color = .gray) -> Color {
        guard let (r, g, b) = palette[key].flatMap(Palette.rgb) else { return fallback }
        return Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }

    private func distance(_ index: Int) -> Int {
        abs(index - (themes.firstIndex { $0.id == selectedID } ?? 0))
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

    var body: some View {
        let matching = model.matching
        let position = matching.firstIndex { $0.id == model.selectedID } ?? 0
        let visible = matching.indices.filter { abs($0 - position) <= model.radius }
        let previewX = model.previewX

        ZStack {
            Color.black.opacity(0.001)

            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    if !matching.isEmpty {
                        Slant(skew: Carousel.skew)
                            .fill(model.color("background", .black))
                            .frame(width: Carousel.expanded.width, height: Carousel.expanded.height)
                            .shadow(color: .black.opacity(0.35), radius: 32, y: 18)
                            .offset(x: previewX)
                            .zIndex(99)
                    }
                    ForEach(visible, id: \.self) { index in
                        Card(theme: matching[index], relative: index - position, model: model)
                    }
                }
                .frame(width: model.width, height: Carousel.expanded.height, alignment: .topLeading)
                .padding(.top, Carousel.topMargin)

                VStack(spacing: 8) {
                    label(model.selected?.name ?? (model.query.isEmpty ? "" : "No matches"), size: 24, weight: .semibold)
                    label(model.query, size: 14, weight: .regular)
                        .opacity(model.query.isEmpty ? 0 : 0.85)
                }
                .padding(.top, 16)
                .frame(width: Carousel.expanded.width, height: Carousel.chromeHeight, alignment: .top)
            }
        }
    }

    private func label(_ text: String, size: CGFloat, weight: Font.Weight) -> some View {
        let outline = model.color("background", .black).opacity(0.7)
        return Text(text)
            .font(.custom("TX-02", size: size).weight(weight))
            .foregroundStyle(model.color("foreground", .white))
            .lineLimit(1)
            .truncationMode(.tail)
            .contentTransition(.identity)
            .shadow(color: outline, radius: 0, x: 1, y: 1)
            .shadow(color: outline, radius: 0, x: -1, y: -1)
            .shadow(color: outline, radius: 2)
    }
}

struct Card: View {
    let theme: Theme
    let relative: Int
    @ObservedObject var model: PickerModel

    var body: some View {
        let selected = relative == 0
        let frame = Carousel.frame(relative: relative, previewX: model.previewX)
        let shape = Slant(skew: Carousel.skew)
        let image = model.images[theme.id]
        let hovering = model.hoveredID == theme.id
        let pressed = model.pressedID == theme.id

        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: Carousel.expanded.width, height: Carousel.expanded.height)
                    .transition(.opacity)
            } else {
                swatches
            }
            model.color("background", .black).opacity(selected ? 0 : hovering ? 0.2 : 0.42)
        }
        .frame(width: frame.width, height: frame.height)
        .clipShape(shape)
        .overlay(shape.stroke(selected ? model.color("accent", .accentColor) : model.color("foreground", .white).opacity(0.28),
                              lineWidth: selected ? 3 : 1))
        .scaleEffect(pressed ? 0.97 : 1)
        .animation(.easeOut(duration: 0.16), value: pressed)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(.easeOut(duration: 0.15), value: image != nil)
        .offset(x: frame.minX, y: frame.minY)
        .zIndex(selected ? 100 : Double(50 - min(abs(relative), 40)))
        .allowsHitTesting(false)
    }

    private var swatches: some View {
        HStack(spacing: 0) {
            ForEach(["background", "red", "yellow", "green", "cyan", "blue", "magenta", "foreground"], id: \.self) { key in
                Rectangle().fill(color(key))
            }
        }
    }

    private func color(_ key: String) -> Color {
        guard let (r, g, b) = theme.palette[key].flatMap(Palette.rgb) else { return .gray }
        return Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
}

final class PickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class PickerController: NSObject, NSWindowDelegate {
    private var panel: PickerPanel?
    private var monitors: [Any] = []
    private var model: PickerModel?
    private var scrolled: CGFloat = 0
    private var previous: NSRunningApplication?
    private let choose: (Theme) -> Void

    init(choose: @escaping (Theme) -> Void) {
        self.choose = choose
    }

    var isOpen: Bool { panel != nil }

    func open(themes: [Theme], current: String?) {
        close()
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        let model = PickerModel(themes: themes, current: current)
        model.loadImages()
        let panel = PickerPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.becomesKeyOnlyIfNeeded = false
        panel.delegate = self
        model.width = min(screen.frame.width - 80, Carousel.expanded.width + 13 * Carousel.step + 40)
        let contentHeight = Carousel.topMargin + Carousel.expanded.height + Carousel.chromeHeight
        model.origin = CGPoint(x: (screen.frame.width - model.width) / 2,
                               y: (screen.frame.height - contentHeight) / 2 + Carousel.topMargin)
        panel.acceptsMouseMovedEvents = true
        panel.contentView = NSHostingView(rootView: PickerView(model: model)
            .frame(width: screen.frame.width, height: screen.frame.height))
        panel.setFrame(screen.frame, display: true)
        monitors = [
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleKey(event) == true ? nil : event
            },
            NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handleScroll(event)
                return nil
            },
            NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
                self?.handleMouse(event)
                return nil
            },
        ].compactMap { $0 }
        self.model = model
        self.panel = panel
        previous = NSWorkspace.shared.frontmostApplication.flatMap { $0 == .current ? nil : $0 }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        model?.stopLoading()
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel = nil
        model = nil
        scrolled = 0
        if NSApp.isActive { previous?.activate() }
        previous = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    private func pick(_ theme: Theme) {
        close()
        choose(theme)
    }

    private func handleMouse(_ event: NSEvent) {
        guard let model, let panel, event.window == panel, let view = panel.contentView else { return }
        let location = view.convert(event.locationInWindow, from: nil)
        let point = CGPoint(x: location.x, y: view.isFlipped ? location.y : view.bounds.height - location.y)
        let theme = model.hit(point)
        switch event.type {
        case .mouseMoved, .leftMouseDragged:
            if model.hoveredID != theme?.id { model.hoveredID = theme?.id }
            if model.pressedID != nil, model.pressedID != theme?.id { model.pressedID = nil }
        case .leftMouseDown:
            model.pressedID = theme?.id
        case .leftMouseUp:
            let pressed = model.pressedID
            model.pressedID = nil
            guard let theme else { return close() }
            guard theme.id == pressed else { return }
            theme.id == model.selectedID ? pick(theme) : model.select(theme)
        default:
            break
        }
    }

    private func handleScroll(_ event: NSEvent) {
        guard let model else { return }
        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? -event.scrollingDeltaX : -event.scrollingDeltaY
        guard event.hasPreciseScrollingDeltas else {
            if delta != 0 { model.move(by: delta > 0 ? 1 : -1) }
            return
        }
        if event.phase == .began { scrolled = 0 }
        scrolled += delta
        while abs(scrolled) >= 40 {
            model.move(by: scrolled > 0 ? 1 : -1)
            scrolled -= scrolled > 0 ? 40 : -40
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
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
