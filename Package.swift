// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "toolKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "toolKit", targets: ["toolKit"])
    ],
    targets: [
        .executableTarget(
            name: "toolKit",
            path: "Sources/toolKit"
        ),
        .testTarget(
            name: "toolKitTests",
            dependencies: ["toolKit"],
            path: "Tests/toolKitTests"
        )
    ]
)
