// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Carfo",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Carfo", targets: ["Carfo"])],
    targets: [
        .target(name: "CarfoCore"),
        .executableTarget(name: "Carfo", dependencies: ["CarfoCore"], resources: [.copy("Resources/Engine"), .copy("Resources/CarfoIcon.png"), .copy("Resources/CarfoMenuBarIcon.png")]),
        .testTarget(name: "CarfoCoreTests", dependencies: ["CarfoCore"])
    ],
    swiftLanguageModes: [.v5]
)
