// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PTouchKit",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "PTouchKit", targets: ["PTouchKit"]),
    ],
    targets: [
        .target(name: "PTouchKit"),
        .testTarget(
            name: "PTouchKitTests",
            dependencies: ["PTouchKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
