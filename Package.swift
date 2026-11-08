// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DelayNoMore",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "DelayNoMore", targets: ["DelayNoMore"]),
        .library(name: "DelayCore", targets: ["DelayCore"]),
        .executable(name: "DelayCoreChecks", targets: ["DelayCoreChecks"]),
    ],
    targets: [
        .target(name: "DelayCore"),
        .executableTarget(name: "DelayNoMore", dependencies: ["DelayCore"]),
        .executableTarget(name: "DelayCoreChecks", dependencies: ["DelayCore"]),
        .testTarget(name: "DelayCoreTests", dependencies: ["DelayCore"]),
    ]
)
