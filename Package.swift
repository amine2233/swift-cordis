// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "swift-cordis",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17), .watchOS(.v10)],
    products: [
        .library(name: "Cordis", targets: ["Cordis"]),
        .library(name: "CordisKernel", targets: ["CordisKernel"]),
        .library(name: "CordisLoader", targets: ["CordisLoader"]),
        .executable(name: "cordis-demo", targets: ["CordisDemo"])
    ],
    targets: [
        .target(name: "CordisKernel"),
        .target(name: "Cordis", dependencies: ["CordisKernel"]),
        .target(name: "CordisLoader", dependencies: ["Cordis"]),
        .executableTarget(name: "CordisDemo", dependencies: ["Cordis"]),
        .testTarget(name: "CordisKernelTests", dependencies: ["CordisKernel"]),
        .testTarget(name: "CordisTests", dependencies: ["Cordis"]),
        .testTarget(name: "CordisLoaderTests", dependencies: ["CordisLoader"])
    ]
)
