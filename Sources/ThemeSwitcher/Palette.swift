import Foundation

enum Mode: String {
    case light, dark
}

struct Palette {
    let values: [String: String]

    subscript(key: String) -> String? { values[key] }

    var mode: Mode { Mode(rawValue: values["mode"] ?? "") ?? .dark }

    init(values: [String: String]) {
        self.values = values
    }

    init(colorsFile: URL, lightModeFile: Bool) throws {
        let text = try String(contentsOf: colorsFile, encoding: .utf8)
        var colors = Palette.parse(text)
        Palette.resolve(&colors, lightModeFile: lightModeFile)
        self.values = colors
    }

    static func parse(_ text: String) -> [String: String] {
        var colors: [String: String] = [:]
        for line in text.components(separatedBy: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = String(parts[0]).filter { $0 != "\"" && $0 != "'" && $0 != " " }
            guard !key.isEmpty, !key.hasPrefix("#") else { continue }
            var value = parts.count > 1 ? String(parts[1]) : ""

            if let open = value.firstIndex(where: { $0 == "\"" || $0 == "'" }) {
                value = String(value[value.index(after: open)...])
                if let close = value.firstIndex(where: { $0 == "\"" || $0 == "'" }) {
                    value = String(value[..<close])
                }
            } else {
                value = value.trimmingCharacters(in: .whitespaces)
            }

            guard key.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }) else { continue }
            guard value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "#(),._+/% -".contains($0)) }) else { continue }
            colors[key] = value
        }
        return colors
    }

    static func resolve(_ c: inout [String: String], lightModeFile: Bool) {
        func has(_ key: String) -> Bool { !(c[key] ?? "").isEmpty }
        func get(_ key: String) -> String { c[key] ?? "" }
        func firstSet(_ keys: String...) -> String { keys.first(where: has).map(get) ?? "" }
        func alias(_ key: String, _ fallback: String) { if !has(key) { c[key] = get(fallback) } }
        func derive(_ key: String, _ value: @autoclosure () -> String) { if !has(key) { c[key] = value() } }

        let legacyPaletteAlias = [
            "background": "bg", "dark_background": "dark_bg", "darker_background": "darker_bg",
            "lighter_background": "lighter_bg", "foreground": "fg", "dark_foreground": "dark_fg",
            "light_foreground": "light_fg", "bright_foreground": "bright_fg",
        ]
        for (key, short) in legacyPaletteAlias { alias(key, short) }

        derive("background", get("color0"))
        derive("foreground", get("color7"))
        if has("background") { c["color0"] = get("background") }
        if has("foreground") { c["color7"] = get("foreground") }

        let legacyAlias = [
            "red": "color1", "green": "color2", "yellow": "color3", "blue": "color4",
            "magenta": "color5", "cyan": "color6", "bright_red": "color9", "bright_green": "color10",
            "bright_yellow": "color11", "bright_blue": "color12", "bright_magenta": "color13",
            "bright_cyan": "color14",
        ]
        for (key, ansi) in legacyAlias { alias(key, ansi) }
        alias("magenta", "purple")
        alias("bright_magenta", "bright_purple")

        derive("light_foreground", firstSet("color7", "foreground"))
        derive("bright_foreground", firstSet("color15", "foreground"))
        c["cursor"] = get("bright_foreground")
        derive("lighter_background", firstSet("color0", "background"))
        derive("dark_foreground", firstSet("color8", "foreground"))
        derive("muted", firstSet("color8", "dark_foreground"))
        derive("selection", firstSet("selection_background", "color8", "color0", "background"))
        derive("selection_background", get("selection"))
        derive("selection_foreground", get("bright_foreground"))
        derive("orange", get("yellow"))
        derive("brown", mix(get("orange"), "#000000", "50%"))

        derive("dark_background", mix(get("background"), "#000000", "25%"))
        derive("darker_background", mix(get("background"), "#000000", "50%"))
        for key in ["red", "yellow", "green", "cyan", "blue", "magenta"] {
            derive("bright_\(key)", mix(get(key), "#ffffff", "20%"))
        }
        alias("purple", "magenta")
        alias("bright_purple", "bright_magenta")

        let ansiAlias = [
            "color0": "background", "color1": "red", "color2": "green", "color3": "yellow",
            "color4": "blue", "color5": "magenta", "color6": "cyan", "color7": "foreground",
            "color8": "muted", "color9": "bright_red", "color10": "bright_green",
            "color11": "bright_yellow", "color12": "bright_blue", "color13": "bright_magenta",
            "color14": "bright_cyan", "color15": "bright_foreground",
        ]
        for (key, semantic) in ansiAlias { alias(key, semantic) }
        alias("accent", "color4")

        for (key, short) in legacyPaletteAlias where has(key) { c[short] = get(key) }

        if !has("mode") { c["mode"] = get("theme_type") }
        if !has("mode") {
            if lightModeFile {
                c["mode"] = "light"
            } else if let rgb = rgb(get("background")) {
                c["mode"] = rgb.0 + rgb.1 + rgb.2 > 382 ? "light" : "dark"
            } else {
                c["mode"] = "dark"
            }
        }
        c["theme_type"] = get("mode")
    }

    static func isHex(_ value: String) -> Bool {
        value.count == 7 && value.hasPrefix("#") && value.dropFirst().allSatisfy(\.isHexDigit)
    }

    static func rgb(_ hex: String) -> (Int, Int, Int)? {
        guard isHex(hex), let n = Int(hex.dropFirst(), radix: 16) else { return nil }
        return (n >> 16 & 0xff, n >> 8 & 0xff, n & 0xff)
    }

    static func mix(_ start: String, _ end: String, _ amount: String) -> String {
        var fraction: Double
        if amount.hasSuffix("%") {
            fraction = (Double(amount.dropLast()) ?? 0) / 100
        } else {
            fraction = Double(amount) ?? 0
            if fraction > 1 { fraction /= 100 }
        }
        fraction = min(max(fraction, 0), 1)

        let a = channels(start), b = channels(end)
        let mixed = zip(a, b).map { Int((Double($0) * (1 - fraction) + Double($1) * fraction + 0.5).rounded(.towardZero)) }
        return String(format: "#%02x%02x%02x", mixed[0], mixed[1], mixed[2])
    }

    private static func channels(_ color: String) -> [Int] {
        let hex = Array((color.hasPrefix("#") ? String(color.dropFirst()) : color).lowercased())
        func digit(_ i: Int) -> Int {
            guard i < hex.count, let d = Int(String(hex[i]), radix: 16) else { return -1 }
            return d
        }
        return [0, 2, 4].map { digit($0) * 16 + digit($0 + 1) }
    }
}
