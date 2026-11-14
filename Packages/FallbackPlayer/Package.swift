// swift-tools-version: 6.0
import PackageDescription

// OPT-IN (ADR-006). Not part of the default app build: `scripts/enable-fallback.sh` adds it to the generated Xcode project.
// AetherPlayer is linked separately by the app, on Mac Catalyst through the slices scripts/aether-catalyst-slices.py makes.
let package = Package(
    name: "FallbackPlayer",
    platforms: [.iOS("26.0")],
    products: [
        .library(name: "FallbackPlayer", targets: ["FallbackPlayer"]),
    ],
    dependencies: [
        .package(path: "../PlayerKit"),
        .package(path: "../StremioKit"),
        // The LGPL build. 1.0.0 includes the Libuavs3d fix with Mac Catalyst support; both apps use the same mpv build.
        .package(url: "https://github.com/mpvkit/MPVKit", exact: "1.0.0"),
    ],
    targets: [
        .target(
            name: "FallbackPlayer",
            dependencies: ["PlayerKit", .product(name: "StremioKit", package: "StremioKit"), .product(name: "MPVKit", package: "MPVKit")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
