// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "swift-cordis",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "Cordis", targets: ["Cordis"]),  // usage normal
        .library(name: "CordisKernel", targets: ["CordisKernel"]),  // noyau seul
    ],
    targets: [
        .target(name: "CordisKernel"),  // Scope, Fork, Registry, Context
        .target(name: "Cordis", dependencies: ["CordisKernel"]),  // ServicePlugin, mixins, helpers
        .testTarget(name: "CordisKernelTests", dependencies: ["CordisKernel"]),
    ]
)
