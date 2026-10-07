# STATE

Markers: `[ ]` TODO, `[~]` DOING, `[x]` DONE, `[d]` done pending device/macOS check, `[!]` BLOCKED.

Verification topology (see ADR-002): host packages and the mock addon are verified on the
Linux agent host with `./scripts/verify.sh`; everything that needs Xcode (app target, SwiftUI,
SwiftData, Keychain, AVFoundation) is verified by the `macos` job in `.github/workflows/ci.yml`
on the same branch. `[d]` means "written, host-verified where possible, awaiting the macOS/device check".

- [~] ROOT Blusion v1 | accept: ./scripts/verify.sh milestone | tries 0
  - [ ] M0 Bootstrap | composite
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
