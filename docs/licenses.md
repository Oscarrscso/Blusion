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

## Data the app downloads

| Data | Terms | Notes |
|---|---|---|
| IMDb `title.ratings.tsv.gz` (datasets.imdbws.com) | IMDb non-commercial datasets: personal and non-commercial use only (https://developer.imdb.com/non-commercial-datasets/) | Downloaded to the device once a day, kept out of backups, never uploaded or redistributed. Credit line in Settings → IMDb ratings and Acknowledgements. ☐ A public or commercial release needs IMDb's permission or a licence: do not ship this to others on the current terms. |
| IMDb `title.episode.tsv.gz` (datasets.imdbws.com) | IMDb non-commercial datasets: personal and non-commercial use only (https://developer.imdb.com/non-commercial-datasets/) | Episode-to-series/season/number mapping downloaded only on unmetered connections, indexed on device and kept out of backups. The data is not redistributed. |

## Brand marks in the app

| Marks | Terms | Notes |
|---|---|---|
| Six streaming service logos in `App/Assets.xcassets` (`StreamLogoNetflix`, `StreamLogoPrimeVideo`, `StreamLogoAppleTV`, `StreamLogoHBOMax`, `StreamLogoParamountPlus`, `StreamLogoCrunchyroll`), from Simple Icons 13.21.0 (HBO Max from 15.x, the current mark) | Icon files CC0-1.0 (the package licence). Each mark is still that service's trademark, and CC0 does not cover it. Simple Icons asks users to seek permission for brand use. | Shown on a stream's card to name the service it comes from. ☐ A release needs sign-off that each service's mark may be shown. |
| Disney+ logo (`StreamLogoDisneyPlus`, from Wikimedia Commons `Disney+ 2024.svg`, author Disney Enterprises) and Peacock logo (`StreamLogoPeacock`, from `NBCUniversal Peacock Logo (2026).svg`, author NBCUniversal) | Commons marks both as public domain as simple text logos, and as trademarked. Copyright is not the issue: the trademarks belong to Disney and NBCUniversal. | Used on Disney+ and Peacock streams. Hulu streams also show the Disney+ logo, as the viewer chose: Hulu streams from the Disney+ app. The Disney+ SVG is trimmed to its wordmark paths, with the Illustrator styles and hidden layers removed. ☐ Same sign-off as above. |
| Blu-ray and Ultra HD Blu-ray logos (`StreamLogoBluRay`, `StreamLogoUHDBluRay`) for a disc's box beside a release's name, from Wikimedia Commons (`Blu-ray Disc.svg`, `Ultra HD Blu-ray logo.svg`, author Blu-ray Disc Association) | Commons lists the files as public domain, but marks them as trademarked, so they are not free to use. ☐ A release needs sign-off that the Blu-ray Disc Association's marks may be shown. | Personal use only, like the service logos. |

## Fallback engine (ADR-006) — in the iPhone install

`scripts/install-iphone.sh` builds the fallback engine in, so MKV, AVI, DTS, TrueHD and AV1 play in the iPhone app. `scripts/install-mac.sh` leaves it out: the MPVKit versions `from: "0.40.0"` allows fetch a Libuavs3d with no Mac Catalyst slice. The default `project.yml` and `scripts/archive.sh` still leave it out: a release that ships it needs the sign-off below.

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
2. **Link dynamically** (frameworks), so a user could in principle replace the library. ☐ Confirm the MPVKit xcframeworks that get resolved are dynamic.
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
