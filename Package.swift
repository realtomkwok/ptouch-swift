// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PTouchKit",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "PTouchKit", targets: ["PTouchKit"]),
        .executable(name: "ptouchkit-testpage", targets: ["ptouchkit-testpage"]),
    ],
    targets: [
        .target(name: "PTouchKit"),
        // Developer tool for hardware tests. Not part of the library.
        .executableTarget(name: "ptouchkit-testpage", dependencies: ["PTouchKit"]),
        .testTarget(
            name: "PTouchKitTests",
            dependencies: ["PTouchKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
