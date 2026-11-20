import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

enum Previews {
    static let maxPixelSize = 1536
    private static let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Theme Switcher/previews")

    static func source(_ theme: Theme) -> URL? {
        theme.preview ?? theme.backgrounds.first
    }

    static func warm(_ themes: [Theme]) {
        for theme in themes { _ = cachedFile(theme) }
    }

    static func image(_ theme: Theme) -> NSImage? {
        guard let file = cachedFile(theme),
              let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    private static func cachedFile(_ theme: Theme) -> URL? {
        guard let source = source(theme) else { return nil }
        let modified = (try? source.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?
            .timeIntervalSince1970 ?? 0
        let key = SHA256.hash(data: Data("\(source.path)|\(modified)|\(maxPixelSize)".utf8))
            .prefix(8).map { String(format: "%02x", $0) }.joined()
        let file = directory.appendingPathComponent("\(theme.id)-\(key).jpg")
        if FileManager.default.fileExists(atPath: file.path) { return file }

        guard let input = CGImageSourceCreateWithURL(source as CFURL, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(input, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
              ] as CFDictionary)
        else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for stale in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        where stale.deletingPathExtension().lastPathComponent.dropLast(key.count + 1) == theme.id {
            try? FileManager.default.removeItem(at: stale)
        }
        guard let output = CGImageDestinationCreateWithURL(file as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(output, thumbnail, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        return CGImageDestinationFinalize(output) ? file : nil
    }
}
