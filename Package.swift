// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PTouchKit",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "PTouchKit", targets: ["PTouchKit"]),
        .library(name: "PTouchKitTransports", targets: ["PTouchKitTransports"]),
        .executable(name: "ptouchkit-testpage", targets: ["ptouchkit-testpage"]),
    ],
    targets: [
        .target(name: "PTouchKit"),
        // Transports: macOS USB (IOUSBHost) and Bluetooth (IOBluetooth), iOS ExternalAccessory.
        .target(
            name: "PTouchKitTransports",
            dependencies: ["PTouchKit"],
            linkerSettings: [
                .linkedFramework("IOUSBHost", .when(platforms: [.macOS])),
                .linkedFramework("IOBluetooth", .when(platforms: [.macOS])),
                .linkedFramework("ExternalAccessory", .when(platforms: [.iOS])),
            ]
        ),
        // Developer tool for hardware tests. Not part of the library.
        .executableTarget(name: "ptouchkit-testpage", dependencies: ["PTouchKit", "PTouchKitTransports"]),
        .testTarget(
            name: "PTouchKitTests",
            dependencies: ["PTouchKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
