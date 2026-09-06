// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Bootsmith",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Bootsmith",
            path: "Sources/Bootsmith",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
