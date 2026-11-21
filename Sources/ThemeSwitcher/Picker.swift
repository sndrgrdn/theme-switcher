import AppKit
import SwiftUI

enum Carousel {
    static let expanded = CGSize(width: 768, height: 475)
    static let slice = CGSize(width: 84, height: 440)
    static let gap: CGFloat = 10
    static let topMargin: CGFloat = 30
    static let chromeHeight: CGFloat = 104
    static var step: CGFloat { slice.width + gap }

    static func radius(width: CGFloat) -> Int {
        max(1, min(16, Int(((width - expanded.width) / (2 * step)).rounded(.up)) + 1))
    }

    static func frame(relative: Int, previewX: CGFloat, radius: Int) -> CGRect {
        if relative == 0 { return CGRect(x: previewX, y: 0, width: expanded.width, height: expanded.height) }
        let distance = CGFloat(abs(relative))
        let height = slice.height * sqrt(max(0.05, 1 - pow(distance / (CGFloat(radius) + 0.6), 2)))
        let x = relative < 0 ? previewX - distance * step
            : previewX + expanded.width + gap + (distance - 1) * step
        return CGRect(x: x, y: (expanded.height - height) / 2, width: slice.width, height: height)
    }

    static func cornerRadius(for rect: CGRect) -> CGFloat {
        min(18, max(8, min(rect.width, rect.height) * 0.12))
    }

    static var motion: Animation? {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .smooth(duration: 0.35)
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

    var radius: Int { Carousel.radius(width: width) }

    func frame(_ relative: Int) -> CGRect {
        Carousel.frame(relative: relative, previewX: previewX, radius: radius)
    }

    var visible: [(relative: Int, theme: Theme)] {
        let matching = matching
        guard !matching.isEmpty else { return [] }
        let position = matching.firstIndex { $0.id == selectedID } ?? 0
        if matching.count >= 2 * radius + 2 {
            return (-radius...radius).map { ($0, matching[(position + $0 + matching.count) % matching.count]) }
        }
        return matching.indices.filter { abs($0 - position) <= radius }.map { ($0 - position, matching[$0]) }
    }

    func hit(_ point: CGPoint) -> Theme? {
        let local = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
        return visible
            .filter { abs($0.relative) < radius }
            .sorted { abs($0.relative) < abs($1.relative) }
            .first { frame($0.relative).contains(local) }?
            .theme
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
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.2)) { self?.images[theme.id] = image }
                }
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
        let offset = abs(index - (themes.firstIndex { $0.id == selectedID } ?? 0))
        return min(offset, themes.count - offset)
    }
}

struct PickerView: View {
    @ObservedObject var model: PickerModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.001)

            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    ForEach(model.visible, id: \.theme.id) { item in
                        Card(theme: item.theme, relative: item.relative, model: model)
                    }
                }
                .frame(width: model.width, height: Carousel.expanded.height, alignment: .topLeading)
                .padding(.top, Carousel.topMargin)

                caption
                    .padding(.top, 26)
                    .frame(width: Carousel.expanded.width, height: Carousel.chromeHeight, alignment: .top)
            }
        }
    }

    private var caption: some View {
        HStack(spacing: 12) {
            if let theme = model.selected {
                Text(theme.name)
                    .font(.custom("TX-02", size: 17).weight(.semibold))
                    .foregroundStyle(.white)
                HStack(spacing: 5) {
                    ForEach(["red", "yellow", "green", "cyan", "blue", "magenta"], id: \.self) { key in
                        Circle()
                            .fill(theme.color(key))
                            .frame(width: 9, height: 9)
                            .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
                    }
                }
            } else {
                Text("No matches")
                    .font(.custom("TX-02", size: 17).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            if !model.query.isEmpty {
                Rectangle().fill(.white.opacity(0.2)).frame(width: 1, height: 16)
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                    Text(model.query)
                }
                .font(.custom("TX-02", size: 14))
                .foregroundStyle(.white.opacity(0.75))
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 18)
        .frame(height: 40)
        .background(Blur(radius: 20))
        .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
        .transaction { $0.animation = nil }
    }
}

struct Blur: NSViewRepresentable {
    let radius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .vibrantDark)
        view.maskImage = NSImage(size: NSSize(width: radius * 2 + 1, height: radius * 2 + 1), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        view.maskImage?.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        view.maskImage?.resizingMode = .stretch
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

extension Theme {
    func color(_ key: String) -> Color {
        guard let (r, g, b) = palette[key].flatMap(Palette.rgb) else { return .gray }
        return Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
}

struct Card: View {
    let theme: Theme
    let relative: Int
    @ObservedObject var model: PickerModel

    var body: some View {
        let selected = relative == 0
        let frame = model.frame(relative)
        let corner = Carousel.cornerRadius(for: frame)
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        let image = model.images[theme.id]
        let hovering = model.hoveredID == theme.id
        let pressed = model.pressedID == theme.id
        let dim = selected ? 0 : hovering ? 0.2 : 0.42

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
            model.color("background", .black).opacity(dim)
        }
        .frame(width: frame.width, height: frame.height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(selected ? theme.color("accent") : .white.opacity(0.12), lineWidth: selected ? 2.5 : 1))
        .shadow(color: .black.opacity(selected ? 0.45 : 0), radius: selected ? 30 : 0, y: selected ? 18 : 0)
        .scaleEffect(pressed ? 0.97 : 1)
        .opacity(abs(relative) >= model.radius ? 0 : 1)
        .offset(x: frame.minX, y: frame.minY)
        .zIndex(selected ? 100 : Double(50 - min(abs(relative), 40)))
        .transition(.opacity)
        .allowsHitTesting(false)
    }

    private var swatches: some View {
        HStack(spacing: 0) {
            ForEach(["background", "red", "yellow", "green", "cyan", "blue", "magenta", "foreground"], id: \.self) { key in
                Rectangle().fill(theme.color(key))
            }
        }
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
            withAnimation(.easeOut(duration: 0.15)) {
                if model.hoveredID != theme?.id { model.hoveredID = theme?.id }
                if model.pressedID != nil, model.pressedID != theme?.id { model.pressedID = nil }
            }
        case .leftMouseDown:
            withAnimation(.easeOut(duration: 0.12)) { model.pressedID = theme?.id }
        case .leftMouseUp:
            let pressed = model.pressedID
            withAnimation(.easeOut(duration: 0.16)) { model.pressedID = nil }
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
