// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ANNReader",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "ANNKit"),
        .executableTarget(name: "ANNReaderApp", dependencies: ["ANNKit"]),
        .testTarget(name: "ANNKitTests", dependencies: ["ANNKit"]),
    ]
)
