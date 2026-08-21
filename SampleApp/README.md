# Relavoi iOS Sample App

Developer test harness for the Relavoi iOS SDK. Not a production UI — a column of
buttons that each exercise one SDK feature against the **live backend**
(`https://api.relavoi.com/v1`) using the **Bolt Nigeria** test tenant.

The sources are plain SwiftUI files meant to be dropped into an Xcode iOS app.
They use iOS-only APIs, so they build under Xcode for an iOS target — not via a
plain `swift build` on macOS. The `Package.swift` here exists only so SwiftPM /
Xcode can resolve the local `RelavoiSDK` package for the sources.

## Setup

1. Open Xcode and create a new **iOS App** project (interface: SwiftUI).
2. Add the SDK: **File → Add Package Dependencies… → Add Local…** and select the
   `relavoi-ios-sdk` directory (the one containing the SDK's `Package.swift`).
   Add the **RelavoiSDK** library product to your app target.
3. Copy these three files into your project (replacing the generated `App`/
   `ContentView`):
   - `Sources/SampleApp.swift`
   - `Sources/ContentView.swift`
   - `Sources/SDKLogView.swift`
4. In `ContentView.swift`, replace `PASTE_YOUR_API_KEY` / `PASTE_YOUR_API_SECRET`
   with the Bolt Nigeria test key/secret (shared out-of-band — not committed to
   git). The tenant ID and backend URL are already set.
5. (Optional) For Live Activities, add `NSSupportsLiveActivities = YES` to
   `Info.plist`.
6. Run on a device or simulator (iOS 16+).

Tap the buttons top-to-bottom, starting with **Initialize SDK** (the other
buttons refuse to run until the SDK is initialized). Every operation and its
result is appended to the on-screen log.

## Test credentials

- API Key / Secret: **Bolt Nigeria test tenant** — shared out-of-band, paste into
  `ContentView.swift` (not committed to git).
- Tenant ID: `f656ac1b-3b5d-4af0-8ff1-c4cbc1076144` (Bolt Nigeria)
- Backend: `https://api.relavoi.com/v1`

## Test numbers (pre-filled in the UI)

- Agent phone: `+2347067379297`
- Customer phone: `+2348162662319`

## Features exercised

- **Session CRUD** — create / get / end / list
- **Call initiation** — `initiateCall` opens the native dialer with the proxy number
- **Call verification** — `/sessions/verify` plus `isCallActive` (CXCallObserver)
- **WebSocket events** — connect and stream `RelavoiEvent`s into the log
- **Presence tracking** — `setUserPhone` (auto online/background/offline on lifecycle)

Push (APNs) is not wired into this harness because it needs a real device token
from `didRegisterForRemoteNotifications`; use `Relavoi.shared.push.registerToken(userPhone:deviceToken:)`
in your app's app-delegate once you have one.
