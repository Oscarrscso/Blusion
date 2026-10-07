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
  - [ ] M1 Protocol core (StremioKit) | composite
  - [ ] M2 Client and registry | composite
  - [ ] M3 Browse UI | composite
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
- M0.4 written, awaiting macOS CI. If CI is red, read the job log via the GitHub MCP tools (get_job_logs) and fix project.yml / app skeleton.
