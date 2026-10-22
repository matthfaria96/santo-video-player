import AppKit
import MetalKit

/// `SantoPlayer --render-check <image> <out-dir> [width height]` renders the
/// image through every CRT preset into PNGs, to inspect the shader offline.
enum RenderCheck {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        if let flag = args.firstIndex(of: "--bench"), args.count > flag + 1 {
            bench(input: URL(fileURLWithPath: args[flag + 1]))
            return true
        }
        guard let flag = args.firstIndex(of: "--render-check"), args.count > flag + 2 else { return false }
        let input = URL(fileURLWithPath: args[flag + 1])
        let outDir = URL(fileURLWithPath: args[flag + 2], isDirectory: true)
        let size = args.count > flag + 4
            ? CGSize(width: Double(args[flag + 3]) ?? 1600, height: Double(args[flag + 4]) ?? 1000)
            : nil
        do {
            try render(input: input, outDir: outDir, size: size)
        } catch {
            FileHandle.standardError.write(Data("render-check: \(error.localizedDescription)\n".utf8))
        }
        return true
    }

    /// `SantoPlayer --bench <image>`: GPU ms per frame for every preset and size.
    private static func bench(input: URL) {
        guard let renderer = try? CRTRenderer(),
              let texture = try? MTKTextureLoader(device: renderer.device)
                .newTexture(URL: input, options: [.SRGB: false]) else { return }
        let sizes = [CGSize(width: 1920, height: 1080), CGSize(width: 2880, height: 1620), CGSize(width: 3840, height: 2160)]
        var report = "preset        " + sizes.map { "\(Int($0.width))x\(Int($0.height))".padding(toLength: 12, withPad: " ", startingAt: 0) }.joined() + "\n"
        for preset in CRTPreset.allCases {
            renderer.settings = preset.settings
            let times = sizes.map { String(format: "%6.2f ms   ", renderer.benchmark(source: texture, size: $0)) }
            report += preset.rawValue.padding(toLength: 14, withPad: " ", startingAt: 0) + times.joined() + "\n"
        }
        FileHandle.standardOutput.write(Data(report.utf8))
    }

    private static func render(input: URL, outDir: URL, size: CGSize?) throws {
        let renderer = try CRTRenderer()
        let loader = MTKTextureLoader(device: renderer.device)
        let texture = try loader.newTexture(URL: input, options: [.SRGB: false])
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        for preset in CRTPreset.allCases {
            renderer.settings = preset.settings
            guard let image = renderer.renderImage(source: texture, size: size) else { continue }
            let rep = NSBitmapImageRep(cgImage: image)
            try rep.representation(using: .png, properties: [:])?
                .write(to: outDir.appendingPathComponent("\(preset.rawValue).png"))
        }
    }
}
