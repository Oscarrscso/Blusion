// swift-tools-version: 6.0
import PackageDescription

// Foundation-only. Builds for iOS, macOS and Linux so `swift test` runs on the host (PLAN §1).
let package = Package(
    name: "StremioKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "StremioKit", targets: ["StremioKit"]),
    ],
    targets: [
        .target(name: "StremioKit"),
        .testTarget(
            name: "StremioKitTests",
            dependencies: ["StremioKit"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
