import AppKit

enum Snapshot {
    /// Writes a PNG to ~/Pictures/Santo Video Player and returns its URL.
    static func save(_ image: CGImage, name: String) throws -> URL {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
        let folder = pictures.appendingPathComponent("Santo Video Player", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter.string(from: Date(), timeZone: .current,
                                                formatOptions: [.withFullDate, .withTime])
        let safeName = name.replacingOccurrences(of: "/", with: "-")
        let url = folder.appendingPathComponent("\(safeName) \(stamp).png")
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url)
        return url
    }
}
