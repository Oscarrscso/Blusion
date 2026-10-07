# STATE

Markers: `[ ]` TODO, `[~]` DOING, `[x]` DONE, `[d]` done pending device/macOS check, `[!]` BLOCKED.

Verification topology (see ADR-002): host packages and the mock addon are verified on the
Linux agent host with `./scripts/verify.sh`; everything that needs Xcode (app target, SwiftUI,
SwiftData, Keychain, AVFoundation) is verified by the `macos` job in `.github/workflows/ci.yml`
on the same branch. `[d]` means "written, host-verified where possible, awaiting the macOS/device check".

- [d] ROOT Blusion v1 | accept: ./scripts/verify.sh milestone on a Mac (host layer is green; see handoff notes) | tries 0
  - [d] M0 Bootstrap | composite
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
  - [d] M4 Streams | accept: swift test (ranking, policy, listing, service); UI test on macOS CI | tries 1
    - [x] M4.1 ContainerSniffer (bytes > content-type > extension), RangedContainerSniffer | accept: swift test --filter ContainerSnifferTests
    - [x] M4.2 StreamQuality heuristics, PlaybackPolicy (ADR-003 notWebReady refinement), StreamingServerRoute (ADR-004, UNVERIFIED) | accept: swift test --filter PlaybackPolicyTests
    - [x] M4.3 Ranking, de-duplication, StreamListing (incremental), BingeSelection, StreamService with bounded sniffing | accept: swift test --filter StreamListingTests
    - [x] M4.4 StreamPickerViewModel, PlaybackPlan/Candidate, PlaybackSettings | accept: swift test --package-path Packages/Features --filter StreamPickerViewModelTests
    - [d] M4.5 StreamPickerView + UI test (first row before slowest addon) | accept: macOS CI
  - [d] M5 Playback (AVPlayer) | accept: host tests + macOS CI (AVEngineTests, PlaybackFlowTests); device items in docs/DEVICE_CHECKLIST.md | tries 1
    - [x] M5.1 PlaybackEngine protocol/state, PlaybackCoordinator (auto-advance, startup timeout, mid-stream failover with resume), MockEngine | accept: swift test --filter PlaybackCoordinatorTests
    - [x] M5.2 SRT/VTT parsers, SubtitleTimeline + offset, language codes, SubtitleService | accept: swift test --filter SubtitleParserTests
    - [x] M5.3 Progress: 10 s saves, watched at 90%, resume policy, ProgressSession | accept: swift test --filter ProgressTests
    - [x] M5.4 PlayerViewModel (scrubbing, controls auto-hide, subtitles, next-episode binge) | accept: swift test --package-path Packages/Features --filter PlayerViewModelTests
    - [x] M5.5 Header route logic (custom scheme, HLS rewrite, ranges) | accept: swift test --filter HeaderLoaderSupportTests
    - [d] M5.6 AVEngine, HeaderResourceLoader (ADR-005 B), NowPlayingController, SwiftUI player, PiP proxy, AirPlay | accept: swiftc -parse + macOS CI
    - [d] M5.7 PiP, AirPlay, lock-screen, background audio, interruptions | accept: docs/DEVICE_CHECKLIST.md (device only)
  - [d] M6 Format coverage | accept: host tests for engine/routing; `FALLBACK=1 ./scripts/verify.sh milestone` on a Mac | tries 1
    - [x] M6.1 Research + ADR-006 (MPVKit LGPL chosen; comparison with VLCKit, KSPlayer) | accept: docs/decisions/006-fallback-player.md
    - [x] M6.2 FallbackBackend protocol, FallbackEngine (event -> state mapping), MockBackend, routing through the coordinator | accept: swift test --filter FallbackEngineTests
    - [d] M6.3 MPVBackend glue (opt-in package, UNVERIFIED), overlay spec, enable script, spec checker incl. GPL guard | accept: swiftc -parse, scripts/check-project-spec.py; Mac build
    - [d] M6.4 MKV (AC3) and MKV (DTS) UI tests, size report, licenses.md | accept: Mac: FALLBACK=1 verify.sh milestone; scripts/size-report.sh; human license sign-off
  - [d] M7 Library and settings | accept: swift test (Features PrivacyTests), macOS CI LibrarySettingsFlowTests | tries 0
    - [x] M7.1 LibraryStore + SettingsStore persistence (Defaults + Keychain), validation, LanguageCodes.all | accept: swift test --filter LibraryAndSettingsTests
    - [d] M7.2 SwiftData schema V2 (library entity) + lightweight migration V1 to V2, Swift Data progress/library stores | accept: StoreContractTests on host; SwiftDataStoreTests on macOS CI
    - [x] M7.3 View models: Library, Settings, DataResetService, Detail library/watched, Home continue-watching, acknowledgements | accept: swift test --package-path Packages/Features
    - [x] M7.4 Privacy acceptance: a whole session leaves the mock token out of every log line and every store except the secret store | accept: swift test --filter PrivacyTests
    - [d] M7.5 SwiftUI Library/Settings/Acknowledgements, Library tab + settings sheet, Home row, Detail buttons, persistent wiring, UI tests | accept: swiftc -parse + macOS CI
  - [d] M8 Hardening and release | accept: macOS `verify.sh milestone` (includes unsigned archive); signing steps in docs/RELEASE.md | tries 0
    - [x] M8.1 Offline, empty and error states: Connectivity + isOffline on Home/Discover/Search/Streams, OfflineBanner (ADR-007) | accept: swift test --filter OfflineStateTests
    - [d] M8.2 PrivacyInfo.xcprivacy, String Catalogs + extract-strings.py, icon checks, project-spec guards | accept: scripts/check-project-spec.py; Xcode consumes them on the first Mac build
    - [x] M8.3 Leak pass, host half: LeakTests in PlayerKit (3) and Features (9, incl. a negative control) | accept: swift test --filter LeakTests
    - [d] M8.4 Launch-time baseline (XCTApplicationLaunchMetric + 8 s budget), scripts/leaks.sh, scripts/archive.sh wired into milestone | accept: macOS `verify.sh milestone`
    - [x] M8.5 Docs: README, APP_REVIEW_NOTES, MAC_FIRST_RUN, RELEASE, LOCALIZATION, DEVICE_CHECKLIST additions, ADR-007 | accept: review

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
- M4 host part done: StremioKit 205 tests, Features 47. ADR-003 (protocol verification; notWebReady is NOT a codec statement) and ADR-004
  (torrent route UNVERIFIED) written. Streams are sniffed only when the URL has no extension/filename hint (spares CDNs).
  Swift Testing gotcha: `#expect(optionalInt64 == 700 * 1_048_576)` type-checks the arithmetic alone as Int and quietly fails; use explicit Int64.
  PlayerScreen is a STUB until M5. AppServices now carries streams, settings (SettingsStore) and fallbackEngineLinked.
- M5 host part done: PlayerKit 61 tests, Features 66. ADR-005: documented AVAssetResourceLoader route is the default, the undocumented
  AVURLAssetHTTPHeaderFieldsKey sits behind -D BLUSION_UNDOCUMENTED_AV_HEADERS. Info.plist gains NSAllowsArbitraryLoadsForMedia + UIBackgroundModes audio.
  FOUND AND FIXED by tests: HLS rewriter did nothing on CRLF playlists ("\r\n" is one Character in Swift: normalise before splitting);
  `advance()` on the last candidate would have killed a working stream.
  Progress persistence is in-memory until M7 (SwiftData V2). Fallback engine factory returns nil until M6.
- M6 host part done: PlayerKit 73 tests. DECISION: fallback engine is OPT-IN (FALLBACK=1 / scripts/enable-fallback.sh) because the MPVKit pin and libmpv calls
  could not be compiled here; the default build has zero third-party code. Compiler crash avoided: `#expect(x is SomeProtocol)` / `a === b` on
  AnyObject inside #expect crashed swift 6.3.3 ("Invalid conformance"); hoist such expressions out of the macro.
  Size delta: UNMEASURED (needs a Mac). Licensing: docs/licenses.md, human sign-off open.
- M0.4 written, awaiting macOS CI. If CI is red, read the job log via the GitHub MCP tools (get_job_logs) and fix project.yml / app skeleton.
- M7 host part done: StremioKit LibraryStore/DefaultsSettingsStore, Features 84 tests incl. PrivacyTests. Persistence gains schema V2
  (LibraryEntity) with a lightweight migration, SwiftData progress/library stores; the app now persists progress, library and settings
  (UI tests stay in memory with a throwaway UserDefaults suite). Settings open as a sheet from the gear on Home, Library and Addons.
  Privacy rule enforced by test: progress/library keep poster URLs an addon published but never an addon endpoint or token.
  Swift Testing gotcha again: `await` on the right of `&&` inside #expect does not compile; hoist the awaited value into a let.
  Unverified until a Mac: swipe actions + confirmation dialog in UI, SwiftData V1 to V2 migration at runtime.
- M8 host part done: offline detection from request evidence (ADR-007), leak tests (a deliberate retain cycle proves the helper can fail),
  privacy manifest + string catalogs guarded by check-project-spec.py, release docs. Final host counts: StremioKit 213, PlayerKit 76,
  Persistence 5 (macOS adds the SwiftData tests), Features 100, mock addon 13; StremioKit line coverage 96.45%.
  ROOT is `[d]`, not `[x]`: the Definition of Done needs `verify.sh milestone` green on a Mac and the push to GitHub (B-002) did not go through.
  Next person: docs/MAC_FIRST_RUN.md, then docs/DEVICE_CHECKLIST.md, then docs/RELEASE.md.
