// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OCRMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "OCRMac", targets: ["OCRMac"])
    ],
    targets: [
        .executableTarget(
            name: "OCRMac",
            path: "Sources/OCRMac"
        )
    ]
)
