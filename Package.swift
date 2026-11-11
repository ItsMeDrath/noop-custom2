// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WHOOPCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "WHOOPCore", targets: ["WHOOPCore"])],
    targets: [
        .target(name: "WHOOPCore", path: "Core", resources: [.process("Resources")]),
        .testTarget(name: "WHOOPCoreTests", dependencies: ["WHOOPCore"], path: "Tests/WHOOPCoreTests", resources: [.copy("Fixtures")])
    ],
    swiftLanguageModes: [.v5]
)
