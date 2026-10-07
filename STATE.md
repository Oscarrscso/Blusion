# STATE

Markers: `[ ]` TODO, `[~]` DOING, `[x]` DONE, `[d]` done pending device/macOS check, `[!]` BLOCKED.

Verification topology (see ADR-002): host packages and the mock addon are verified on the
Linux agent host with `./scripts/verify.sh`; everything that needs Xcode (app target, SwiftUI,
SwiftData, Keychain, AVFoundation) is verified by the `macos` job in `.github/workflows/ci.yml`
on the same branch. `[d]` means "written, host-verified where possible, awaiting the macOS/device check".

- [~] ROOT Blusion v1 | accept: ./scripts/verify.sh milestone | tries 0
  - [~] M0 Bootstrap | composite
    - [x] M0.1 Probe toolchain, route around missing Xcode (B-001, ADR-002) | accept: swift --version && node --version
    - [x] M0.2 Mock addon, fixtures generator, node tests | accept: cd Tools/MockAddon && node --test test/server.test.js | tries 2
    - [x] M0.3 Four local packages, verify.sh, coverage.sh, lint-basic.sh | accept: ./scripts/verify.sh | tries 0
    - [d] M0.4 XcodeGen project, app skeleton, UI launch test, CI workflow | accept: macOS CI `verify.sh milestone` | tries 0
  - [x] M1 Protocol core (StremioKit) | accept: ./scripts/coverage.sh StremioKit 90 | tries 1
    - [x] M1.1 Lenient decoding helpers, redaction, logging | accept: swift test --filter LenientDecodingTests
    - [x] M1.2 Models: manifest (routing, validation), meta, stream, subtitle, content id | accept: swift test --filter ManifestDecodingTests
    - [x] M1.3 URL normaliser, request builder/parser | accept: swift test --filter URLNormaliseTests
    - [x] M1.4 18 manifest + 11 response fixtures, mutation tests | accept: swift test --filter MutationTests
  - [d] M2 Client and registry | accept: swift test --filter MockIntegrationTests && RegistryTests | tries 1
    - [x] M2.1 HTTP transport (size cap, redirects, cancel), deadline, AddonClient (retries, status map) | accept: swift test --filter AddonClientTests
    - [x] M2.2 Registry: install/remove/enable/reorder/routing/updates, stores protocols + in-memory | accept: swift test --filter RegistryTests
    - [x] M2.3 FanOut AsyncStream; isolation, timeout, token-free logs proven against the mock | accept: swift test --filter MockIntegrationTests
    - [d] M2.4 SwiftData AddonStore + Keychain SecretStore, Info.plist ATS/local-network keys | accept: macOS CI (PersistenceTests, BlusionTests)
  - [d] M3 Browse UI | accept: macOS CI `verify.sh milestone` (AppFlowTests) | tries 1
    - [x] M3.1 BrowseService: catalog rows, genre + skip paging, multi-addon search, detail with fallback | accept: swift test --filter BrowseServiceTests
    - [x] M3.2 View models: Board, Discover, Search (debounce, error chips), Detail, Addons | accept: swift test --package-path Packages/Features
    - [d] M3.3 SwiftUI views (tabs, poster grid, Detail, Addons incl. empty state + suggestion) | accept: swiftc -parse + macOS CI
    - [d] M3.4 XCUITest flows on the mock, accessibility audit, AX5, screenshots script (SE / Pro Max / iPad) | accept: macOS CI, scripts/screenshots.sh
  - [ ] M4 Streams | composite
  - [ ] M5 Playback (AVPlayer) | composite
  - [ ] M6 Format coverage | composite
  - [ ] M7 Library and settings | composite
  - [ ] M8 Hardening and release | composite

## Handoff notes
(append a 3-line note after each DONE node)

- M0.2 done: `Tools/MockAddon/server.js` (ports 7001 catalog / 7002 stream; `--port 0` for ephemeral), flags are path segments `flag-<name>`,
  other prefix segments are user tokens. Media from `make-fixtures.sh` (mp4, hls, mkv ac3, mkv dts, srt, vtt). 13 node tests green.
- M0.3 done: Swift 6.3.3 at /opt/swift (symlinked in /usr/local/bin). verify.sh on Linux prints SKIPPED for xcodegen/xcodebuild and
  `milestone` fails without Xcode unless ALLOW_HOST_ONLY=1. Packages build with `-Xswiftc -warnings-as-errors`.
- M1 done: 80 tests, 98.56% line coverage (scripts/coverage.sh). Public API: ResponseDecoder.{manifest,catalog,meta,streams,subtitles},
  AddonURLNormaliser.normalise -> AddonLocation, AddonRequestBuilder.url/parse, Manifest.supports/validate, Redactor, AddonLogger/MemoryLogSink.
  Decisions: query strings in addon URLs are rejected; empty idPrefixes = no restriction; manifest without any types accepts all types.
- M2 done on host: 47 StremioKit-adjacent tests added (client 20, mock integration 12, registry 15), coverage 97.95%. FOUND AND FIXED a real bug:
  per-task state was a struct copied on every received chunk (quadratic for big bodies, held the lock, and tripped a swift-corelibs
  redirect assertion on Linux). Pending state is now a class. SwiftData/Keychain stores and plist keys are [d] (macOS only).
  Gotchas: Swift 6 forbids NSLock.lock() in async code (use withLock); `#expect(x.allSatisfy(\.kp))` does not compile (use closures).
- M3 host part done: BrowseService 11 tests, Features view models 31 tests. Views/app/UI tests are written and syntax-checked ONLY.
  Real bug found by tests: BoardViewModel skipped its first load when the registry was empty (initial signature == first emission).
  Shared test helpers now live in the StremioKitTestSupport library (MockServer, StubTransport, makeStubbedRegistry).
  Unverified risks for the first macOS run: `@Observable` views under Swift 6 isolation, `NSAllowsLocalNetworking` covering 127.0.0.1,
  accessibility-audit findings (contrast of orange chips, poster labels), `.searchable` + `.onChange` wiring.
- M0.4 written, awaiting macOS CI. If CI is red, read the job log via the GitHub MCP tools (get_job_logs) and fix project.yml / app skeleton.
