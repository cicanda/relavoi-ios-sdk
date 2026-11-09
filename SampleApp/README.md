# Relavoi iOS Sample App

Developer test harness for the Relavoi iOS SDK. Not a production UI: a column of
buttons that each exercise one SDK feature against the backend at
`https://api.relavoi.com/v1`, using a workspace of your own.

The sources are plain SwiftUI files meant to be dropped into an Xcode iOS app.
They use iOS-only APIs, so they build under Xcode for an iOS target, not via a
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
4. In `ContentView.swift`, replace `PASTE_YOUR_API_KEY`,
   `PASTE_YOUR_API_SECRET` and `PASTE_YOUR_WORKSPACE_ID` with your own
   workspace's values, from the section below. The backend URL is already set.
5. (Optional) For Live Activities, add `NSSupportsLiveActivities = YES` to
   `Info.plist`.
6. Run on a device or simulator (iOS 16+).

Tap the buttons top-to-bottom, starting with **Initialize SDK** (the other
buttons refuse to run until the SDK is initialized). Every operation and its
result is appended to the on-screen log.

## Credentials: use a workspace of your own

This harness does not ship with a workspace, and the keys to ours are not
shared. A sandbox key is free and takes about a minute, and it means the
sessions you create while trying the SDK are yours rather than mixed into
somebody else's test data.

1. Sign up at <https://app.relavoi.com/signup>.
2. Open **API & Keys** in the dashboard and press **Generate sandbox keys**.
   The key and the secret are shown once, when they are generated, so copy
   both before leaving the page. Regenerating invalidates the previous pair.
3. The workspace id is on that same page, inside the ready-made SDK snippets.

Sandbox keys talk to the same backend as live ones and need no approval. What
they will not do is place a real call: a sandbox session is routed and recorded
exactly as a live one but never reaches the carrier, which is what makes it
safe to run this harness against the numbers below.

All three go into `ContentView.swift`, which is not committed to git. The
backend is `https://api.relavoi.com/v1` and is already set.

## Test numbers (pre-filled in the UI)

- Agent phone: `+2349000000001`
- Customer phone: `+2349000000002`

## Features exercised

- **Session CRUD**: create / get / end / list
- **Call initiation**: `initiateCall` opens the native dialer with the proxy number
- **Call verification**: `/sessions/verify` plus `isCallActive` (CXCallObserver)
- **WebSocket events**: connect and stream `RelavoiEvent`s into the log
- **Presence tracking**: `setUserPhone` (auto online/background/offline on lifecycle)

Push (APNs) is not wired into this harness because it needs a real device token
from `didRegisterForRemoteNotifications`; use `Relavoi.shared.push.registerToken(userPhone:deviceToken:)`
in your app's app-delegate once you have one.
