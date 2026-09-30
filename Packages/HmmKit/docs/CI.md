# The hmm. CI recipe

Every hmm. app is built without a Mac: GitHub Actions does all Apple builds, the developer installs the CI `.ipa`
with Sideloadly until App Store enrollment is live. This is the recipe the apps share.

## Project

- **XcodeGen** `project.yml` generates the Xcode project in CI (`brew install xcodegen && xcodegen generate`); the
  `.xcodeproj` is never committed.
- **Swift packages** hold the code: `<App>Core` (pure Swift, Linux-testable), `<App>Engine`, `<App>Features`, and
  `HmmKit` (this repository, as a `git subtree` at `Packages/HmmKit`).
- **Swift 6 language mode**, strict concurrency, warnings as errors in CI.

## Jobs (in order)

1. **Lint** on Ubuntu: SwiftFormat `--lint`, SwiftLint `--strict` (limits: file 500 lines, type body 350,
   function 60, cyclomatic complexity 12).
2. **Core on Linux** in the `swift:6.1` container: `swift test --enable-code-coverage`, then `llvm-cov report` with a
   ≥ 80 % line coverage gate.
3. **App on macOS** (`runs-on: xcode-27`, `DEVELOPER_DIR` pinned): pick the newest iPad simulator, `xcodebuild test`
   (unit, render golden images, UI smoke tests), export `xcresult` attachments (screenshots, renders) as an artifact.
4. **Release** runs only after CI succeeded on the same commit (`workflow_run` with `conclusion == 'success'`), never
   on a commit whose message contains `[build-only]`: unsigned device build, ad-hoc `codesign`, `.ipa` attached to a
   GitHub Release for `v*` tags. When App Store Connect API secrets exist, the same workflow uploads to TestFlight.

## Locally on Windows

Docker Desktop runs everything that doesn't need Apple SDKs:

```sh
docker run --rm -v "$PWD:/work" -w /work swift:6.1 swift test                 # pure packages
docker run --rm -v "$PWD:/work" -w /work ghcr.io/realm/swiftlint:0.65.1 swiftlint lint --strict
docker run --rm -v "$PWD:/work" -w /work ghcr.io/nicklockwood/swiftformat:0.63.0 --lint .
```

## `[build-only]`

A commit message containing `[build-only]` skips the simulator tests (feature work in progress). Such a commit is
never tagged and never released.
