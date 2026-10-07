# BLOCKERS

Entry format: node / tried / error / hypotheses / the one question / resolution.

## B-001 · M0 · No macOS, Xcode or iOS simulator on the agent host — ROUTED AROUND

- **Node:** M0 Bootstrap (`xcodebuild -version`, `xcrun simctl`, `xcodegen`)
- **Tried:** `swift --version` (absent), `xcodebuild -version` (absent). Host is Ubuntu 24.04 (Linux x86_64).
- **Error:** PLAN §6 M0 says "If macOS or Xcode is missing, stop and say so."
- **Hypotheses:** none needed; the host simply cannot run Xcode.
- **The question:** "Can you give me a Mac?" — not asked; the operator instructed the agent to complete end to end without questions.
- **Route (parent re-plan, PLAN §2 BLOCK rule: stub/defer/alternative):**
  1. Installed the official Swift 6.3.3 Linux toolchain (PGP-verified) so `StremioKit`, `PlayerKit` (host-side parts) and the
     view-model layer build and test for real on the host.
  2. Added a GitHub-hosted macOS job (public repo, free minutes) that runs the Xcode steps of `verify.sh`
     (`xcodegen`, `xcodebuild test` on a simulator, `swiftlint --strict`). CI results are read back via the GitHub API.
  3. Anything that CI cannot prove (PiP, AirPlay, lock-screen controls, background audio, real hardware decode) is `[d]`
     and listed in `docs/DEVICE_CHECKLIST.md`.
- **Resolution:** routed; see ADR-002. Residual risk: code that only compiles on Apple platforms is verified one CI round-trip at a time.
