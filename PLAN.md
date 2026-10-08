# Recursive Agent Plan: Stremio-Addon Player for iOS

*Execution spec for an autonomous coding agent · Swift 6 / SwiftUI · iOS 17+ · v1.0 · Oct 7, 2026*

## 0. Bootstrap

Save this file as `PLAN.md` in an empty git repo on a Mac with Xcode. Give the agent this prompt:

```
You are an autonomous iOS engineer. Your spec is PLAN.md.
1. Read PLAN.md fully.
2. If STATE.md does not exist, create it from the milestone tree in section 6, all TODO.
3. Execute RUN(ROOT) exactly as defined in section 2, depth-first.
4. Do not stop to report progress. Stop only when ROOT is DONE, or when a BLOCKED node has no route around it. Then print the single question you need answered.
5. After a restart or context reset, repeat from step 1. RUN is re-entrant: it resumes at the first node that is not DONE.
```

## 1. Goal, scope, constraints

**Goal.** An iPhone-first, iPad-compatible app that installs Stremio addons by manifest URL, browses their movie catalogs, searches, shows details, lists streams from stream addons, and plays the chosen stream with resume, subtitles, Picture in Picture and AirPlay.

**v1 scope:** movies, addon management, direct-URL streams, MP4 and HLS through AVPlayer, a fallback engine for MKV and other formats, watch progress.

**Out of scope:** Stremio account sync, embedded torrent engine, series and live TV UI (models still parse them), downloads, Chromecast, tvOS and macOS.

**Constraints**

- Neutral client. Ship zero preinstalled content addons; the empty state explains how to add one by URL. Stremio's official metadata addon (Cinemeta, `https://v3-cinemeta.strem.io/manifest.json`) may be offered as a suggested install for catalogs only. The agent must not search for, install or test against third-party stream addons. All stream testing uses the local mock addon (section 7).
- Don't put `Stremio` in the app name, bundle ID or icon (trademark). Say 'works with Stremio addons' in descriptive text only.
- Addon URLs often embed user tokens. Treat them as secrets: Keychain storage, redacted in logs, never in analytics or crash output.
- Swift 6 language mode, SwiftUI, Observation (`@Observable`), `NavigationStack`, async/await. No Combine, no storyboards. Never hand-edit `.pbxproj`; generate the project with XcodeGen (`project.yml`).
- Never set global `NSAllowsArbitraryLoads`. Use the narrow ATS keys named in M2 and M5.
- `StremioKit` is Foundation-only and builds for iOS and macOS, so `swift test` runs on the host without a simulator.
- Unit tests use Swift Testing, UI tests use XCUITest. Tests may reach the network only through the localhost mock.
- A new third-party dependency needs an ADR in `docs/decisions/`. Pre-approved: one fallback player (M6) and, optionally, Nuke for image loading.
- Implement the protocol natively. ADR-001 records why not `stremio-core` via FFI; revisit only if M1 shows the protocol is more complex than section 4 says.

## 2. The recursive procedure

Every unit of work, from ROOT down to a one-function fix, is a node handled by the same procedure. ROOT's children are M0 to M8 (section 6). Node kinds: `feature`, `fix`, `research`, `decision`.

```
RUN(node):
  ORIENT    read PLAN.md, STATE.md, BLOCKERS.md, git log -10, git status
            if node is DONE: return. if it has children: continue at the first child not DONE
  CLASSIFY  atomic = one outcome, about 150 changed lines or fewer, 3 files or fewer, one command proves it
            otherwise composite
  if composite:
      kids = DECOMPOSE(node)     # 3 to 7 ordered children, each strictly smaller, each with an accept command
      write kids to STATE.md; commit 'plan: expand <id>'
      for kid in kids, in dependency order: RUN(kid)
  else:
      write the test or fixture first, implement, build, test, read your own diff
  repeat up to 3 times:
      run node.accept, then ./scripts/verify.sh
      green -> mark DONE, commit '<id>: <title>', write a 3-line handoff note in STATE.md, return
      red   -> diagnose, add 1 to 3 children of kind fix, RUN each
  BLOCK(node): mark BLOCKED, append to BLOCKERS.md (tried / error / hypotheses / the one question), return.
      The parent re-plans around it: stub, defer or pick an alternative. Escalate only if no route exists.
```

`STATE.md` holds one line per node, indented by depth. Markers: `[ ]` TODO, `[~]` DOING, `[x]` DONE, `[d]` done pending device check, `[!]` BLOCKED.

```
- [~] M2 Client and registry | accept: ./scripts/verify.sh | tries 0
  - [x] M2.1 Manifest fetch and validate | accept: swift test --filter ManifestFetchTests | tries 1
  - [~] M2.2 Registry: install, remove, reorder | composite
    - [x] M2.2.1 Normalise stremio:// to https:// | accept: swift test --filter URLNormaliseTests | tries 0
    - [ ] M2.2.2 Metadata in SwiftData, URL in Keychain | accept: swift test --filter PersistenceTests | tries 0
    - [ ] M2.2.3 Routing by type and idPrefixes | accept: swift test --filter RoutingTests | tries 0
  - [ ] M2.3 Fan-out resolver, per-addon timeout | accept: swift test --filter ResolverTests | tries 0
```

Rules that keep it terminating and sane:

- Depth cap 4 (ROOT = 0). If DECOMPOSE returns one child, treat the node as atomic. A child equal to its parent is a planning bug: re-plan.
- Same error signature twice means change strategy (research the API, simplify, stub). Never make the same attempt a third time.
- Never guess a protocol or API detail that isn't in this file. Open a `research` node, read the upstream source (Stremio/stremio-addon-sdk docs/api, Apple documentation) and record the answer in `docs/decisions/NNN-title.md`. No web access? Record the assumption as UNVERIFIED and queue a verification task for the human.
- Milestone boundary = RETRO: list what the plan got wrong, edit later milestones' hints, add discovered work as nodes, append to the Changelog at the bottom. Never edit sections 1 and 2; change section 4 only through an ADR.
- Branch per milestone (`m3-browse-ui`). Merge to main only when `verify.sh` is green. No force-push, no skipped hooks.
- Caps: 3 tries per node, 80 RUN calls per milestone, 500 overall. At a cap, stop and print a STATE.md summary.
- Sub-agents, if the platform offers them: hand a leaf node to one with this file, the node ID and a file scope. It runs the same RUN and returns the diff and verify output. The parent re-runs verify itself before marking DONE.
- Context hygiene: the handoff note after each DONE node must be enough for a fresh context to continue. Trust it over memory.

## 3. Verification gate

One command gates every node: `./scripts/verify.sh [milestone]`, created in M0. In order, stopping at the first failure:

1. `swift test --package-path Packages/StremioKit`, then the same for `PlayerKit` (host-side, seconds)
2. Start the mock addon, wait until its manifest answers 200, stop it on exit
3. `xcodegen generate`
4. `xcodebuild test` for the app scheme on the newest available iPhone simulator (resolve it from `xcrun simctl list devices available`, never hardcode a device name), warnings as errors. Per-node runs skip the UI test target; milestone runs include it
5. `swiftlint --strict` if installed, otherwise log that it was skipped
6. Print a one-line summary and exit non-zero on any failure

For UI nodes, also run `xcrun simctl io booted screenshot shots/<id>.png`, open the image and check it against the node's requirements. Commit screenshots at milestone boundaries only.

## 4. Stremio addon protocol cheat sheet

Verify against upstream in M1 and correct this section by ADR if it is wrong.

- **Manifest** at `<base>/manifest.json`. Fields: `id`, `name`, `version`, `description`, `resources`, `types`, `catalogs`, optional `idPrefixes`, `logo`, `background`, `behaviorHints` (`configurable`, `configurationRequired`, `adult`, `p2p`). A `resources` entry is a string (`stream`) or an object (`name`, `types`, `idPrefixes`). `<base>` is the manifest URL minus `/manifest.json`. Install links use `stremio://host/path/manifest.json`; swap in `https://` (or `http://` when the user typed a LAN address).
- **Requests:** `<base>/<resource>/<type>/<id>.json`, and with extras `<base>/<resource>/<type>/<id>/<k>=<v>&<k>=<v>.json` with percent-encoded values. Resources: `catalog`, `meta`, `stream`, `subtitles`, `addon_catalog`. Catalog extras: `search`, `genre`, `skip`; the catalog's `extra` array says which are supported or required (older manifests use `extraSupported` and `extraRequired`).
- **Responses:** `{metas: [...]}`, `{meta: {...}}`, `{streams: [...]}`, `{subtitles: [...]}`. Real addons are sloppy: numbers arrive as strings, fields go missing, arrays are null. A bad item is dropped; it never fails the whole response.
- **Stream object:** one source field: `url`, `infoHash` (with `fileIdx`, `sources`), `ytId`, `externalUrl`, or newer archive and usenet forms (`nzbUrl`, `rarUrls` and similar). Plus `name`, `description` (legacy `title`), `subtitles`, and `behaviorHints`: `notWebReady`, `bingeGroup`, `proxyHeaders` (`request`, `response`), `videoHash`, `videoSize`, `filename`, `countryWhitelist`.
- **Subtitles:** `<base>/subtitles/movie/<id>/videoHash=..&videoSize=..&filename=...json` returns `{subtitles: [{id, url, lang}]}`; `lang` is usually ISO 639-2.
- **Routing:** an addon is eligible for (resource, type, id) when its manifest lists that resource for that type and, if `idPrefixes` exists (resource level first, then top level), the id starts with one of them. No prefixes means it matches everything.
- **Ids:** movies are normally IMDb ids (`tt1234567`). Episodes are `<imdbId>:<season>:<episode>`. Parse both now; series UI comes later.
- **Container detection:** URLs often have no extension. Use Content-Type plus the first bytes of a ranged GET: `1A 45 DF A3` is Matroska or WebM, `ftyp` at offset 4 is MP4 or MOV, `#EXTM3U` is HLS.
- **Stream handling policy:**
  - `url` to MP4, MOV, M4V or HLS without `notWebReady`: AVPlayer
  - `url` to MKV, AVI or other containers, audio AVPlayer can't decode (DTS, TrueHD), or `notWebReady: true`: fallback engine (M6). Before M6, show 'unsupported format' and offer the next stream
  - `infoHash`: only when the user has set a Stremio-compatible streaming server URL in Settings (research its HTTP route in an ADR first). Otherwise hide it with a hint that it needs a streaming server or an addon that returns direct URLs
  - `externalUrl`, `ytId`: open outside the app
  - nzb and archive forms: unsupported in v1, filtered out

## 5. Architecture target

```
App/                    @main, DI container, NavigationStack routes
Packages/
  StremioKit/           models, URL builder, lenient decoding, AddonClient, Registry, StreamResolver
  PlayerKit/            PlaybackEngine protocol, AVEngine, FallbackEngine, SRT and VTT parsers
  Persistence/          SwiftData stores, Keychain wrapper
  Features/             Board, Discover, Search, Detail, StreamPicker, Player, Addons, Settings
Tools/MockAddon/        zero-dependency Node server and fixture generator
scripts/verify.sh
docs/decisions/         ADRs, DEVICE_CHECKLIST.md, licenses.md
PLAN.md  STATE.md  BLOCKERS.md
```

- `PlaybackEngine` is a protocol (load, play, pause, seek, audio and subtitle tracks, state as `AsyncStream`) so AVPlayer and the fallback engine are interchangeable.
- `PlayerKit` imports AVFoundation only, no UIKit, so it builds and tests on macOS.
- Stream resolution yields an `AsyncStream` of results so the UI fills in as each addon answers.
- External subtitles are parsed and drawn as an overlay synced to the engine clock. Don't rely on AVPlayer side-loading them.

## 6. Milestone tree (level-1 nodes)

Each milestone is composite: DECOMPOSE it with RUN. The bullets are candidate children, not a script.

**M0 Bootstrap.** Run `xcodebuild -version`, `swift --version`, `xcrun simctl list devices available`, `node --version`; check that XcodeGen, ffmpeg and SwiftLint are installed. If macOS or Xcode is missing, stop and say so. Create the XcodeGen project, local packages, `verify.sh`, mock addon skeleton, ADR-001 (stack and native-protocol choice). *Accept:* `./scripts/verify.sh` green on an empty app; app launches in the simulator; screenshot saved.

**M1 Protocol core (StremioKit).** Models, lenient decoders, URL builder, manifest validation, `stremio://` normalisation. At least 10 manifest fixture variants (string and object resources, top-level and resource-level idPrefixes, legacy extra fields, missing types, null arrays). *Accept:* 90% line coverage in the package; mutated fixtures never crash the decoder; URL builder round-trips spaces, `&`, `=`, `/` and unicode.

**M2 Client and registry.** Manifest fetch, install, remove, enable, reorder; routing; 8 s per-addon timeout; bounded retries with backoff on idempotent GETs; response size cap; redirects; URLCache; fan-out as AsyncStream. Metadata in SwiftData, URLs in Keychain. Info.plist: `NSAllowsLocalNetworking` and `NSLocalNetworkUsageDescription` for LAN addons. *Accept:* integration tests on the mock: a slow addon doesn't delay a fast one; 500s, invalid JSON, oversized bodies and redirects stay isolated to their addon; captured logs contain no URL tokens.

**M3 Browse UI.** Board (catalog rows), Discover (genre filters, `skip` pagination), Search (debounced, multi-addon, per-addon error chips), Detail (`meta`, falling back to catalog preview data), Addons screen (install by URL or paste, remove, reorder, view manifest, empty state). *Accept:* XCUITest flows pass on the mock; screenshots reviewed at iPhone SE, Pro Max and iPad sizes; no clipping at Dynamic Type AX5; `performAccessibilityAudit()` clean.

**M4 Streams.** Resolver (fan-out, dedupe by url or infoHash), container sniffing, quality parsed heuristically from `name` and `description`, ranking (natively playable first, then resolution; user preferences land in M7), picker grouped by addon with incremental loading, `bingeGroup` continuity. *Accept:* ranking unit tests from fixtures; UI test shows the first result before the slowest addon answers.

**M5 Playback (AVPlayer).** `PlaybackEngine` and `AVEngine`; player UI (gestures, scrubber, audio and subtitle menus); subtitle overlay with offset control; `proxyHeaders` (ADR: undocumented `AVURLAssetHTTPHeaderFieldsKey` vs documented `AVAssetResourceLoaderDelegate`); PiP; AirPlay; background audio and Now Playing remote commands; interruptions; auto-advance to the next stream on failure; resume (save every 10 s and on exit, watched at 90%). Info.plist: `NSAllowsArbitraryLoadsForMedia` and the audio background mode; check each key against current Apple docs. *Accept:* simulator plays the mock MP4 and HLS, time advances, seek lands within 1 s, subtitles render at the right cue times; progress unit tests. PiP, AirPlay, lock-screen controls and background audio can't be verified in the simulator: mark those `[d]` and list them in `docs/DEVICE_CHECKLIST.md`.

**M6 Format coverage.** ADR comparing MPVKit, VLCKit and KSPlayer on license, App Store compatibility, binary size, HDR and Dolby Vision, ASS and PGS subtitles, maintenance, SPM support. Implement `FallbackEngine` behind the same protocol and wire the routing policy from section 4. *Accept:* generated MKV (H.264 + AC3) and MKV with DTS audio play in the simulator; binary size delta reported; license obligations in `docs/licenses.md`.

**M7 Library and settings.** Library, continue watching, watched flags; settings for default subtitle language, preferred quality, streaming server URL, clear data. *Accept:* persistence tests including a schema migration; a test greps captured logs for the mock's token and finds none.

**M8 Hardening and release.** Empty, offline and error states; `PrivacyInfo.xcprivacy`; String Catalog scaffolding; app icon; launch-time baseline (`XCTApplicationLaunchMetric`); leak pass; App Review notes (neutral client, no bundled addons, how users add content). *Accept:* `verify.sh` milestone run green; `xcodebuild archive` succeeds; signing steps written out for the human.

## 7. Mock addon and fixtures

`Tools/MockAddon/server.js`: Node 18+, zero dependencies. Serves a catalog addon and a stream addon on separate ports, ids prefixed `mock:`. Flags simulate a 3 s delay, HTTP 500, invalid JSON, a 6 MB body, a 302 redirect, null arrays and numbers as strings.

Media is generated offline with ffmpeg by `Tools/MockAddon/make-fixtures.sh` so tests don't need the internet: 10 s clips from `testsrc` and `sine` as MP4 (H.264/AAC), HLS (2 s segments), MKV (H.264/AC3) and MKV (H.264/DTS via `-c:a dca -strict -2`, if available), plus SRT and VTT subtitle files with known cue times. Don't commit generated media.

## 8. Risks and planned responses

- **AVPlayer can't open MKV or DTS:** fallback engine behind the same protocol (M6).
- **Torrent-only sources:** out of scope natively; supported only through a user-supplied streaming server or addons that return direct URLs.
- **App Review (Guideline 5.2, intellectual property) and trademark:** neutral client, no bundled addons, no 'Stremio' in name or icon. The distribution route (TestFlight, App Store, personal build) is the human's decision; the agent only prepares the notes.
- **Fallback-player licensing (LGPL or GPL):** the M6 ADR states the obligations; the human signs off before release.
- **Addon schema drift:** lenient decoding, mutated fixtures, per-item error isolation.
- **Tokens in URLs:** Keychain, redaction, a log-grep test.
- **Simulator can't verify some features:** `[d]` plus a checklist; never silently DONE.
- **Agent drift or loops:** caps and stuck detection in section 2.

## 9. Escalate to the human when

- Signing, provisioning, App Store Connect or a paid account is needed
- A licensing or legal question has no clear answer in an ADR
- Progress would require real third-party addons or content
- A node is BLOCKED and its parent can't re-plan around it
- A cap in section 2 is hit

## 10. Definition of done (ROOT)

- M0 to M8 are DONE, or `[d]` with entries in `docs/DEVICE_CHECKLIST.md`
- `./scripts/verify.sh milestone` is green on a clean checkout
- README covers build and run, adding an addon, running the mock, known limitations
- `BLOCKERS.md` is empty, or every entry is resolved or deferred with a reason
- The Changelog below matches what was built

## Changelog

- v1.0: initial plan
- v1.1 (build record, appended by the agent that built it; sections 0-10 above are unchanged):
  - Built on an Ubuntu host with no Xcode (BLOCKERS B-001). Verification was split: StremioKit, PlayerKit logic, Persistence contracts, Features view models and the
    mock addon are compiled and tested for real with Swift 6.3.3 on Linux; SwiftUI, SwiftData, Keychain, AVFoundation, the app target and the UI tests were syntax-checked only
    and are marked `[d]` (ADR-002). `verify.sh milestone` therefore refuses to pass on Linux without `ALLOW_HOST_ONLY=1`.
  - One working branch (`claude/blusion-github-e2e-sqx5r4`) instead of a branch per milestone, because the operator pinned it. Milestone commits are `M<n>: <title>`.
  - GitHub write access was denied (B-002): nothing was pushed, so the macOS CI workflow has not run.
  - The fallback player (M6) is opt-in (`FALLBACK=1`) instead of default: the MPVKit pin could not be compiled here, and the default build stays free of third-party code (ADR-006).
  - Added beyond the plan: `scripts/check-project-spec.py` (ATS, trademark, GPL and privacy-manifest guards), `scripts/archive.sh`, `scripts/leaks.sh`, `scripts/extract-strings.py`,
    ADRs 001-007, `docs/MAC_FIRST_RUN.md`, `docs/RELEASE.md`, `docs/APP_REVIEW_NOTES.md`, `docs/LOCALIZATION.md`.
  - Final host counts: StremioKit 213 tests (96.45% line coverage), PlayerKit 76, Persistence 5, Features 100, mock addon 13.
- v1.2 (continuation, 2026-10-08; sections 0-10 above remain unchanged):
  - Saved interrupted work first as `7331a0e` (`checkpoint`); preserved original agent directories and briefs in local `build/checkpoint-agent-work.tar.gz`.
  - Reviewed all 20 original agent briefs; combined overlapping work and completed the remaining widget, settings, search, rating, and UI wiring using existing patterns.
  - Current target is iOS 26.0 with Mac Catalyst. Cinemeta is installed once for metadata; stream addons remain user-supplied under Settings → Addons.
  - Added adaptive TV-style screens, Infuse handoff/progress updates, customizable Home widgets and Fusion import/export, poster ratings, persistent recent searches, and title context actions.
  - Fixed cache invalidation/refresh behavior and made missing-fixture and missing-simulator verification explicit. A simulator-free run cannot silently satisfy the full milestone gate.
  - Updated README and Mac/reviewer notes to match current behavior. Every original agent is mapped in `docs/CLAUDE_HANDOFF.md`.
  - Validation: StremioKit 416, PlayerKit 84, Persistence 12, Features 273; 10 media-fixture skips, no failures. Mock addon 12 passed, 1 media skip. Generic iOS/Catalyst compilation and recorded Mac layout checks pass; no simulator runtime is installed.
- v1.3 (requested follow-up, 2026-10-08):
  - Separate subagents added Trakt device-code sign-in and explicit add-only watchlist/history sync, five review-site icons/links with optional OMDb/TMDB scores, and pointer/focus feedback.
  - Fixed Home cancellation/re-entry, stale Settings overwriting new account credentials, launch navigation timing, and Settings Done contrast; regression tests and recorded route/layout checks pass. Live credentialed service checks need user API credentials.
  - Signed builds and installation succeed on the connected iPhone 17; an earlier build launched. Final launch verification awaits an unlocked phone. Full device playback checks and distribution remain open.
  - Removed 3.72 GiB of old Blusion build caches, retaining the checkpoint archive and current builds. No push.
