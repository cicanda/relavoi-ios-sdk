# Backlog

Work that was found, understood and deliberately not done, with enough detail
that picking it up does not mean rediscovering it. Dated entries, newest first.
Delete an entry when it ships; do not leave it here marked done.

## 2026-11-02

### swiftlint in CI

CI runs `swift build`, `swift test` and an `xcodebuild test` against the
simulator, so the code is compiled and exercised on both the host and iOS.
Nothing checks Swift style or catches the class of problem a linter does. This
repo and the Android SDK are the two left without a lint gate after the three
web repos got ESLint today.

How to pick it up:

1. SwiftLint is not a Swift Package Manager plugin we want in `Package.swift`:
   adding it as a build-tool plugin makes every integrator's build depend on
   it, and this package is installed by SPM straight from a git tag. Install it
   in CI instead, `brew install swiftlint` on the macOS runner, and run
   `swiftlint lint --strict`.
2. Add `.swiftlint.yml` at the root. Start by disabling nothing and running it
   to see the count; this code has never been linted. `line_length` and
   `type_body_length` are the usual first two to relax for a file like the
   SDK's public surface, where a long declaration is clearer than a wrapped
   one.
3. Add the step to the existing `swift-build` job in
   `.github/workflows/ci.yml`, before `swift build`, with no
   `continue-on-error`. `--strict` turns warnings into errors, so decide
   deliberately whether to use it: without it, warnings are reported and the
   build passes, which matches the policy the web repos use.

Note the two-job shape of that workflow. The host job compiles everything
outside `#if os(iOS)` and the simulator job covers CallKit, ActivityKit and the
UIKit dialer hand-off. Linting belongs in the host job: it reads source and
does not need a simulator.
