import AppKit

/// Uploaded project icons: PNG, JPG or SVG, redrawn as a square PNG (256 px) in the data folder's
/// ProjectIcons directory. The workspace only stores the file name.
enum ProjectIconFiles {
    static let allowedExtensions = ["png", "jpg", "jpeg", "svg"]
    private static let pixels: CGFloat = 256
    private static let cache = NSCache<NSString, NSImage>()

    static var directory: URL {
        AppDataLocation.directory.appendingPathComponent("ProjectIcons", isDirectory: true)
    }

    /// Reads the picture at `url`, crops it to a square and saves it. Returns the stored file
    /// name, or nil when the file can't be read as an image.
    static func importImage(from url: URL) -> String? {
        guard allowedExtensions.contains(url.pathExtension.lowercased()),
              let source = NSImage(contentsOf: url), source.size.width > 0, source.size.height > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(pixels), pixelsHigh: Int(pixels),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        let side = min(source.size.width, source.size.height)
        let crop = NSRect(x: (source.size.width - side) / 2, y: (source.size.height - side) / 2, width: side, height: side)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        source.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: crop, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let name = UUID().uuidString + ".png"
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent(name), options: .atomic)
        } catch {
            return nil
        }
        return name
    }

    /// The stored picture, nil when the file is gone.
    static func image(named name: String) -> NSImage? {
        if let cached = cache.object(forKey: name as NSString) { return cached }
        guard let image = NSImage(contentsOf: directory.appendingPathComponent(name)) else { return nil }
        cache.setObject(image, forKey: name as NSString)
        return image
    }

    /// Removes a stored picture nothing uses any more.
    static func remove(_ name: String) {
        cache.removeObject(forKey: name as NSString)
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }
}
