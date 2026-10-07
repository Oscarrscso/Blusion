# Licenses and obligations

This file lists what the app ships and what that obliges. **It is not legal advice, and it is not an audit.** The human signs off before any
release (PLAN §8, §9). Items marked ☐ are open.

## Always in the app

| Component | License | Notes |
|---|---|---|
| Blusion's own code | the owner's choice (none chosen yet) | ☐ add a LICENSE file when decided |
| Swift standard library / Apple frameworks | Apple SDK terms | no redistribution obligations |
| Swift Testing, XCTest | test targets only | not shipped |
| Node mock addon (`Tools/MockAddon`) | development tool, zero dependencies | not shipped |

No third-party code is linked into the **default** build: the dependency list is empty by design (ADR-001).

## Opt-in fallback engine (ADR-006) — only when built with `FALLBACK=1`

Linking MPVKit's **LGPL** build makes the app a distributor of LGPL libraries. Typical component set of that build (verify against the exact
MPVKit release you pin; this list is from project documentation, not from inspecting a binary):

| Component | License (as reported) | Obligation sketch |
|---|---|---|
| libmpv | LGPL-2.1-or-later when built without GPL features (GPL-2.0-or-later with `-Dgpl=true`) | |
| FFmpeg libraries | LGPL-2.1-or-later with GPL features disabled (GPL-2.0-or-later otherwise) | |
| libplacebo | LGPL-2.1-or-later | |
| libass and other helpers | permissive (ISC/BSD/MIT) or LGPL | |
| MoltenVK | Apache-2.0 | include the license and NOTICE text |
| MPVKit wrapper itself | LGPL-3.0 | |

What LGPL asks, in practice, and where we stand:

1. **Use the LGPL build, never the GPL one.** The GPL build would put the whole app under GPL, which conflicts with App Store distribution.
   `scripts/check-project-spec.py` fails the build if `Packages/FallbackPlayer/Package.swift` references a GPL product.
2. **Link dynamically** (frameworks), so a user could in principle replace the library. ☐ Confirm the pinned MPVKit xcframeworks are dynamic.
   Static linking into the app binary needs a relinking story that App Store signing makes hard.
3. **Show notices.** The app's Settings → Acknowledgements screen lists each component, its license and a link to its source. ☐ Fill in exact
   versions once MPVKit is pinned (Acknowledgements currently lists MPVKit only when the engine is built in).
4. **Offer the source.** Link to the exact MPVKit release and its build scripts for the version you ship. No Blusion modifications to these libraries exist.
5. **Open question (VideoLAN forum, unresolved):** LGPL asks that end users be able to replace the library; App Store signing complicates that.
   ☐ Counsel decides whether dynamic linking plus source availability is acceptable for your distribution route.

## Sign-off

| Question | Decision | Who / when |
|---|---|---|
| Ship the fallback engine at all? | ☐ | |
| Distribution route (TestFlight / App Store / personal) | ☐ | |
| LGPL obligations satisfied for that route | ☐ | |
| Own license for Blusion's code | ☐ | |
