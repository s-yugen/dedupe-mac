// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DedupeMac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DedupeMac", targets: ["DedupeMac"]),
    ],
    targets: [
        .target(name: "DedupeCore"),
        .executableTarget(name: "DedupeMac", dependencies: ["DedupeCore"]),
        .testTarget(name: "DedupeCoreTests", dependencies: ["DedupeCore"]),
    ]
)
