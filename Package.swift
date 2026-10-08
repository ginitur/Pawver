// swift-tools-version: 6.0
import PackageDescription

// Command Line Tools ship Swift Testing outside the default runtime search
// paths, so the test bundle needs explicit rpaths (see docs/PLAN.md §1.1).
let cltTestingRPaths: [String] = [
    "-Xlinker", "-rpath", "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
    "-Xlinker", "-rpath", "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib",
]

let package = Package(
    name: "FloatShelf",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "FloatShelf", targets: ["FloatShelf"]),
        .library(name: "FloatShelfCore", targets: ["FloatShelfCore"]),
    ],
    targets: [
        .target(name: "FloatShelfCore"),
        .executableTarget(
            name: "FloatShelf",
            dependencies: ["FloatShelfCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
            ]
        ),
        .testTarget(
            name: "FloatShelfCoreTests",
            dependencies: ["FloatShelfCore"],
            linkerSettings: [.unsafeFlags(cltTestingRPaths)]
        ),
    ]
)
