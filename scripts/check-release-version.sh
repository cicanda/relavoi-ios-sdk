#!/usr/bin/env bash
#
# Fail if the tree disagrees with the tag being released.
#
# Why this exists: v0.3.2 was tagged while README.md still told the reader to
# install 0.3.1, which was the release whose create() and list() crashed. The
# tag had to be force-moved to fix it, and moving a published tag is the thing
# that is not supposed to happen: SwiftPM had already cached the old revision
# for 0.3.2 and refused to resolve it afterwards.
#
# So the version bump belongs in the release commit, and this is what proves it
# did. Run it with the tag, or let CI run it on a tag push:
#
#   scripts/check-release-version.sh v0.3.3
#
set -euo pipefail

TAG="${1:-${GITHUB_REF_NAME:-}}"
if [[ -z "$TAG" ]]; then
  echo "usage: $0 <tag>    (e.g. v0.3.3)" >&2
  exit 2
fi

# SwiftPM strips the leading v, so the tag is vX.Y.Z and the dependency reads X.Y.Z.
if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]]; then
  echo "::error::tag '$TAG' is not vMAJOR.MINOR.PATCH" >&2
  exit 1
fi
VERSION="${TAG#v}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

note() { echo "  $*"; }
bad() { echo "::error::$*"; fail=1; }

echo "Releasing $TAG, so every version reference must read $VERSION."

# ── README: the SPM snippet an integrator copies ─────────────────────────────
readme_versions=$(grep -oE 'from: "[0-9]+\.[0-9]+\.[0-9]+"' "$ROOT/README.md" | sed -E 's/from: "([^"]+)"/\1/' | sort -u || true)
if [[ -z "$readme_versions" ]]; then
  bad "README.md has no 'from: \"X.Y.Z\"' snippet to check. If the install block moved, update this script."
else
  while read -r v; do
    [[ -z "$v" ]] && continue
    if [[ "$v" == "$VERSION" ]]; then
      note "README.md install snippet: from: \"$v\"  ok"
    else
      bad "README.md installs $v, but the tag being cut is $TAG. Bump it in the release commit, not after tagging."
    fi
  done <<< "$readme_versions"
fi

# ── CHANGELOG: the top section must be this release ──────────────────────────
top=$(grep -m1 -E '^## ' "$ROOT/CHANGELOG.md" | sed -E 's/^## +//' | tr -d '\r')
if [[ "$top" == "$VERSION" ]]; then
  note "CHANGELOG.md newest section: $top  ok"
else
  bad "CHANGELOG.md's newest section is '$top', expected '$VERSION'. A release with no entry, or one still marked Unreleased, is not a release."
fi

if [[ "$fail" -ne 0 ]]; then
  echo
  echo "Nothing was published. Fix the tree, amend the release commit, then move the tag."
  exit 1
fi
echo "Tree agrees with $TAG."
