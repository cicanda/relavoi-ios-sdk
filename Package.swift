// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RelavoiSDK",
    platforms: [
        // iOS is the product platform. This floor is the supported minimum and
        // must not be raised without a major version bump.
        .iOS(.v15),
        // macOS is declared only so that `swift build` / `swift test` on a Mac
        // host get a modern deployment target instead of SwiftPM's very old
        // default, which rejected async/await, URLSessionWebSocketTask and
        // URLSession.data(for:delegate:) outright. CI uses the host build to
        // type-check the platform-independent code and run the unit suite.
        //
        // This is NOT a claim of macOS feature parity. Call detection
        // (CallKit), Live Activities (ActivityKit) and dialer hand-off (UIKit)
        // are iOS-only and compile out on macOS, so the macOS build of this
        // library is for testing, not shipping.
        .macOS(.v12),
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
