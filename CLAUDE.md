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

## After any push, check this repository's CI before pushing anything else

Push, then check the run. Not at the end of the session, not "it'll be fine":
before the next push to this repository.

```
gh run list --repo cicanda/relavoi-ios-sdk --branch main --limit 1
```

And at the end of a round, every repository at once:

```
relavoi-infra/scripts/ci-status.sh
```

It prints the latest default-branch result for all nine and exits non-zero if
any is failing, cancelled or still running. **Its output goes at the top of the
report. A report does not say "green" without it.**

This is a rule because it has been broken twice in one week, the same way both
times. relavoi-backend sat red on main for two days behind a lint error a
narrower local command did not catch, and the report said zero lint errors.
relavoi-infra's terraform-plan failed for a day while four commits were pushed
through it, because a plan-only role was missing a read; the run ended in an
AccessDenied nobody opened, and because Terraform could not refresh the bucket
the plan also proposed replacing the backups.

Both were one command away. The reason neither got run is that the work felt
finished, and a push feels like the end of it. It is not: the push is where
the check starts.

An in-progress run is not a pass. Wait for it.

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

## README code samples are compiled

CI compiles every ```swift fence in README.md against this working tree, and the
docs repository runs the same script over the docs site's pages for this
platform on a schedule, with this SDK checked out at its newest tag.

A fence that is not a complete copy-pasteable sample says so in its info
string: `fragment`, `reference`, `manifest`, or `no-compile <reason>`.
Anything unannotated has to compile. The marks, and the prelude of app-side
symbols the samples assume, are documented in scripts/doc-samples/README.md.

So a public API change here is not finished until the README and the docs
pages for it compile again. That is the point: 0.3.0 removed two parameters
from `create` and three SDKs' docs kept passing them for two releases.
