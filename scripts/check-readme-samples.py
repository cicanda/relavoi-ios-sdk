#!/usr/bin/env python3
"""Fail if a README sample calls create() with a parameter it does not have.

Not a compiler. Compiling the samples needs Xcode and an iOS SDK and a way to
tell a copy-paste sample from a reference listing, which is a bigger job; this
catches the one fault that actually happened, four times, in three SDKs' docs
and in this README: 0.3.0 removed `recordingEnabled` and `consentPrompt` from
create, and every sample kept passing them. Nothing noticed for two releases.

The allowed set is read from the protocol, so it cannot drift from the source.
"""
import pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PROTOCOL = ROOT / "Sources/RelavoiSDK/Session/SessionManager.swift"
README = ROOT / "README.md"

src = PROTOCOL.read_text()
# The requirement, not the convenience overload: the convenience may add
# labels with defaults, and a sample passing one of those is still fine.
m = re.search(r'func createSession\(\s*(.*?)\s*\) async throws -> Session', src, re.S)
if not m:
    print("::error::could not find createSession in the protocol; update this script", file=sys.stderr)
    sys.exit(2)
allowed = set(re.findall(r'^\s*(\w+):', m.group(1), re.M))

ext = re.search(r'public extension SessionManager \{(.*?)\n\}', src, re.S)
if ext:
    for call in re.finditer(r'func create\(\s*(.*?)\s*\) async throws -> Session', ext.group(1), re.S):
        allowed |= set(re.findall(r'^\s*(\w+):', call.group(1), re.M))

print("create() accepts:", ", ".join(sorted(allowed)))

bad = 0
for block in re.finditer(r'```swift\n(.*?)```', README.read_text(), re.S):
    code = block.group(1)
    for call in re.finditer(r'\.create\(\s*(.*?)\n\s*\)', code, re.S):
        passed = set(re.findall(r'^\s*(\w+):', call.group(1), re.M))
        extra = passed - allowed
        if extra:
            print(f"::error::README create() is passed {', '.join(sorted(extra))}, "
                  f"which create() does not accept")
            bad += 1

if bad:
    print("\nThe sample would not compile. Fix the README.")
    sys.exit(1)
print("README create() samples pass only parameters create() accepts.")
