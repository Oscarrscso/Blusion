// swift-tools-version: 6.0
import PackageDescription

// PlaybackEngine protocol, AVEngine (Apple only), subtitle parsers, progress and coordination logic.
// Imports AVFoundation only, never UIKit, so it builds and tests on macOS; pure logic also builds on Linux.
let package = Package(
    name: "PlayerKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PlayerKit", targets: ["PlayerKit"]),
    ],
    dependencies: [
        .package(path: "../StremioKit"),
    ],
    targets: [
        .target(name: "PlayerKit", dependencies: ["StremioKit"]),
        .testTarget(name: "PlayerKitTests", dependencies: ["PlayerKit"]),
    ],
    swiftLanguageModes: [.v6]
)
