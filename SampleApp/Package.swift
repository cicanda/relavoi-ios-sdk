// swift-tools-version:5.9
import PackageDescription

// This manifest lets SwiftPM/Xcode resolve the local RelavoiSDK for the sample
// sources. NOTE: the sources use iOS-only SwiftUI/UIKit APIs, so they are meant
// to be built by Xcode for an iOS target (or pasted into a new Xcode app) — a
// plain `swift build` on a macOS host will not compile the iOS UI. See README.md.
let package = Package(
    name: "RelavoiSampleApp",
    platforms: [.iOS(.v16)],
    dependencies: [
        .package(path: "../")
    ],
    targets: [
        .executableTarget(
            name: "RelavoiSampleApp",
            dependencies: [
                .product(name: "RelavoiSDK", package: "relavoi-ios-sdk")
            ],
            path: "Sources"
        )
    ]
)
