// swift-tools-version:5.8
import PackageDescription

let package = Package(
    name: "TouchJockey",
    platforms: [.macOS(.v13)],
    targets: [
        // Audio engine, beat analysis and the control server. No external dependencies.
        .target(name: "TJCore", path: "Sources/TJCore"),
        // The Mac app: window plus the web surface it serves to phones and tablets.
        .executableTarget(
            name: "TouchJockey",
            dependencies: ["TJCore"],
            path: "Sources/TouchJockey",
            resources: [.copy("Surface")]
        ),
        // Command-line beat analysis, for checking the analyzer against real tracks.
        .executableTarget(name: "tj-analyze", dependencies: ["TJCore"], path: "Sources/tj-analyze"),
    ]
)
