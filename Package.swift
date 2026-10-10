// swift-tools-version: 6.0
import PackageDescription

// Command Line Tools ship Swift Testing outside the default runtime search
// paths, so the test bundle needs explicit rpaths (see docs/PLAN.md §1.1).
let cltTestingRPaths: [String] = [
    "-Xlinker", "-rpath", "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
    "-Xlinker", "-rpath", "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib",
]

let package = Package(
    name: "Pawver",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Pawver", targets: ["Pawver"]),
        .library(name: "PawverCore", targets: ["PawverCore"]),
    ],
    targets: [
        .target(name: "PawverCore"),
        .executableTarget(
            name: "Pawver",
            dependencies: ["PawverCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
            ]
        ),
        .testTarget(
            name: "PawverCoreTests",
            dependencies: ["PawverCore"],
            linkerSettings: [.unsafeFlags(cltTestingRPaths)]
        ),
    ]
)
