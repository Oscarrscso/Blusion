// swift-tools-version: 6.0
import PackageDescription

// Foundation plus Apple's own SQLite3 and Compression modules (IMDb ratings dataset); those files compile out elsewhere. Builds for iOS,
// macOS and Linux so `swift test` runs on the host.
let package = Package(
    name: "StremioKit",
    platforms: [.iOS("26.0"), .macOS(.v14)],
    products: [
        .library(name: "StremioKit", targets: ["StremioKit"]),
        // Mock addon launcher, stub transport and sample addons for test targets of this and other packages. Never linked into the app.
        .library(name: "StremioKitTestSupport", targets: ["StremioKitTestSupport"]),
    ],
    targets: [
        .target(name: "StremioKit", path: "Sources"),
        .target(name: "StremioKitTestSupport", dependencies: ["StremioKit"], path: "TestSupport"),
        .testTarget(
            name: "StremioKitTests",
            dependencies: ["StremioKit", "StremioKitTestSupport"],
            path: "Tests",
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
