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
  .package(url: "https://github.com/cicanda/relavoi-ios-sdk", from: "0.3.2"),
]

.target(
  name: "MyApp",
  dependencies: [
    .product(name: "RelavoiSDK", package: "relavoi-ios-sdk"),
  ]
)
```

## Quick start

### Where the token comes from

Your backend holds the API key and secret and calls `POST /v1/auth/sdk-token`
for one user; the app asks your backend and hands the result to the SDK. The
secret never reaches the handset, because anything compiled into a published
app can be read back out of it, and a live key and secret let anyone create
sessions billed to you and list every session and call on your workspace.

```swift
// AppDelegate / @main App.init
Relavoi.initialize(tenantId: "a1b2c3d4-e5f6-7890-abcd-ef1234567890") {
  // Ask YOUR backend, which holds the API secret.
  let t = try await MyBackend.relavoiToken()
  return RelavoiToken(accessToken: t.accessToken, expiresIn: t.expiresIn)
}

// Anywhere: async/await throughout
let session = try await Relavoi.shared.sessions.create(
  agentPhone: "+2348012345678",
  customerPhone: "+2348087654321",
  metadata: ["orderId": "CHW-9281"],
  gracePeriodMinutes: 15,
  directionMode: .bidirectional
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
  Relavoi.swift             public class: Relavoi.initialize + Relavoi.shared.*
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

UIKit code is wrapped in `#if canImport(UIKit)`. CallKit and ActivityKit code is wrapped in `#if os(iOS)`, **not** `canImport`: both of those modules import fine on a macOS host, and it is the types inside them (`CXCallObserver`, `Activity`, `ActivityViewContext`) that are `@available(macOS, unavailable)`, so `canImport` guards nothing there.

A macOS host build therefore type-checks and unit-tests the platform-independent code only. Call detection, Live Activities and the dialer hand-off compile out; use a simulator destination to build those. `Package.swift` declares `.macOS(.v12)` purely to give the host build a modern deployment target, not as a claim of macOS support.

## Build & test

```bash
swift build
swift test
```

For the iOS-only code paths use Xcode against a simulator. Device *names* come and
go with each Xcode release, so resolve one that actually exists rather than
hardcoding a model:

```bash
udid=$(xcrun simctl list devices available | awk '
  /^-- iOS/ { in_ios = 1; next }
  /^-- /    { in_ios = 0 }
  in_ios && /iPhone/ && match($0, /\(([0-9A-Fa-f-]{36})\)/) {
    print substr($0, RSTART + 1, RLENGTH - 2); exit
  }')

xcodebuild test \
  -scheme RelavoiSDK \
  -destination "platform=iOS Simulator,id=$udid" \
  CODE_SIGNING_ALLOWED=NO
```

## Privacy

Phone numbers are **never logged, in any form**. Not in full, and not masked to
the last four digits: no log line, error message or crash report carries any
part of a number. `PhoneUtils.mask()` existed for that purpose and was removed
in 0.2.0, because `+****5678` is still part of a number. Log lines use the
session id instead, which is the key that actually correlates them.

`PhoneUtils.hashClientSide()` (CommonCrypto `CC_SHA256` via `@_silgen_name`)
remains, for the SDK's own internal keying such as push-token deduplication. It
is not for logs.

Validation at the SDK boundary is deliberately light: non-empty, digits, with an
optional leading plus. The server owns the real rule and reads it from its
countries table, so it can change without a new SDK release. A number the
platform does not support arrives as `RelavoiError.numberNotSupported`, and two
numbers in different countries as `RelavoiError.crossBorderNotSupported`.

## Related Repositories

- relavoi-backend (private): API server (this SDK is a client of)
- [relavoi-android-sdk](https://github.com/cicanda/relavoi-android-sdk): Android SDK (matching feature set)
- [relavoi-docs](https://github.com/cicanda/relavoi-docs): Documentation site
- [relavoi-dashboard](https://github.com/cicanda/relavoi-dashboard): Tenant web dashboard
- [relavoi-admin](https://github.com/cicanda/relavoi-admin): Operator console
- relavoi-infra (private): Terraform infrastructure

## License

Apache License 2.0. See [LICENSE](./LICENSE).

Copyright 2026 CICANDA Ltd.
