// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "swift-cordis",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17), .watchOS(.v10)],
    products: [
        .library(name: "Cordis", targets: ["Cordis"]),
        .library(name: "CordisKernel", targets: ["CordisKernel"]),
        .executable(name: "cordis-demo", targets: ["CordisDemo"]),
        .executable(name: "cordis-bench", targets: ["CordisBench"])
    ],
    targets: [
        .target(name: "CordisKernel"),
        .target(name: "Cordis", dependencies: ["CordisKernel"]),
        .executableTarget(name: "CordisDemo", dependencies: ["Cordis"]),
        .executableTarget(name: "CordisBench", dependencies: ["Cordis"]),
        .testTarget(name: "CordisKernelTests", dependencies: ["CordisKernel"]),
        .testTarget(name: "CordisTests", dependencies: ["Cordis"])
    ]
)
