# Relavoi iOS SDK

Swift SDK. Published for client applications to depend on.

## Before any work in this repo

Before any work in this repo: git fetch origin, then check whether origin/main
has commits you don't have. If it does, list them (author, message, files
touched) in your report before building. Fetch again right before you push, in
case something landed while you worked. After a long gap between sessions,
assume something has changed.

This repository is public and is what integrators read. A published SDK
version is not retractable once a client has resolved it, so a breaking change
waits for the next minor rather than going out as a patch.

## Commit identity

Author and commit as `admin@cicanda.com`.

It is set per repository, `git config user.email admin@cicanda.com`, and not
globally. The global identity is a personal address, and before this was
pinned three different author identities had already reached this history:
`Kalu Chinecherem <kaluchinecherem8@gmail.com>`,
`Chinecherem Kalu <nechecodes@gmail.com>` and
`Kalu Chinecherem <nechecodes@gmail.com>`. Leave `user.name` as it is and
change only the address. Existing history is not rewritten.

Never add a Claude attribution line, a co-author trailer or a generated-by
note to a commit message or a pull request description. Never add
`Co-Authored-By`, `Generated with` or any other Claude or Anthropic
attribution to a commit or a PR.

The check, anchored because a trailer is always at the start of its own line
and because a prose mention of the forbidden string is not itself a violation:

```
git log --all --format=%B | grep -icE '^(co-authored-by|generated with)'
```

It answers 0 as of 2 November 2026, across every ref of every Relavoi repo,
and no author or committer has ever been Claude or Anthropic.
