# Blusion

An iPhone-first, iPad-compatible player that works with Stremio addons: install an addon by manifest URL, browse catalogs,
search, open details, pick a stream and play it with resume, subtitles, Picture in Picture and AirPlay.

Blusion ships **no content addons**. Users add their own by URL.

> Work in progress. The build and run instructions below are completed in M8; see `STATE.md` for status.

## Layout

```
App/                    @main, DI container, NavigationStack routes
Packages/
  StremioKit/           models, URL builder, lenient decoding, AddonClient, Registry, StreamResolver
  PlayerKit/            PlaybackEngine protocol, AVEngine, FallbackEngine, SRT and VTT parsers
  Persistence/          SwiftData stores, Keychain wrapper
  Features/             Board, Discover, Search, Detail, StreamPicker, Player, Addons, Settings
Tools/MockAddon/        zero-dependency Node server and fixture generator
scripts/verify.sh       the one gate for every change
docs/decisions/         ADRs
PLAN.md  STATE.md  BLOCKERS.md
```

## Verify

```
./scripts/verify.sh              # per node
./scripts/verify.sh milestone    # includes UI tests; needs macOS + Xcode
```
