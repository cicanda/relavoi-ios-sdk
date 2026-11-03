## 0.3.3

### The token call goes through the SDK's own session

`/auth/token` was the one request in the SDK that used `URLSession.shared`
directly instead of the session handed to `APIClient`. So anything configured
on that session applied to every call except the one that authenticates them:
a host app's timeouts, a proxy, additional headers, or a `URLProtocol`
registered on that session alone.

`AuthManager` now takes the session and uses it, and `Relavoi` builds one
session and hands the same instance to both, so the two cannot drift apart
again. Nothing about the public API changes.

There is a test for it that cannot pass by accident: the mock it uses is never
registered globally, only in one `URLSessionConfiguration`, so a request
arriving there proves the injected session carried it. Putting
`URLSession.shared` back fails it.

### A release cannot disagree with its own tag

`scripts/check-release-version.sh` runs on a tag push and fails the release if
the README install snippet or the newest CHANGELOG section names a version
other than the tag being cut.

This is here because 0.3.2 was tagged with a README that still said 0.3.1, the
release whose `create()` and `list()` crashed, and the tag had to be
force-moved to fix it. Moving a published tag is exactly what should not
happen: SwiftPM had already cached the old revision for 0.3.2 and then refused
to resolve it. The version bump belongs in the release commit, and this proves
it was.

### The simulator job had never run

`ios-simulator` was gated to pull requests, and work here lands by pushing to
main, so the job that compiles and exercises the iOS-only code paths had never
run once. It now runs on pull requests, on every push to main, and on release
tags.

## 0.3.2

### `create()` and `list()` called themselves until the process died

Both convenience methods on `SessionManager` were unusable in 0.3.0 and
0.3.1. **Any app calling `create(agentPhone:customerPhone:)` or `list()`
crashed**, and the sample app in this repository crashed on its first button.

The cause is a Swift rule that is easy to walk into. A protocol extension
method that shares its name and argument labels with a protocol requirement
does not satisfy that requirement: it is a separate overload. Both methods
were declared in the extension with the requirements' own labels and then
forwarded to themselves, so each call recursed until the stack ran out.

`create` was worse than ambiguous. It also still accepted `recordingEnabled`
and `consentPrompt`, which 0.3.0 removed from the API, so the only overload
that could accept them was the recursive one.

The fix makes the mistake impossible rather than merely absent. The two
requirements are now named `createSession` and `listSessions`, so the
forwarding call in the extension has no overload to resolve to except the
requirement. Callers are unaffected and keep writing `create(...)` and
`list(...)`, with the same defaults as before.

**If you implement `SessionManager` yourself**, rename your two methods to
`createSession` and `listSessions`. Nothing else changes. If you obtain the
manager from `Relavoi.sessions`, as the documentation shows, there is nothing
to do.

`recordingEnabled` and `consentPrompt` are now a compile error on `create`
rather than a crash, which is what 0.3.0 intended when it removed them.

### Why no test caught it

The test file for these methods never ran. Its first case recursed, the
process died with no assertion failure, and the suite reported nothing, so CI
had been red since 1 November while looking like a hang rather than a failure.
There are now tests for each call shape a caller actually writes: two
arguments, three, and all five. They assert only that the call returns, which
is the whole guard, because a recursing call never does.

## 0.3.1

### Apache License 2.0

This repository is public and is what integrators read, and it shipped without
a licence. Nobody could use it: no licence means all rights reserved, so a
company's legal review would have stopped an integration whatever the README
promised.

The licence is Apache 2.0, the full text is in `LICENSE`, and the README says
so. Nothing about the code or the API has changed in this release.

## 0.3.0

### Initialize with a token provider, so no secret ships in the app

`initialize()` took the API key and secret, and anything compiled into a
published app can be read back out of it. It now takes a token provider: your
app asks your own backend, which holds the secret and calls
`POST /v1/auth/sdk-token` for one user. The key and secret form still works,
deprecated, and warns at runtime when the key is a live one.

`create()` no longer takes `recordingEnabled` or `consentPrompt`. The API
refuses `recordingEnabled: true` with `feature-not-available`, so they
configured nothing. Both fields are still returned on `Session`.

This release went out with the `create()` and `list()` defect described under
0.3.2. Use 0.3.2 or later.

### `Package.swift` now declares a macOS platform

CI could never build or test this package: the manifest declared only
`.iOS(.v15)`, so a host build fell back to SwiftPM's very old default macOS
deployment target and rejected async/await, `URLSessionWebSocketTask` and
`URLSession.data(for:delegate:)`.

`.macOS(.v12)` is now declared alongside the iOS floor. **This is not macOS
support.** Call detection, Live Activities and the dialer hand-off are iOS-only
and compile out off iOS. The iOS floor is unchanged at 15.

The CallKit and ActivityKit code was guarded with `#if canImport(...)`, which
guarded nothing: both modules import on macOS, and it is the types inside them
that are `@available(macOS, unavailable)`. Those guards are now `#if os(iOS)`.
No iOS behaviour changes.

## 0.2.0

### Phone numbers: the server decides, not the SDK

The client-side check was strict E.164 (`^\+[1-9]\d{6,14}$`). It was wrong in
both directions, and the second direction is the one that hurt:

* It **refused numbers the API accepts.** Someone typing `08031234567`, or
  pasting `0803 123 4567` out of their contacts, got a client-side error for a
  number the platform would have taken. Only the full `+234...` form worked.
* It **accepted numbers the API refuses**, such as a UK mobile or a Nigerian
  landline, so the SDK let a call to `create` through and the server refused it.

The check is now deliberately light: non-empty, digits, with an optional leading
plus. Separators (spaces, brackets, hyphens, dots, non-breaking spaces, Unicode
dashes) are stripped using the same set the server strips, so the SDK cannot
reject a value the API would accept. The server owns the rule, reads it from its
countries table, and can change it without a new SDK release.

### Two new typed errors

The server's refusals now arrive as cases you can switch on, rather than a
generic `.validation`:

* `.numberNotSupported(detail:)` for a number Relavoi does not connect. Today
  that means anything other than a Nigerian mobile.
* `.crossBorderNotSupported(detail:)` when the two parties are not in the same
  country.

Both are matched on the problem document's `type` slug, so they work against any
environment. Neither detail contains the number that was refused.

### No part of a phone number in any message or log line

Several places leaked digits, and one leaked whole numbers:

* The validation error appended the **last four digits** of the rejected value.
  Removed. The detail now names the field and the expected shape, nothing else.
* Request logging wrote the **full path including the query string**, and
  `/sessions/verify` carries the subscriber's number there. With SDK logging on,
  that put a plaintext phone number in the unified log. Only the path is logged
  now, and the same applies to the `.unexpected` message for a non-HTTP response.
* `PhoneUtils.mask` returned `+****5678`, and those last four digits were logged
  for both parties on session creation. The function is gone and that line no
  longer carries a number.
* Error responses no longer surface a **raw body**. Only `type` and `detail` are
  read from a problem document. An error page from in front of the API commonly
  echoes the request URI, which is how a number would have reached a crash
  reporter.

### Possibly breaking

* `RelavoiError` has two new cases. An exhaustive `switch` over it will need
  them.
* `.api(statusCode:body:)` no longer carries the raw response body. `body` is
  now the problem `detail`, or nil. The status code is unchanged.
* `.unauthorized(detail:)` carries the problem `detail` rather than the raw body.
* `PhoneUtils` is internal, but if you reached it: `requireValidE164` is now
  `requireNumberShaped` and returns the canonical form, `validateE164` is now
  `looksLikeNumber`, and `mask` is removed.
* Numbers are sent with separators stripped. `0803 123 4567` goes out as
  `08031234567`.

## 0.1.0

* First release: auth, sessions, call verification, push registration,
  WebSocket events, presence, Live Activities and the offline queue.
