# Claude work handoff

Claude's interrupted work was saved before continuation in commit **`7331a0e`**, named **`checkpoint`**.
The original agent directories and Markdown briefs were also preserved in **`build/checkpoint-agent-work.tar.gz`**.
The archive is local, Git-ignored build data; keep a copy when moving this checkout.

The continuation uses the original briefs and existing project patterns. It restores the unfinished UI and ratings work,
finishes widget management and settings, fixes refresh/callback wiring, and makes missing-fixture and missing-simulator checks explicit.
The design follows Apple's TV app layout language; it is not a claim of pixel-identical rendering.

## Coverage of every original agent

The briefs live locally at `build/agents/brief-<agent>.md`; their original versions are preserved in the checkpoint archive.
Later briefs refine earlier ones, so overlapping work is combined rather than copied twice.

| Agent | Brief | Result in the current implementation |
|---|---|---|
| a1 | Search/browse core and default metadata addon | All catalog types, catalog-only manifests, separate stream timeout, metadata fields, and one-time Cinemeta seeding are retained. |
| a2 | Widgets core | Widget models, persistence, Fusion JSON import/export, automatic layouts, catalog sources, and supported Trakt sources are retained. |
| a3 | Initial shared design system | Cached artwork, cards, rows, chips, states, buttons, and gallery remain the foundation; s0 adapts their appearance. |
| b1 | Home, catalog-grid, and widget-manager view models | Existing view models drive the completed UI; clear-data and refreshing use their services. |
| c1 | Title detail page | Primary/resume action, saved/watched state, episode progress, trailers, synopsis, and fallback details are retained and adapted. |
| c2 | Library, Addons, Settings | Library shelves/grids and native settings/addon lists; player, Trakt, addon capabilities, and content settings are exposed. |
| d1 | Home, catalog grid, Continue Watching | Widget-based Home, featured carousel, catalog paging, and Continue Watching are wired into navigation. |
| d2 | Widgets manager/editor/source/import UI | Replaced the stub with adding, editing, ordering, removing, reset, JSON/URL import, copy/share export, and missing-addon confirmation. |
| d3 | Search and Discover UI | Genre browsing, grouped results, content-type/catalog/genre filters, paging, skeletons, and empty/error states. |
| e1 | Player controls | Glass transport, menus, scrubber, notices, failure state, and subtitles preserve the original playback actions and identifiers. |
| f1 | Infuse handoff | Existing handoff, resume, callback persistence, player detection, and alerts are retained; callback updates reach Home/Library. |
| g1 | Cached Home loading | Last-known rows remain visible while refreshing; explicit refresh invalidates relevant cached results. |
| r1 | Poster rating data | Letterboxd lookup, cache, concurrency limits, retries, and per-title observation complete the skeleton; IMDb uses catalog ratings. |
| s0 | Adaptive Apple TV design system | Recovered the partial work; black backgrounds, adaptive metrics, poster ratings, shelf headers, progress cards, tiles, and round actions. |
| s1 | App shell and Home on phone/Mac | Adaptive tab/sidebar navigation, Mac shortcuts, featured layout, Home shelves, and customization use the shared metrics. |
| s2 | Detail and stream picker on phone/Mac | Adaptive artwork/title layout, horizontal episodes, cast/information, calm stream rows, details, and collapsed addon notes. |
| s3 | Search, Discover, Library, catalog grid | Adaptive grids/shelves and poster library/watched/share menus; recent search controls are included. |
| s4 | Player, Settings, Addons, Widgets | The above native settings/widget screens and glass player controls cover this combined refinement brief. |
| t1 | Honest test infrastructure | Media tests gate only on required fixtures; absent simulator runtimes are reported, with device/Catalyst compilation fallback and a strict milestone gate. |
| v1 | Quality-of-life view-model APIs | Persistent recent searches, browse genres, playback/rating settings, Trakt Client ID, addon capabilities/prefill, and shared title actions. |

## Validation record

- `scripts/verify.sh` passes on this Mac; log: `build/finish-verify.log`.
- Swift Testing totals: StremioKit 416 (4 media skips), PlayerKit 84 (6 media skips), Persistence 12, Features 273 (final settings regression in `build/finish-features-final.log`). No test failures.
- Mock addon: 12 passed, 1 media skip, no failures. ffmpeg is absent, so generated-media playback checks were skipped.
- Generic iOS and Mac Catalyst builds pass. Build logs: `build/verify-device.log` and `build/verify-catalyst.log`.
- Syntax, string-catalog, basic lint, and whitespace checks pass. SwiftLint and PyYAML are absent; the full lint and YAML parser checks were skipped.
- Rendered Catalyst layouts: Home at Mac and phone sizes, Mac Library, Widgets, Search results, Settings, and Detail. Current images are in local `build/shots/` (`finished-home-mac.png`, `finished-home.png`, `finished-library-mac.png`, `finished-widgets-mac.png`, `finished-search-mac.png`, `finished-settings-mac.png`, and `finished-review-links-mac.png`). The last shows all five review-site badges; Settings/Widgets show corrected toolbar contrast. The Debug snapshot helper now finds sheets presented from child controllers, so it captures the sheet rather than the underlying Home window. Snapshots bring the preview window to the front to let navigation animations finish.
- Interactive Mac checks exercised addon installation, Infuse playback/return, widget title editing, and adding a genre row. Final pointer/account interactions were not exercised: native UI automation stopped connecting during final review; API credentials were not supplied.
- Simulator UI tests: not run; this Mac has no installed iOS simulator runtime.
- Physical iPhone 17 (iOS 27.0.1): signed Debug builds and installation over the existing app succeed. An earlier build launched and its process was confirmed running. A later launch was rejected by iOS while the device reported a required passcode; final launch verification awaits unlocking. Signature validation passes, Developer Mode is enabled, and the provisioning profile is valid through 2026-10-15. Log: `build/iphone-build.log`. The full playback/device checklist has not been exercised.
- Development signing succeeds. Distribution and optional MPV fallback release checks remain separate work.

Phone-sized Catalyst images check layout. They do not prove touch behavior, iPhone playback, accessibility, or device-only media features.
The original `[d]` milestone markers remain historical and do not substitute for these checks.

The user-provided stream addon was tested in a temporary session with in-memory stores. Installation, stream listing, and Infuse handoff worked.
One provider returned a plan-upgrade notice; an alternate provider played the selected film. Stopping returned to Blusion, where the title appeared
in Continue Watching. The private manifest link is deliberately absent from repository files and this report.

Widget title editing and adding a genre row were exercised in that temporary session. The saved title appeared on Home.

## Follow-up work

Three subagents separately added Trakt account support, review-site support, and pointer interactions.

- **Trakt:** Settings → Accounts → Trakt now uses PKCE with the supplied public Client ID prefilled; no Client Secret is required. The exact registered Redirect URI is still required. A registered `blusion://trakt/callback` returns through the native browser session; other registered callbacks can be pasted after authorization. Connection automatically imports watchlist and collection into Library → Saved, and watched history into Library → Watched. Refresh is manual, add-only, and keeps playback positions local. Tokens and redirect settings use the Keychain. The supplied Client ID returned HTTP 200 on a live public API request; live account authorization still awaits the registered Redirect URI and the user's browser approval.
- **Reviews:** Detail has icons and links for IMDb, Letterboxd, Rotten Tomatoes, Metacritic, and TMDB. TMDB scores and episode ratings need its API Read Access Token (Rotten Tomatoes and Metacritic are search links only; no keyless score source is wired). Save credentials under Settings → Review services. Keys are optional and live credentialed requests were not tested; parser/cache behavior has unit coverage. Poster ratings remain IMDb/Letterboxd.
- **Interaction:** Poster cards, chips, stream rows, and playback controls use hover/focus feedback and helpful keyboard labels, respecting disabled controls and Reduce Motion.
- **Missing ratings (2026-10-08):** Cinemeta's own catalogs lack `imdbRating` on 8–50% of items (new and unrated titles), and it sends `rating: "0"`
  for the episodes of nearly every show (15 of 16 sampled), which the app rightly drops. OMDb was only asked from the detail page's review row,
  never for posters or episodes. Now a poster with no IMDb score asks OMDb (cached 21 days, or 3 when empty; paused for an hour when OMDb answers
  401/429), and `OMDbRatings.episodeRatings` reads a season's `Episodes` list (`PosterRatingsStore.episodeRatings`, shown by `DetailViewModel.score(for:)`).
  The season endpoint is parsed from OMDb's documented format and covered by stub tests; it has not been run against a live key.
- **Detail page:** ratings are small icon-then-score glass buttons (`RatingButtonsRow`) under the hero title, replacing the five large review links.
  "Watched" now exists for shows (every aired episode; specials aside), per season (season menu), and from a poster's long-press menu.
- **Stream picker:** restyled as cards (resolution tile, quality headline, formatted facts, the addon's notes underneath), an ambient poster
  header, and resolution filter chips when the list holds more than one sharpness. The "Play Best" bar is unchanged.
- **Settings is a tab:** the tab bar is Home, Discover, Library, Settings, Search. There is no gear, sheet or Done button any more
  (`AppRouter.showSettings/showAddons/showWidgets` select the tab and set its stack's path), which ends the doubled Done for good.
  Home and Search reload when the viewer leaves the Settings tab, as they did when the sheet closed.
- **Best Blu-ray edition:** `BestBluraysClient` (StremioKit) reads bestblurays.com's public pages (its robots.txt allows `/films` and
  `/film/…`): search by title, rank by slug and year, confirm the page's IMDb id, read the `<h2>` above the "Best … release · updated …"
  line plus video notes, UHD tier and upcoming. Parser tested on trimmed copies of five real pages (`Fixtures/bestblurays`) and checked
  by hand against six full ones. The site has no API, so a redesign would break it; the tests say where.
- **Home freeze (open, 2026-10-09):** twelve watchdog reports on the phone (`xcrun devicectl device info files --domain-type
  systemCrashLogs`) are user force-quits of a frozen app: the main thread is inside one SwiftUI layout pass, in Observation
  registration/cancel and scroll-behaviour / lazy-placement rules, with no Blusion frame on top. It happens on Home only. A self-scrolling
  Mac Catalyst run (`BLUSION_AUTOSCROLL=1`, `BLUSION_HANG_MARKER`, `App/DebugStress.swift`) did not reproduce it, and on-device UI tests
  cannot run (a free developer profile allows 3 apps; AltStore and StikDebug use the other two). Next step is a live sample:
  `scripts/profile-iphone.sh` while the phone is frozen. `scripts/install-iphone.sh --release` installs the optimised build, since the
  Debug build is several times slower for card-heavy SwiftUI.
- **One branch:** work from 2026-10-08 on lands on `claude/blusion-github-e2e-sqx5r4`. The title page keeps the inline Play row
  (Play with Save, Watched and Trailer on one line) from `worktree-detail-backdrop-blur`, which this work was merged with.
- **Home:** Returning after a cancelled load starts a fresh observation; cancellation no longer replaces rows with errors. Two regression tests cover reload and retry. Home launch routes wait for their navigation stack; a stale Settings model preserves account credentials when changing playback.

## Test the current app

```bash
cd ~/Blusion
xcodegen generate
open Blusion.xcodeproj
```

Run **Blusion → My Mac (Mac Catalyst)** with **⌘R**. Cinemeta provides browsing/search without setup.
Use **Settings tab → Addons** for stream sources, **Settings → Playback** for Infuse preferences,
and **Settings → Widgets** to customize Home.

Check search → title → stream → playback → return → Continue Watching; also test saving/removing a title and editing a Home row.
For deterministic playback, generate the local mock fixtures as described in [MAC_FIRST_RUN.md](MAC_FIRST_RUN.md).

## Reopen and build locations

On the connected iPhone, tap **Blusion**. To rebuild later, open `Blusion.xcodeproj`, choose **Blusion → Oscar**, and press **⌘R**.
`scripts/install-iphone.sh` does the same from the shell: it builds into `build/iphone.noindex` and installs on the connected iPhone.
The Mac app is `/Applications/Blusion.app`; `scripts/install-mac.sh` rebuilds and replaces it. Open that copy and no other:
snapshot builds have their own bundle id and live in `build/catalyst*.noindex`, out of Spotlight's sight.

Old agent/build caches (3.32 GiB) and two old Blusion Xcode DerivedData folders (0.40 GiB) were removed.
The checkpoint archive, original sources/briefs, screenshots, and current iPhone/Mac builds were kept. Nothing was pushed.

## Practical limits

- Letterboxd ratings depend on its public page format and can be absent.
- Infuse progress requires its callback; the app cannot infer a new stop position without one.
- Supported Fusion imports retain supported sources; unsupported sources remain visible for replacement rather than being silently invented.
- Detail's Information block remains below the synopsis/episodes instead of a custom side-by-side Mac layout.
- The streaming-server route, optional fallback engine, simulator UI journey, and real-device checklist need their own validation.
