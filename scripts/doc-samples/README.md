# Doc sample compile check

`scripts/check-doc-samples.py` takes markdown files, pulls every ```swift fence
out of them, and type-checks each one against this package's own sources for
the iOS Simulator. A sample that would not compile for an integrator fails the
build.

It runs over this repository's `README.md` in CI, and the docs repository runs
it on a schedule over `docs/sdks/ios/` with this SDK checked out at its
released tag.

## Annotating a fence

The fence info string carries the annotation, after the language:

| Mark | Meaning | What is checked |
|---|---|---|
| (none) | A complete, copy-pasteable sample. | Compiles as its own module. |
| `fragment` | A snippet that needs surrounding context: a few statements, a lone expression. | Compiles, wrapped in an `async throws` function body. `import` lines are hoisted. |
| `reference` | A listing of API this SDK provides, shown so a reader can see the shape. Not for copying. | Every type it declares must exist in `Sources/`, and every property or case it lists must exist on that type. |
| `manifest` | An excerpt of a build file: `Package.swift`, an Xcode setting. | Not compiled. It is not app code. |
| `no-compile <reason>` | Last resort. The reason is required and is printed in the census. | Nothing. |

So:

    ```swift fragment
    await Relavoi.shared.events.disconnect()
    ```

`reference` is not a free pass. It is a different check, and it is the one that
would have caught `recordingEnabled` surviving in the docs for two releases
after 0.3.0 removed it.

## The prelude

A sample is written for an app that already exists, so it reaches for symbols
the SDK does not provide: `MyBackend`, `Secrets`, a `showAlert`. Those are
declared once in `prelude/`, one declaration per file, named after what it
declares.

Each sample is compiled with the prelude in scope **minus** any file whose name
the sample itself declares. That is how `call-verification.md` can both show
`BannerView` being used and, further down the page, show how to write it: the
second fence declares `BannerView`, so `prelude/BannerView.swift` is left out
of that one target.

Adding a symbol to the prelude is a decision worth making deliberately: it
means the docs invented a name and the reader is expected to supply it. Keep
the stub as thin as the sample needs.
