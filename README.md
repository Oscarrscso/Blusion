# Blusion

Blusion is an iPhone/iPad media browser and player for Stremio-protocol addons, with a Mac Catalyst app from the same target.
It supports search, configurable Home rows, saved titles, resume, subtitles, manual Trakt sync, and playback in Blusion or Infuse.

Cinemeta, Stremio's official metadata addon, is installed once on first launch for catalogs, search, and title details.
It supplies **no streams**. You can disable or remove it in **Settings → Addons**; removal does not cause it to be installed again.
Blusion bundles no media or stream sources and operates no content server. Addon links are stored in the Keychain because they can contain tokens.

The current app has been built with Xcode and rendered locally through Mac Catalyst. This checkout has no installed iOS simulator runtime;
iPhone-sized Catalyst snapshots are layout checks, not iPhone or simulator testing. Final validation results are recorded in
[the Claude handoff](docs/CLAUDE_HANDOFF.md). The older milestone records in `STATE.md` remain historical.

## Build and run

Use a Mac with Xcode providing the iOS 26 SDK or newer, Swift 6, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).
The app's deployment target is iOS 26.0. Node 18+ runs the mock addon; ffmpeg generates playback fixtures.

```bash
brew install xcodegen
cd ~/Blusion
xcodegen generate
open Blusion.xcodeproj
```

Select **Blusion → My Mac (Mac Catalyst)** and press **⌘R**. To test on an iPhone, choose a connected compatible device;
to use a simulator, first install its runtime in Xcode. Review the bundle ID and development team in `project.yml` before signing for your own device.
The generated Xcode project is ignored by Git; edit `project.yml` for persistent project settings.

To keep the Mac app in `/Applications`, run `scripts/install-mac.sh`: it builds a Release copy, replaces the installed one and
opens it. That is the only copy to open. A build product launched from `build/` becomes one more "Blusion" in Spotlight.
`scripts/install-iphone.sh` builds for the connected iPhone and installs there; with a free Apple ID, run it again every seven days.

[First Mac run](docs/MAC_FIRST_RUN.md) gives the short testing path.

## Using the app

- **Home:** featured titles, Continue Watching, and catalog shelves. Use **Customize Home** or **Settings → Widgets** to add, edit,
  reorder, remove, import, or export rows. Fusion widget exports can be pasted as JSON or imported from a URL.
- **Search:** searches every supported content type across enabled searchable addons. Recent successful searches are kept locally;
  genre tiles let you browse before typing. Discover provides content-type, catalog, and genre filters.
- **Library:** saved titles, Continue Watching, and watched items. Long-press or right-click a poster for library and watched actions.
- **Pointer and keyboard:** cards and controls highlight on hover and keyboard focus. In Blusion's player, Space plays or pauses,
  Left/Right skips 10 seconds, and Esc closes. Reduce Motion keeps cards still.
- **Settings → Playback:** choose Blusion, Infuse, or Infuse only when Blusion cannot play a format. Automatic best-stream playback is optional.
  Infuse handoff includes the resume position and records progress when its callback returns.
- **Settings → Appearance:** toggle poster ratings. IMDb ratings come from catalog metadata; movie Letterboxd ratings are fetched and cached when available.
- **Title details:** IMDb, Letterboxd, Rotten Tomatoes, Metacritic, and TMDb icons open their review pages or a labeled search.
  Links work without API keys. **Settings → Review services** accepts an optional OMDb API key for critic scores and a TMDb API Read Access Token
  for TMDb ratings; select **Save Review Services**. Credentials are stored in the Keychain.
- **Settings → Accounts → Trakt:** the supplied public Client ID is prefilled. Enter the exact Redirect URI registered for that
  Trakt API app, then select **Connect Trakt**. PKCE sign-in needs no Client Secret. A registered `blusion://trakt/callback`
  returns through the native browser session; other registered callbacks can be pasted after authorization.
  Connecting imports watchlist (watch later) and collection into **Library → Saved**, and history into **Library → Watched**.
  Use **Refresh from Trakt** for later changes. Import adds missing IMDb titles without deleting local items or sending data to Trakt.
  Playback positions stay on the device. Tokens and connection settings use the Keychain.

## Adding an addon

1. Get its manifest link, such as `https://example.com/path/manifest.json` or `stremio://example.com/path/manifest.json`.
2. Open **Home gear → Settings → Addons**, paste the link, and select **Install**. A `stremio://` install link can also open this field for you to review.
3. Enable, reorder, or remove addons on the same screen. Removing one also removes its saved link.

Catalog addons provide browsing and search; stream addons provide playback choices. Direct HTTP(S) media can play in Blusion.
Infuse can handle additional formats, including MKV and DTS. Streams needing request headers stay in Blusion because an external player
cannot receive those headers. Torrent streams require a compatible streaming server you run and configure in **Settings → Streaming server**.

## Local mock addon and verification

```bash
brew install node ffmpeg             # optional until you need mock playback fixtures
./Tools/MockAddon/make-fixtures.sh
node Tools/MockAddon/server.js
```

Install `http://127.0.0.1:7001/demo/manifest.json` for mock catalogs and `http://127.0.0.1:7002/demo/manifest.json` for mock streams
when the app runs on this Mac or a simulator. A physical phone needs the Mac's LAN address. Generated media is ignored by Git.

```bash
./scripts/verify.sh
./scripts/verify.sh milestone
```

Media-dependent tests are explicitly skipped when their generated fixtures are absent. When no iPhone simulator is installed,
verification reports skipped simulator tests and builds for generic iOS and Mac Catalyst instead. A milestone run still requires
simulator tests unless `ALLOW_HOST_ONLY=1` is explicitly supplied; that override retains the skipped-check summary.

```bash
scripts/snapshot.sh home build/shots/home.png
scripts/snapshot.sh home build/shots/home-mac.png --mac
```

The first command renders an iPhone-sized Catalyst layout; `--mac` uses the Mac layout. Neither is a simulator test.
Snapshot builds carry the bundle id `app.blusion.player.snapshot`, so a run never touches the installed app or its settings.

## Known limitations

- Device checks remain open for PiP, AirPlay, lock-screen controls, background playback, hardware decoding, local-network prompts,
  VoiceOver, and accessibility text sizes. See [the device checklist](docs/DEVICE_CHECKLIST.md).
- A real streaming-server route, the optional MPV fallback build, distribution signing, and App Store submission are not validated by local layout snapshots.
- Letterboxd lookup depends on its public page format and availability; a missing rating leaves the poster badge absent.
- Trakt sign-in/sync and optional OMDb/TMDb lookups have stub-based tests; live account checks require user credentials.
- External-player progress depends on the player returning a callback. A canceled or missing callback cannot supply a new position.
- SRT and WebVTT are supported by the built-in player; styled or bitmap subtitles need a player that supports them.
- Trakt imports on connection; later refreshes are manual. It does not transfer playback positions or propagate removals. There is no automatic device sync or tvOS target.
- Addon manifest URLs containing query strings are rejected. English is the only completed localization.

## Project layout

```text
App/                    app entry point, dependency wiring, privacy manifest, string catalogs, assets
Packages/StremioKit/     addon protocol, catalogs, streams, widgets, settings, ratings, cache contracts
Packages/PlayerKit/      playback engines, coordinator, subtitles, progress
Packages/Persistence/   SwiftData and Keychain stores
Packages/Features/      view models and SwiftUI screens
Packages/FallbackPlayer/ optional MPV backend
Tools/MockAddon/        local addon server and fixture generator
scripts/                verification, project generation checks, snapshots, archives, lint
```

The fallback backend is opt-in through `scripts/enable-fallback.sh`; its licensing and release checks are in
[docs/licenses.md](docs/licenses.md). See [the handoff](docs/CLAUDE_HANDOFF.md) for every original agent brief,
[STATE.md](STATE.md) for historical milestones, and [docs/RELEASE.md](docs/RELEASE.md) for distribution work.
