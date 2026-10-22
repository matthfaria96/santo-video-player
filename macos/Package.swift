// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SantoPlayer",
    platforms: [.macOS("15.0")],
    dependencies: [
        // libmpv + FFmpeg (all formats, audio/subtitle tracks), universal xcframeworks.
        .package(url: "https://github.com/mpvkit/MPVKit", exact: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "SantoPlayer",
            dependencies: [.product(name: "MPVKit", package: "MPVKit")],
            path: "Sources/SantoPlayer",
            // mpv's macOS render path is OpenGL (the same one IINA uses).
            swiftSettings: [.unsafeFlags(["-Xcc", "-DGL_SILENCE_DEPRECATION"])]
        ),
        // Needs Xcode (DEVELOPER_DIR): the Command Line Tools lack XCTest.
        .testTarget(name: "SantoPlayerTests", dependencies: ["SantoPlayer"], path: "Tests/SantoPlayerTests"),
    ]
)
