# Blusion

An iPhone-first, iPad-compatible player for **Stremio-protocol addons**: install an addon by its manifest URL, browse its catalogs,
search, open a title, pick a stream and play it with resume, subtitles, Picture in Picture and AirPlay.

Blusion is a **neutral client**. It ships **no content addons, no catalogs and no default sources**; users add their own by URL. It has
no accounts, no backend and no analytics. Addon links often contain secrets, so they are kept in the Keychain and never written to a log.

> **Status: written and tested on Linux, not yet built with Xcode.** The protocol core, view models, playback coordinator, stores'
> contracts and the mock addon are compiled and tested for real (about 400 tests). The SwiftUI views, SwiftData/Keychain stores, AVPlayer
> engine, app target and UI tests were only syntax-checked, because the agent that wrote them had no Mac. Start with
> [`docs/MAC_FIRST_RUN.md`](docs/MAC_FIRST_RUN.md). See [Known limitations](#known-limitations) and `STATE.md` for exact status.

## Requirements

| To... | You need |
|---|---|
| build and run the app | macOS, Xcode 16+ (Swift 6 language mode, iOS 17 SDK), [XcodeGen](https://github.com/yonaskolb/XcodeGen) |
| run the host tests and the mock addon | Swift 6 toolchain (macOS or Linux), Node 18+, `ffmpeg` (optional: only for the media fixtures) |
| lint | SwiftLint (optional on Linux: a basic whitespace check runs instead) |

```bash
brew install xcodegen swiftlint ffmpeg node
```

## Build and run

The Xcode project is generated and never committed (`project.yml` is the source of truth).

```bash
xcodegen generate            # writes Blusion.xcodeproj
open Blusion.xcodeproj       # pick an iPhone simulator, Run
```

Before it runs on a device, set your own bundle id and team in `project.yml` (the bundle id `app.blusion.player` is a placeholder);
see [`docs/RELEASE.md`](docs/RELEASE.md).

On first launch the app is empty by design. Home explains how to add an addon.

## Adding an addon

1. Get an addon's **manifest URL** from whoever runs it. It looks like `https://example.com/<anything>/manifest.json`
   or `stremio://example.com/<anything>/manifest.json`. Treat it like a password: it often embeds a personal token.
2. In Blusion open the **Addons** tab, paste the link and tap **Install**. Blusion downloads and checks the manifest and shows what the
   addon offers (catalogs, streams, subtitles). A malformed or unsupported manifest is rejected with a plain explanation.
3. Catalogs appear on **Home** and **Discover**, titles are found by **Search**, and **Detail** lists streams from every installed
   stream addon at once, best first. Addons can be reordered, disabled or removed on the same tab; removing one also deletes its saved link.

Streams: direct `http(s)` video plays in the system player. Streams that need request headers are supported through a documented
`AVAssetResourceLoader` path (`docs/decisions/005-proxy-headers-and-media-keys.md`). Torrent (`infoHash`) streams need a streaming server **you run
yourself**, set under *Settings > Streaming server*; Blusion contains none. MKV and some audio formats need the optional fallback player (below).

## Running the mock addon

A zero-dependency Node server plays both roles (catalog addon and stream addon) with generated test media. It is what every integration
and UI test runs against.

```bash
./Tools/MockAddon/make-fixtures.sh        # needs ffmpeg; generates MP4, HLS, MKV (AC3, DTS), SRT, VTT into a git-ignored folder
node Tools/MockAddon/server.js            # catalog on :7001, stream addon on :7002
```

In the app, install `http://127.0.0.1:7001/anything/manifest.json` (simulator) for catalogs and `http://127.0.0.1:7002/anything/manifest.json`
for streams. Any path segment before `manifest.json` is treated as a user token, which is how the privacy tests prove tokens never reach logs.
Segments like `flag-slow`, `flag-err500`, `flag-badjson`, `flag-big`, `flag-redirect` or `flag-nulls` make that addon misbehave on purpose; the full list is
at the top of `Tools/MockAddon/server.js`.

## Verifying

```bash
./scripts/verify.sh              # per change: package tests (warnings are errors), project spec + syntax check, mock addon tests, lint
./scripts/verify.sh milestone    # adds, on macOS: xcodegen, xcodebuild test (unit + UI on a simulator), swiftlint --strict, unsigned archive
./scripts/coverage.sh StremioKit 90          # line-coverage gate for the protocol core
./scripts/screenshots.sh         # UI screenshots at three device sizes (macOS)
./scripts/leaks.sh               # simulator leak sampling (macOS)
FALLBACK=1 ./scripts/verify.sh milestone     # the same, with the opt-in fallback player built in
```

On Linux `verify.sh` prints exactly which steps it skipped, and `milestone` refuses to pass there unless you set `ALLOW_HOST_ONLY=1`, so a
Linux green is never mistaken for a full green (`docs/decisions/002-verification-topology.md`). `.github/workflows/ci.yml` runs both layers on
GitHub-hosted runners when the branch is pushed.

## Layout

```
App/                    @main, dependency wiring, privacy manifest, string catalogs, app icon
Packages/
  StremioKit/           models, URL normaliser and builder, lenient decoding, AddonClient, registry, browse and stream services, settings/library contracts
  PlayerKit/            PlaybackEngine protocol, coordinator (failover, resume), subtitles, progress, AVPlayer engine, fallback-engine adapter
  Persistence/          SwiftData stores (schema V1 to V2 migration), Keychain secret store
  Features/             view models (no UI imports, tested on Linux) and the thin SwiftUI views on top
  FallbackPlayer/       OPT-IN MPV (LGPL) backend; not part of the default build
Tools/MockAddon/        zero-dependency Node server and fixture generator
scripts/                verify, coverage, archive, screenshots, leaks, enable-fallback, lint, project-spec checks
docs/                   decisions (ADRs 001-007), licenses, device checklist, review notes, release steps, first Mac run, localization
PLAN.md  STATE.md  BLOCKERS.md
```

Design rules worth knowing before changing anything:

- Logic lives in packages and view models so it can be tested without a simulator; SwiftUI views stay thin.
- Addon URLs are secrets: only the Keychain stores them, and every log line goes through `Redactor`. `PrivacyTests` runs a whole session and greps every log
  and every store for the mock's token.
- Decoding is lenient and per-item: one broken item or addon never blanks a screen.
- Anything the Linux host or the simulator cannot prove is marked `[d]` in `STATE.md` and listed in `docs/DEVICE_CHECKLIST.md`; it is never silently "done".

## Optional fallback player

AVPlayer cannot open MKV or DTS. An opt-in engine built on MPVKit (LGPL build) plays them behind the same `PlaybackEngine` protocol. It is off by
default because it adds third-party code, binary size and license obligations (`docs/decisions/006-fallback-player.md`, `docs/licenses.md`).
`./scripts/enable-fallback.sh` generates a project that includes it; the MPVKit version pin and the libmpv glue were never compiled by the agent
that wrote them.

## Known limitations

- **Never built with Xcode by its author.** Expect a short round of compile fixes in the Apple-only files on the first Mac run (`docs/MAC_FIRST_RUN.md`
  lists them in order of likelihood). The GitHub Actions workflow has not run either: pushing was denied (`BLOCKERS.md` B-002).
- **Needs a person on a real device** for Picture in Picture, AirPlay, lock-screen controls, background audio, hardware decode, the local-network
  prompt, and VoiceOver / largest Dynamic Type passes: `docs/DEVICE_CHECKLIST.md`.
- **Streaming server route is unverified** (`docs/decisions/004-streaming-server-route.md`): it was written from documentation, not tested against a real server.
- **Subtitles:** SRT and WebVTT from addons are supported. Styled formats (ASS) and bitmap subtitles (PGS) need the fallback player.
- **Header-protected streams** use `AVAssetResourceLoader`; HLS playlists are rewritten to carry headers. Exotic DRM or token schemes are out of scope.
- **Addon manifests whose URL carries a query string are rejected** (the protocol builds paths by appending to the manifest's base).
- **English only.** The string-catalog scaffolding is in place (`docs/LOCALIZATION.md`).
- **iPhone-first.** iPad runs the same layout adapted by SwiftUI; there is no tvOS or macOS target and no sync between devices.
- **Distribution is not set up.** No signing, bundle id or App Store Connect record exists; the steps are in `docs/RELEASE.md`, and reviewer notes
  (neutral client, how users add content) are drafted in `docs/APP_REVIEW_NOTES.md`. Legal and licensing questions are flagged for a human in `docs/licenses.md`.

## Project documents

| File | What it is |
|---|---|
| `PLAN.md` | the plan this repo was built from (only its Changelog is edited) |
| `STATE.md` | milestone tree with status markers and per-milestone handoff notes |
| `BLOCKERS.md` | what blocked the work, what was tried, what is still open |
| `docs/decisions/` | ADRs: stack, verification topology, protocol facts, streaming server, proxy headers and ATS, fallback player, offline and privacy manifest |
