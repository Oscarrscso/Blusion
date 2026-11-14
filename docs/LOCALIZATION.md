# Localization

English is the only shipped language.

- `App/Localizable.xcstrings` holds the plain SwiftUI string literals in `Packages/Features/Sources/Features/Views`. `python3 scripts/extract-strings.py` adds missing entries and leaves existing translations. `scripts/verify.sh` runs it with `--check`. Do not read the catalog file in full; search it.
- `App/InfoPlist.xcstrings` holds the app name and the local-network permission text. `scripts/check-project-spec.py` keeps the English values equal to `project.yml`.
- `project.yml` sets `SWIFT_EMIT_LOC_STRINGS` and `LOCALIZATION_PREFERS_STRING_CATALOGS`.

The catalog is in the app target because SwiftUI looks `Text("...")` up in the main bundle unless a view passes `bundle: .module`. Interpolated strings are not seeded by the script; Xcode creates those keys on the first build of the app target.

Addon-supplied text is shown as sent. `AddonError.shortDescription` is English in `StremioKit`.
