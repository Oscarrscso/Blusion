# App Review notes

Draft material for App Store Connect (**not legal advice**; the human decides the distribution route and answers every form themselves,
PLAN §8/§9). Blusion is prepared as a *neutral client*: it plays what the user's own addons return and ships nothing to play.

## What to tell the reviewer (paste into "Notes for the reviewer")

> Blusion is a media player and browser for addons that the user adds by URL, using the public addon protocol that several open-source
> media centres implement. **The app contains no content, no catalogs and no addons.** On first launch it is empty and explains how to add
> an addon. It has no accounts, no backend of ours, no analytics and no advertising.
>
> To review: open the Addons tab and install the demo addon at `<DEMO ADDON URL, supplied by the human>`; it serves openly licensed films
> (Blender Foundation open movies). Home, Discover, Search, Detail, stream selection and playback then work. Library and Settings need no setup.

The demo addon URL is the one thing this repo cannot supply. `Tools/MockAddon` shows the protocol end to end and can be hosted with
openly licensed media (for example Blender Foundation's open movies, which are Creative Commons licensed) for the review. Do **not** point
reviewers at a third-party addon that serves other people's copyrighted work.

## Guidelines the reviewer will care about

| Topic | Position | Where it shows |
|---|---|---|
| **5.2 Intellectual property** | The app hosts, bundles and links to no content. Like a web browser, podcast app or RSS reader, it fetches only what the user's own addon URLs return. The developer operates no server. | empty state on Home; `README.md` |
| **Trademark** | The name, bundle id and icon contain no third-party marks (`scripts/check-project-spec.py` enforces "Stremio" absent from the name and bundle id). The in-app empty-state text refers to "Stremio addons" only to say which addon format is compatible. If a reviewer objects, replace that sentence with "addons that follow the open addon protocol" (one string in `EmptyAddonsView`, plus `Localizable.xcstrings`). | `Components.swift`, `docs/decisions/003-protocol-verification.md` |
| **5.1.1 Privacy** | Nothing is collected. `PrivacyInfo.xcprivacy` declares no tracking, no collected data, and one required-reason API (UserDefaults, `CA92.1`). Addon links can contain secrets, so they live in the Keychain and are redacted from every log line (test: `PrivacyTests`). | `App/PrivacyInfo.xcprivacy`, M7 acceptance test |
| **2.5.4 Background audio** | `UIBackgroundModes: audio`, used only while a video or audio stream the user started is playing (PiP, lock-screen controls). | `Info.plist` via `project.yml` |
| **ATS exceptions** | `NSAllowsLocalNetworking` so addons on the user's LAN work over `http`; `NSAllowsArbitraryLoadsForMedia` only because many direct stream URLs are plain `http` and AVFoundation loads them itself. `NSAllowsArbitraryLoads` is never set. | ADR-005 |
| **Local network prompt** | `NSLocalNetworkUsageDescription` explains it appears only for addons on the home network. | `project.yml` |
| **Encryption export** | `ITSAppUsesNonExemptEncryption = false`: only the operating system's HTTPS is used. | `project.yml` |
| **Open source (LGPL)** | The default build links no third-party code. The optional fallback player (MPVKit, LGPL) is **off** unless built with `FALLBACK=1`; shipping it needs the sign-off in `docs/licenses.md`. | ADR-006 |

## App Store Connect answers to prepare (the human enters these)

- **App Privacy ("nutrition label"):** "Data Not Collected". Re-check this if analytics, crash reporting or any server is ever added.
- **Age rating:** the questionnaire asks about content the app can show. Blusion shows whatever the user's addons return, so answer
  for unfiltered, user-supplied content, not for a fixed catalog. Decide consciously; a too-low rating is a rejection risk.
- **Category:** Entertainment or Photo & Video.
- **Screenshots:** `scripts/screenshots.sh` produces iPhone (small and Pro Max) and iPad sets from the mock addon. They show only the mock's
  generated test pattern content, never real titles.
- **Support URL and privacy policy URL:** required by App Store Connect and not in this repo. A one-paragraph policy is enough
  ("Blusion collects no data; addon links are stored on your device in the Keychain").

## Things that would change this note

- Adding any default or recommended addon, catalog, or "browse popular" content: this breaks the neutral-client position. Don't.
- Adding accounts, sync, analytics or crash reporting: the privacy manifest, nutrition label and policy all change.
- Linking the fallback player: the license notices, size, and the open LGPL question in `docs/licenses.md` become release blockers.
