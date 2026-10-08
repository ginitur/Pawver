// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FloatShelf",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FloatShelfCore", targets: ["FloatShelfCore"]),
    ],
    targets: [
        .target(name: "FloatShelfCore"),
    ]
)
