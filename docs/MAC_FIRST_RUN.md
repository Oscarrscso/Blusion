# First run on a Mac

The Linux agent that wrote this repo could not run Xcode (BLOCKERS B-001) and could not push to GitHub to use CI (B-002). Everything
under `Packages/*/Sources/**` that builds on Linux was compiled and tested for real (Swift 6.3.3, about 400 tests). **Apple-only code was
only syntax-checked.** That is: SwiftUI views, SwiftData stores, the Keychain store, `AVEngine`, the resource loader, Now Playing,
the `App/` target, the XCUITests and the optional MPV glue. Expect a short round of compile fixes. This page makes that round quick.

## Commands, in order

```bash
brew install xcodegen swiftlint ffmpeg xcbeautify node     # node 18+, ffmpeg for the media fixtures
git checkout claude/blusion-github-e2e-sqx5r4
./scripts/verify.sh                 # host layer first: must be green exactly as on Linux
xcodegen generate                   # writes Blusion.xcodeproj (git-ignored)
open Blusion.xcodeproj              # or: ./scripts/verify.sh milestone for the whole gate
```

`./scripts/verify.sh milestone` runs, on a Mac: package tests, `xcodegen`, `xcodebuild test` on the newest iPhone simulator (unit and UI tests
against the mock addon), `swiftlint --strict`, then an unsigned `xcodebuild archive` with checks on what was archived (`scripts/archive.sh`).
Optional afterwards: `./scripts/screenshots.sh` (layouts at three sizes), `./scripts/leaks.sh` (leak sampling), `FALLBACK=1 ./scripts/verify.sh milestone`
(the opt-in MPV engine), `./scripts/size-report.sh` (binary size delta).

If you push the branch, `.github/workflows/ci.yml` does the same on GitHub-hosted runners; read failures with the job log.

## Where compile errors are most likely (most likely first)

1. **Swift 6 strict concurrency in Apple-only files.** `@Observable` view models used from `@State`, `Binding(get:set:)` closures that touch a
   `@MainActor` model (`SettingsView`, `DetailView`), `Task { await model... }` inside view builders. Fix by marking the closure `@MainActor` or hopping
   with `MainActor.assumeIsolated` only where the call is provably on the main thread.
2. **`PlayerKit/AV/AVEngine.swift`, `HeaderResourceLoader.swift`, `NowPlayingController`.** AVFoundation's async/KVO APIs and
   `MPRemoteCommandCenter` handlers are the most version-sensitive code in the repo. The portable logic (HLS rewriting, header tables,
   command mapping) is separate and tested; only the glue can fail.
3. **`Persistence/*`.** SwiftData `@Model` under Swift 6, the `VersionedSchema` / `SchemaMigrationPlan` pair (`BlusionSchemaV1` to `V2`, lightweight
   stage) and `ModelContainer` creation. `SwiftDataStoreTests` contains the V1 to V2 migration test: run it first.
4. **`Features/Views/PlayerSurface.swift`.** `AVPlayerLayer` hosting, `AVPictureInPictureController`, `AVRoutePickerView`.
5. **`App/`.** `AppEnvironment` wiring (`SwiftData*` stores, `KeychainSecretStore`, `DefaultsSettingsStore`).
6. **XCUITests.** Identifier typos or elements that are `otherElements` instead of `buttons` on a given iOS version. The accessibility
   identifiers are all `screen.element` strings set in the views.
7. **`Packages/FallbackPlayer`** (opt-in): the MPVKit version pin (`from: "0.40.0"`) and the libmpv calls were never compiled. Ignore unless you build with `FALLBACK=1`.

The host tests already pin the behaviour the Apple glue must keep (view models, coordinator, header-loader helpers, store contracts), so
fixing a compile error should never require changing a test. If it does, that is a design bug worth a note in `STATE.md`.

## What the simulator still cannot prove

`docs/DEVICE_CHECKLIST.md`: Picture in Picture, AirPlay, lock-screen controls, background audio, real hardware decode, the local-network
prompt, and a Dynamic Type / VoiceOver pass by a person.

## Known unknowns

- `StreamingServerRoute` (ADR-004) was written from documentation only. Test it against a streaming server you run.
- Binary size delta of the fallback engine is unmeasured.
- The `UserDefaults` privacy-manifest reason (`CA92.1`) and the ATS keys are chosen from Apple's documentation, not from an App Review round trip.
