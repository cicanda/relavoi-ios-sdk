// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RelavoiSDK",
    platforms: [
        .iOS(.v15),
    ],
    products: [
        .library(
            name: "RelavoiSDK",
            targets: ["RelavoiSDK"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "RelavoiSDK",
            dependencies: [],
            path: "Sources/RelavoiSDK"
        ),
        .testTarget(
            name: "RelavoiSDKTests",
            dependencies: ["RelavoiSDK"],
            path: "Tests/RelavoiSDKTests"
        ),
    ]
)
