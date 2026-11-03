#!/usr/bin/env python3
"""Type-check every Swift sample in a markdown file against this SDK.

Reads ```swift fences out of the files given on the command line, builds a
throwaway SwiftPM package with one target per sample, and type-checks the lot
for the iOS Simulator. A sample an integrator could not compile fails here.

See scripts/doc-samples/README.md for the fence annotations and the prelude.

    check-doc-samples.py README.md
    check-doc-samples.py --sdk . ../relavoi-docs/docs/sdks/ios
"""
from __future__ import annotations

import argparse
import os
import pathlib
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass, field

LANG = "swift"
MARKS = {"fragment", "reference", "manifest", "no-compile"}

# A top-level declaration, for the prelude-exclusion rule and the reference
# check. Deliberately simple: the samples are small and hand-written.
DECL = re.compile(
    r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*"
    r"(?:public\s+|internal\s+|private\s+|fileprivate\s+|open\s+)?"
    r"(?:final\s+)?(?:@\w+\s+)*"
    r"(struct|class|enum|protocol|extension|actor|func|let|var|typealias)\s+"
    r"([A-Za-z_]\w*)",
    re.M,
)


@dataclass
class Sample:
    path: pathlib.Path
    line: int
    mark: str
    reason: str
    code: str
    target: str = ""
    declares: set[str] = field(default_factory=set)
    linemap: dict[int, int] = field(default_factory=dict)

    @property
    def where(self) -> str:
        return f"{self.path}:{self.line}"


def extract(path: pathlib.Path) -> list[Sample]:
    out: list[Sample] = []
    lines = path.read_text().split("\n")
    i = 0
    while i < len(lines):
        m = re.match(r"^```(\S+)(.*)$", lines[i])
        if not m:
            i += 1
            continue
        lang, meta = m.group(1), m.group(2).strip()
        j = i + 1
        body: list[str] = []
        while j < len(lines) and not re.match(r"^```\s*$", lines[j]):
            body.append(lines[j])
            j += 1
        if lang == LANG:
            words = meta.split()
            mark, reason = "", ""
            if words and words[0] in MARKS:
                mark = words[0]
                reason = " ".join(words[1:])
            elif words:
                # An unrecognised first word is almost always a typo'd mark,
                # and treating it as "no annotation" would silently compile
                # something marked reference as app code, or the reverse.
                print(
                    f"::error file={path},line={i + 1}::unknown fence annotation "
                    f"{words[0]!r}. Use one of: {', '.join(sorted(MARKS))}"
                )
                sys.exit(2)
            s = Sample(path=path, line=i + 1, mark=mark, reason=reason, code="\n".join(body))
            s.declares = {d[1] for d in DECL.findall(s.code)}
            out.append(s)
        i = j + 1
    return out


def markdown_files(args: list[str]) -> list[pathlib.Path]:
    files: list[pathlib.Path] = []
    for a in args:
        p = pathlib.Path(a)
        if p.is_dir():
            files += sorted(p.rglob("*.md")) + sorted(p.rglob("*.mdx"))
        else:
            files.append(p)
    return [f for f in files if f.name != "CLAUDE.md"]


# ── the reference check ──────────────────────────────────────────────────────
#
# A reference listing claims "this is what the SDK gives you". So the names in
# it have to be names the SDK actually has. This does not type-check the
# listing; it checks that every type it names is declared in Sources/, and that
# every stored property and enum case it lists exists on that declaration.


def brace_body(src: str, from_index: int) -> tuple[str, int]:
    """The `{ ... }` starting at or after from_index, and the index past it."""
    start = src.find("{", from_index)
    if start < 0:
        return "", len(src)
    depth, k = 0, start
    while k < len(src):
        if src[k] == "{":
            depth += 1
        elif src[k] == "}":
            depth -= 1
            if depth == 0:
                return src[start:k + 1], k + 1
        k += 1
    return src[start:], len(src)


TYPE_DECL = re.compile(
    r"(?:^|\n)\s*(?:@\w+(?:\([^)]*\))?\s*\n\s*)*"
    r"(?:public\s+|open\s+|internal\s+)?(?:final\s+)?"
    r"(struct|class|enum|protocol|actor)\s+(\w+)"
)

MEMBER = re.compile(r"^\s*(?:public\s+|open\s+)?(?:let|var)\s+(\w+)\s*:", re.M)
CASE = re.compile(r"^\s*case\s+([\w, ]+)", re.M)


def types_in(src: str) -> dict[str, str]:
    """Every type declared in src, nested ones included, name -> its own body
    with nested type bodies removed.

    Nested types are hoisted to the top of the map under their bare name.
    RelavoiCallAttributes.State is just State here, which is enough: the
    listings use the bare name and the SDK has no two types sharing one.
    """
    out: dict[str, str] = {}
    for m in TYPE_DECL.finditer(src):
        name = m.group(2)
        body, _ = brace_body(src, m.end())
        if not body:
            continue
        own = body
        # Strip nested type bodies so their members are not attributed to the
        # enclosing type, which is what made RelavoiCallAttributes.State look
        # like three properties RelavoiCallAttributes does not have.
        for inner in TYPE_DECL.finditer(body[1:]):
            ibody, _ = brace_body(body[1:], inner.end())
            if ibody:
                own = own.replace(ibody, "")
        out.setdefault(name, own)
    return out


def sdk_declarations(sdk: pathlib.Path) -> dict[str, str]:
    found: dict[str, str] = {}
    for f in sorted((sdk / "Sources").rglob("*.swift")):
        for name, body in types_in(f.read_text()).items():
            found.setdefault(name, body)
    return found


def check_reference(s: Sample, decls: dict[str, str]) -> list[str]:
    problems: list[str] = []
    for name, listing in types_in(s.code).items():
        body = decls.get(name)
        if body is None:
            problems.append(
                f"{s.where}: reference listing declares {name}, which is not a type "
                f"in Sources/. Either the SDK renamed it or the listing invented it."
            )
            continue
        for member in MEMBER.findall(listing):
            if not re.search(rf"\b(?:let|var)\s+{re.escape(member)}\s*:", body):
                problems.append(
                    f"{s.where}: reference listing gives {name} a property "
                    f"`{member}` that {name} does not have."
                )
        listed_cases = set()
        for group in CASE.findall(listing):
            for case in (c.split("(")[0].strip() for c in group.split(",")):
                if case:
                    listed_cases.add(case)
        for case in sorted(listed_cases):
            if not re.search(rf"\bcase\s+[\w, ]*\b{re.escape(case)}\b", body):
                problems.append(
                    f"{s.where}: reference listing gives {name} a case "
                    f"`{case}` that {name} does not have."
                )
        # The other direction, which is the one that actually bit: a listing
        # that is a subset still reads as the complete set, and a reader who
        # writes an exhaustive switch from it gets a compile error.
        real_cases = set()
        for group in CASE.findall(body):
            for case in (c.split("(")[0].strip() for c in group.split(",")):
                if case:
                    real_cases.add(case)
        if listed_cases and real_cases - listed_cases:
            missing = ", ".join(sorted(real_cases - listed_cases))
            problems.append(
                f"{s.where}: reference listing of {name} is missing case(s) {missing}. "
                f"A reader switching exhaustively on this listing will not compile."
            )
    return problems


# ── package generation ───────────────────────────────────────────────────────

WRAPPER = [
    "// Wrapped by check-doc-samples.py: this fence is marked `fragment`, so it",
    "// is statements rather than declarations. iOS 17 availability is asserted",
    "// so ActivityKit snippets type-check; it costs the others nothing.",
    "// @MainActor because these snippets live in UI code in a real app, and",
    "// without it every one that touches a view warns about actor isolation.",
    "@available(iOS 17.0, *)",
    "@MainActor",
    "func __docSample() async throws {",
]


def target_name(s: Sample, seen: set[str]) -> str:
    stem = re.sub(r"\W+", "_", f"{s.path.stem}_{s.line}")
    name = f"Sample_{stem}"
    n = 2
    while name in seen:
        name = f"Sample_{stem}_{n}"
        n += 1
    seen.add(name)
    return name


IMPORT = re.compile(r"^\s*import\s+(\w+)")


def render(s: Sample, inherited: set[str]) -> tuple[str, dict[int, int]]:
    """Return the generated Swift file and a generated-line -> fence-line map.

    The map is the whole point: an error has to be reported against the
    markdown a human can edit, not against a file in a temporary directory.

    `inherited` is the set of modules imported by earlier fences on the same
    page. A page shows `import RelavoiSDK` and `import SwiftUI` once, at the
    top, and the snippets below it do not repeat the line; a reader working
    down the page has those imports in the file already. So the harness
    supplies them here. Nothing is invented: a module no fence on the page
    ever imports is not supplied, so a page that forgets the import
    altogether still fails.
    """
    body = [(s.line + 1 + i, t) for i, t in enumerate(s.code.split("\n"))]
    own = {m.group(1) for t in (t for _, t in body) if (m := IMPORT.match(t))}
    supply = sorted((inherited | {"Foundation"}) - own)
    out: list[tuple[int | None, str]] = [
        (None, f"// {s.where} — generated from the markdown; do not edit.")
    ]
    out += [(None, f"import {m}") for m in supply]
    if s.mark == "fragment":
        imports = [(n, t) for n, t in body if IMPORT.match(t)]
        rest = [(n, t) for n, t in body if not IMPORT.match(t)]
        if "RelavoiSDK" not in own and "RelavoiSDK" not in supply:
            out += [(None, "import RelavoiSDK")]
        out += imports
        out += [(None, w) for w in WRAPPER]
        out += rest
        out += [(None, "}")]
    else:
        out += body
    text = "\n".join(t for _, t in out) + "\n"
    linemap = {i + 1: n for i, (n, _) in enumerate(out) if n is not None}
    return text, linemap


def write_package(out: pathlib.Path, sdk: pathlib.Path, samples: list[Sample],
                  prelude: dict[str, str]) -> None:
    if out.exists():
        shutil.rmtree(out)
    (out / "Sources").mkdir(parents=True)
    seen: set[str] = set()
    inherited: dict[pathlib.Path, set[str]] = {}
    for s in samples:
        s.target = target_name(s, seen)
        d = out / "Sources" / s.target
        d.mkdir()
        for name, text in prelude.items():
            if name in s.declares:
                continue
            (d / f"{name}.swift").write_text(text)
        page = inherited.setdefault(s.path, set())
        text, s.linemap = render(s, set(page))
        page |= {m.group(1) for line in s.code.split("\n") if (m := IMPORT.match(line))}
        (d / "Sample.swift").write_text(text)

    # The dependency is referred to by package identity, which for a path
    # dependency is the directory name, not the Package(name:) inside it.
    pkg = sdk.resolve().name
    product = f'.product(name: "RelavoiSDK", package: "{pkg}")'
    targets = ",\n        ".join(
        f'.target(name: "{s.target}", dependencies: [{product}], path: "Sources/{s.target}")'
        for s in samples
    )
    deps = ", ".join(f'"{s.target}"' for s in samples)
    (out / "Package.swift").write_text(
        f"""// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DocSamples",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "DocSamples", targets: [{deps}]),
    ],
    dependencies: [
        .package(path: "{sdk.resolve()}"),
    ],
    targets: [
        {targets},
    ]
)
"""
    )


ERROR_LINE = re.compile(r"^(/[^:]+\.swift):(\d+):(\d+): (error|warning): (.*)$")


def build(out: pathlib.Path, samples: list[Sample]) -> int:
    by_target = {s.target: s for s in samples}
    cmd = [
        "xcodebuild",
        "-scheme", "DocSamples",
        "-destination", "generic/platform=iOS Simulator",
        "-derivedDataPath", str(out / "dd"),
        "-quiet",
        "build",
    ]
    print("$ " + " ".join(cmd) + f"   (in {out})")
    proc = subprocess.run(cmd, cwd=out, capture_output=True, text=True)
    text = proc.stdout + proc.stderr
    errors: dict[str, list[str]] = {}
    warnings: dict[str, list[str]] = {}
    for line in text.split("\n"):
        m = ERROR_LINE.match(line.strip())
        if not m:
            continue
        f, ln, _col, sev, msg = m.groups()
        p = pathlib.Path(f)
        s = by_target.get(p.parent.name)
        if s is None:
            continue
        if p.name == "Sample.swift":
            orig = s.linemap.get(int(ln))
            where = f"{s.path}:{orig}" if orig else f"{s.where} (generated line {ln})"
        else:
            where = f"{s.where} (via prelude {p.name})"
        bucket = errors if sev == "error" else warnings
        entry = f"  {where}: {msg}"
        # xcodebuild reports the same diagnostic more than once.
        if entry not in bucket.setdefault(s.where, []):
            bucket[s.where].append(entry)

    if warnings:
        print("\nWarnings (not fatal):")
        for where, msgs in sorted(warnings.items()):
            print(f"  {where}")
            print("\n".join(msgs))

    if not errors:
        if proc.returncode != 0:
            print("\nxcodebuild failed without an error this script could place:")
            print(text[-6000:])
            return 1
        return 0

    print("\nSamples that do not compile:\n")
    for where, msgs in sorted(errors.items()):
        print(f"::error::{where} does not compile")
        print("\n".join(msgs))
    return 1


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("--sdk", default=str(pathlib.Path(__file__).resolve().parent.parent))
    ap.add_argument("--out", default="")
    ap.add_argument("--keep", action="store_true", help="leave the generated package in place")
    args = ap.parse_args()

    sdk = pathlib.Path(args.sdk).resolve()
    prelude_dir = pathlib.Path(__file__).resolve().parent / "doc-samples" / "prelude"
    prelude = {p.stem: p.read_text() for p in sorted(prelude_dir.glob("*.swift"))}

    files = markdown_files(args.files)
    samples: list[Sample] = []
    for f in files:
        samples += extract(f)

    if not samples:
        print(f"::error::no ```{LANG} fences found in {', '.join(map(str, files))}")
        return 2

    census: dict[str, int] = {}
    for s in samples:
        census[s.mark or "compiled"] = census.get(s.mark or "compiled", 0) + 1
    print(f"{len(samples)} swift fences in {len(files)} file(s):")
    for k in ("compiled", "fragment", "reference", "manifest", "no-compile"):
        if census.get(k):
            print(f"  {census[k]:3d}  {k}")
    for s in samples:
        if s.mark == "no-compile":
            if not s.reason:
                print(f"::error file={s.path},line={s.line}::`no-compile` needs a reason.")
                return 2
            print(f"  not checked: {s.where}: {s.reason}")

    decls = sdk_declarations(sdk)
    problems: list[str] = []
    for s in samples:
        if s.mark == "reference":
            problems += check_reference(s, decls)
    if problems:
        print("\nReference listings that disagree with Sources/:\n")
        for p in problems:
            print(f"::error::{p}")
        return 1
    print(f"\nReference listings agree with Sources/ ({census.get('reference', 0)} checked).")

    todo = [s for s in samples if s.mark in ("", "fragment")]
    if not todo:
        return 0
    out = pathlib.Path(args.out) if args.out else pathlib.Path(
        os.environ.get("TMPDIR", "/tmp")
    ) / "relavoi-doc-samples-swift"
    write_package(out, sdk, todo, prelude)
    rc = build(out, todo)
    if rc == 0:
        print(f"\nAll {len(todo)} compiled samples type-check for the iOS Simulator.")
        if not args.keep:
            shutil.rmtree(out, ignore_errors=True)
    else:
        print(f"\nGenerated package left at {out} for inspection.")
    return rc


if __name__ == "__main__":
    sys.exit(main())
