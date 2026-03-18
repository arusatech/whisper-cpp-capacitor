// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WhisperCpp",
    platforms: [.iOS(.v13)],
    products: [
        .library(
            name: "WhisperCppCapacitor",
            targets: ["WhisperCppPlugin"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", from: "8.0.0")
    ],
    targets: [
        .target(
            name: "WhisperCppPlugin",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm")
            ],
            path: "ios/Sources/WhisperCppPlugin",
            sources: ["WhisperCppPlugin.swift", "WhisperCpp.swift", "WhisperCppBridge.mm"]
        )
    ]
)
