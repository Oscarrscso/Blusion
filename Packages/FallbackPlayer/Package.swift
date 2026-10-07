// swift-tools-version: 6.0
import PackageDescription

// OPT-IN (ADR-006). Not part of the default app build: `scripts/enable-fallback.sh` adds it to the generated Xcode project.
// Keeping the third-party binary dependency out of the default build means a version or API mismatch here can never break the main app.
let package = Package(
    name: "FallbackPlayer",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "FallbackPlayer", targets: ["FallbackPlayer"]),
    ],
    dependencies: [
        .package(path: "../PlayerKit"),
        // UNVERIFIED (ADR-006): the LGPL build of MPVKit. Confirm the product name and pin a version you have actually tested.
        .package(url: "https://github.com/mpvkit/MPVKit", from: "0.40.0"),
    ],
    targets: [
        .target(
            name: "FallbackPlayer",
            dependencies: ["PlayerKit", .product(name: "MPVKit", package: "MPVKit")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
