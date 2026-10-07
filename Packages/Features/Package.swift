// swift-tools-version: 6.0
import PackageDescription

// Board, Discover, Search, Detail, StreamPicker, Player, Addons, Settings.
// View models (`@Observable`, no SwiftUI import) build and test everywhere; SwiftUI views are behind `#if canImport(SwiftUI)`.
let package = Package(
    name: "Features",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Features", targets: ["Features"]),
    ],
    dependencies: [
        .package(path: "../StremioKit"),
        .package(path: "../PlayerKit"),
        .package(path: "../Persistence"),
    ],
    targets: [
        .target(name: "Features", dependencies: ["StremioKit", "PlayerKit", "Persistence"]),
        .testTarget(name: "FeaturesTests", dependencies: ["Features"]),
    ],
    swiftLanguageModes: [.v6]
)
