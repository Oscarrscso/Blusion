# ADR-002 · Verification topology: Linux host plus GitHub-hosted macOS CI

- **Status:** accepted · **Date:** 2026-10-07 · **Node:** M0 (resolves BLOCKERS B-001)

## Context

PLAN §3 gates every node on `./scripts/verify.sh`, which assumes macOS, Xcode, an iOS simulator and XcodeGen.
The agent host that builds this repo is Ubuntu 24.04 with no Xcode. PLAN §6 M0 says to stop if Xcode is missing; the operator
instead asked for the work to be completed end to end without questions, so the plan's own BLOCK rule applies: re-plan around
the blocker with a stub, a deferral or an alternative.

## Decision

Split verification by what each machine can actually prove, and never claim more than was proven.

| Layer | Where it is verified | How |
|---|---|---|
| `StremioKit` (models, URL builder, client, registry, resolver, ranking) | Linux host **and** macOS CI | `swift test` (Swift Testing), integration tests against the Node mock |
| `PlayerKit` pure logic (engine protocol, SRT/VTT, progress, coordinator, policy) | Linux host and macOS CI | `swift test` |
| `Features` view models (`@Observable`, no SwiftUI import) | Linux host and macOS CI | `swift test` |
| SwiftUI views, SwiftData/Keychain stores, `AVEngine`, app target | macOS CI only | `xcodegen` + `xcodebuild test` on a simulator |
| UI flows, accessibility audit, screenshots | macOS CI (simulator) | XCUITest, screenshots uploaded as workflow artifacts |
| PiP, AirPlay, lock-screen controls, background audio, real hardware decode | **Not verifiable** by either | `[d]` in STATE.md + `docs/DEVICE_CHECKLIST.md` |

Concrete choices:

- Swift 6.3.3 official Linux toolchain installed on the host, PGP-verified against swift.org's published keys.
  (The signing key shows as past its expiry date in GnuPG, with a good signature and the published fingerprint. Recorded for transparency.)
- `scripts/verify.sh` detects the platform. On macOS it runs every step of PLAN §3. On Linux it runs steps 1, 2 and 5-6 and prints
  `SKIPPED (no Xcode): xcodegen, xcodebuild` explicitly, so a Linux "green" is never mistaken for a full green.
  `./scripts/verify.sh milestone` additionally **fails on Linux** unless `ALLOW_HOST_ONLY=1` is set, so the root Definition of Done
  can only be satisfied by a macOS run (local or CI).
- `.github/workflows/ci.yml` runs `verify.sh` on `ubuntu-latest` (host layer) and `macos-latest` (full layer) for the working branch.
- Platform-specific code is isolated behind `#if canImport(...)` inside packages that otherwise build everywhere:
  `Persistence` (SwiftData, Security), `PlayerKit/AVEngine` (AVFoundation), `Features` views (SwiftUI).
- `StremioKit` defines `AddonStore` and `SecretStore` protocols with in-memory implementations so the registry is fully tested on Linux.
  The SwiftData and Keychain implementations are verified in macOS CI.
- One working branch (`claude/blusion-github-e2e-sqx5r4`) is used for all milestones instead of PLAN §2's branch-per-milestone,
  because the operator pinned the branch for this run. Milestone commits keep the `<id>: <title>` format so history stays navigable.
  No PR is opened.

## Consequences

- Host-side coverage numbers (M1: 90% line coverage) are measured on Linux with `llvm-cov`.
- A macOS CI failure costs one push round-trip. To keep that cheap, Apple-only code is kept thin and view logic lives in tested view models.
- The Definition of Done item "verify.sh milestone green on a clean checkout" is demonstrated by the macOS CI run on the final commit;
  the CI run URL is recorded in the Changelog.
