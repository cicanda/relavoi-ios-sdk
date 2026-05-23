# Relavoi iOS SDK

Swift SDK for embedding Relavoi's privacy telephony into iOS apps. Swift Package, swift-tools 5.9, targets iOS 15+. Zero external dependencies.

## What it gives you

| Subsystem | What it does |
|---|---|
| `Relavoi.shared.sessions` | Create / get / end / list / verify masking sessions; `@MainActor initiateCall()` opens `tel:` URL via `UIApplication.shared.open` |
| `Relavoi.shared.verification` | Calls `/sessions/verify`; observes call state via `CXCallObserver` (no permission required) |
| `Relavoi.shared.push` | Registers APNs `Data` tokens with `/devices/token`, auto hex-encodes |
| `Relavoi.shared.events` | `URLSessionWebSocketTask` with exponential reconnect; manual listener IDs |
| `Relavoi.shared.presence` | Tracks `didBecomeActive` / `willResignActive` / `willTerminate` |
| `LiveActivityManager` (iOS 16.1+) | `ActivityKit` integration for Dynamic Island + lock-screen verified-call banner |

## Install

```swift
// Package.swift
dependencies: [
  .package(url: "https://github.com/cicanda/relavoi-ios-sdk", from: "0.1.0"),
]

.target(
  name: "MyApp",
  dependencies: [
    .product(name: "RelavoiSDK", package: "relavoi-ios-sdk"),
  ]
)
```

## Quick start

```swift
// AppDelegate / @main App.init
Relavoi.initialize(
  apiKey: ProcessInfo.processInfo.environment["RELAVOI_API_KEY"]!,
  apiSecret: ProcessInfo.processInfo.environment["RELAVOI_API_SECRET"]!,
  tenantId: "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
)

// Anywhere — async/await throughout
let session = try await Relavoi.shared.sessions.create(
  agentPhone: "+2348012345678",
  customerPhone: "+2348087654321",
  metadata: ["orderId": "CHW-9281"],
  gracePeriodMinutes: 15,
  directionMode: .bidirectional,
  recordingEnabled: false,
  consentPrompt: .none
)
print(session.proxyNumber)
```

## Verified-call UX on iOS

iOS does not allow apps to draw over the native dialer (no equivalent to Android's `SYSTEM_ALERT_WINDOW`). The SDK gives you two platform-honest mechanisms:

### Live Activity (iOS 16.1+)

`LiveActivityManager.start(...)` shows a persistent verified-call banner on the lock screen and in the Dynamic Island. The bundled `RelavoiCallActivityView` and `RelavoiCallCompactView` views are designed to drop straight into your app's `WidgetBundle`:

```swift
@main
struct MyWidgets: WidgetBundle {
  var body: some Widget {
    ActivityConfiguration(for: RelavoiCallAttributes.self) { ctx in
      RelavoiCallActivityView(context: ctx)        // lock screen
    } dynamicIsland: { ctx in
      DynamicIsland {
        // expanded regions
      } compactLeading:  { RelavoiCallCompactView.compactLeading(ctx)  }
        compactTrailing: { RelavoiCallCompactView.compactTrailing(ctx) }
        minimal:         { RelavoiCallCompactView.minimal(ctx)         }
    }
  }
}
```

### CallKit Call Directory (any iOS version)

Brand the proxy number in caller ID with a static label like "Chowdeck Courier" via `CXCallDirectoryProvider`. Not dynamic per-session but solves the "unknown number" problem at the OS level.

## Architecture

```
Sources/RelavoiSDK/
  Relavoi.swift             public class — Relavoi.initialize + Relavoi.shared.*
  RelavoiConfig.swift       baseURL / webSocketURL / enableLogging
  RelavoiError.swift        LocalizedError-conforming enum
  Auth/                     actor AuthManager (thread-safe token caching), TokenStore (Keychain)
  Session/                  protocol + impl + Codable models + VerificationResult
  Verification/             protocol + impl wrapping CXCallObserver
  Push/                     PushTokenManager (Data → hex, dedup cache)
  Events/                   actor EventStreamManagerImpl (URLSessionWebSocketTask + reconnect)
  Presence/                 UIApplication lifecycle observers
  Offline/                  JSON-file-backed queue in .cachesDirectory
  LiveActivity/             RelavoiCallAttributes + LiveActivityManager + Activity View + Compact View
  Internal/                 APIClient (URLSession + async/await + 401-retry), Logger (os_log), PhoneUtils
Tests/RelavoiSDKTests/      PhoneUtils, APIClient (URLProtocol mock), AuthManager, SessionManager
```

All UIKit / CallKit / ActivityKit imports are wrapped in `#if canImport(...)` so `swift build` on a macOS host can type-check the iOS-only code paths.

## Build & test

```bash
swift build
swift test
```

For iOS-specific code paths use Xcode:

```bash
xcodebuild test \
  -scheme RelavoiSDK \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Privacy

Phone numbers are **never logged in plaintext**. `PhoneUtils.mask()` and `PhoneUtils.hashClientSide()` (CommonCrypto `CC_SHA256` via `@_silgen_name`) are the only safe ways to surface a phone in logs or the SDK's own state.

## Related Repositories

- [relavoi-backend](https://github.com/cicanda/relavoi-backend) — API server (this SDK is a client of)
- [relavoi-android-sdk](https://github.com/cicanda/relavoi-android-sdk) — Android SDK (matching feature set)
- [relavoi-docs](https://github.com/cicanda/relavoi-docs) — Documentation site
- [relavoi-dashboard](https://github.com/cicanda/relavoi-dashboard) — Tenant web dashboard
- [relavoi-admin](https://github.com/cicanda/relavoi-admin) — Operator console
- [relavoi-infra](https://github.com/cicanda/relavoi-infra) — Terraform infrastructure
