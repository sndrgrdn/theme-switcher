import Foundation

struct TemplateRenderer {
    private var values: [String: String] = [:]
    private let palette: Palette

    init(palette: Palette) {
        self.palette = palette
        for (key, value) in palette.values {
            values["{{ \(key) }}"] = value
            values["{{ \(key)_strip }}"] = value.hasPrefix("#") ? String(value.dropFirst()) : value
            if let (r, g, b) = Palette.rgb(value) {
                values["{{ \(key)_rgb }}"] = "\(r),\(g),\(b)"
            }
        }
    }

    func render(_ template: String) -> String {
        var out = ""
        var rest = Substring(template)
        while let open = rest.range(of: "{{") {
            guard let close = rest[open.upperBound...].range(of: "}}") else { break }
            let token = String(rest[open.lowerBound..<close.upperBound])
            if let value = values[token] ?? mixValue(token) {
                out += rest[..<open.lowerBound] + value
                rest = rest[close.upperBound...]
            } else {
                out += rest[...open.lowerBound]
                rest = rest[rest.index(after: open.lowerBound)...]
            }
        }
        return out + rest
    }

    private static let mixPattern = try! NSRegularExpression(
        pattern: #"^\{\{\s*(mix|mix_strip|mix_rgb)\s+([A-Za-z0-9_]+)\s+([A-Za-z0-9_]+)\s+([0-9]+(?:\.[0-9]+)?%?)\s*\}\}$"#
    )

    private func mixValue(_ token: String) -> String? {
        guard let match = Self.mixPattern.firstMatch(in: token, range: NSRange(token.startIndex..., in: token)) else { return nil }
        let group = { (i: Int) in String(token[Range(match.range(at: i), in: token)!]) }
        guard let start = palette[group(2)], let end = palette[group(3)],
              Palette.isHex(start), Palette.isHex(end) else { return nil }

        let mixed = Palette.mix(start, end, group(4))
        switch group(1) {
        case "mix_strip": return String(mixed.dropFirst())
        case "mix_rgb":
            let (r, g, b) = Palette.rgb(mixed)!
            return "\(r),\(g),\(b)"
        default: return mixed
        }
    }
}
