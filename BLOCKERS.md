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

## B-002 · M0 · GitHub write access denied (git push 403, API "Resource not accessible by integration") — OPEN, needs the human

- **Node:** M0.4 (CI proof), and delivery of every milestone to `Oscarrscso/Blusion`.
- **Tried:** `git push -u origin claude/blusion-github-e2e-sqx5r4` -> 403 "Claude doesn't have GitHub access to Oscarrscso/Blusion for your organization".
  `mcp__github__create_or_update_file` (README.md, designated branch) -> 403 "Resource not accessible by integration".
  Read access works (`get_me`, `search_repositories` report `permissions.push: true` for the user, but the Claude GitHub App itself has no write grant).
- **Hypotheses:** the Claude GitHub App is not installed on this repository (or was installed read-only). Nothing the agent can change.
- **Not attempted, deliberately:** other credentials, other hosts, other branches, or any route that bypasses the denial.
- **The one question (for the human, not asked during the run):** install/reconnect the Claude GitHub App for `Oscarrscso/Blusion`
  (https://claude.ai/connect-github, https://github.com/apps/claude/installations/select_target), then run
  `git push -u origin claude/blusion-github-e2e-sqx5r4` from this session's checkout, or start a new session with the repo selected.
- **Route taken meanwhile:** all work is committed locally on the designated branch with `<id>: <title>` commits; the push is retried at the end of the run.
  Consequence for ADR-002: the macOS CI job is written but has NOT run. Apple-only code is `[d]` = written and syntax-checked (`swiftc -parse`), not compiled.
