#!/usr/bin/env bash
# Unsigned Release IPA for sideloading (AltStore, SideStore, Sideloadly).
# Run from the public export. A private checkout is refused so the IPA cannot
# contain private API keys or addons.
#   ./scripts/build-unsigned-ipa.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -e .env || -e App/PrivateAddons.swift || -e App/PrivateAPIKeys.generated.swift || -e scripts/generate-private-api.py ]] \
  || { [[ -f scripts/generate-project.sh ]] && grep -q 'generate-private-api' scripts/generate-project.sh; }; then
  echo "build-unsigned-ipa: run this from the public export so the IPA has no private keys or addons" >&2
  exit 1
fi
[[ -f scripts/generate-project.sh ]] || { echo "build-unsigned-ipa: scripts/generate-project.sh is missing" >&2; exit 1; }
[[ "$(uname -s)" == Darwin ]] || { echo "build-unsigned-ipa: needs macOS and Xcode" >&2; exit 2; }
command -v xcodegen >/dev/null 2>&1 || { echo "build-unsigned-ipa: xcodegen is required (brew install xcodegen)" >&2; exit 2; }

./scripts/generate-project.sh

DERIVED="$ROOT/build/DerivedData"
ARCHIVE="$ROOT/build/Blusion.xcarchive"
IPA="$ROOT/build/Blusion.ipa"
rm -rf "$DERIVED" "$ARCHIVE" "$ROOT/build/ipa-stage" "$IPA"
mkdir -p "$ROOT/build"

# The scheme pre-action patches AetherEngine, but on a clean checkout it runs
# before SwiftPM has fetched the package and has nothing to change. Resolve
# first, patch that checkout, then archive with the same DerivedData.
xcodebuild -project Blusion.xcodeproj -scheme Blusion -derivedDataPath "$DERIVED" \
  -resolvePackageDependencies
bash scripts/prepare-aether.sh "$DERIVED/Build"

xcodebuild archive \
  -project Blusion.xcodeproj -scheme Blusion -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""

APP="$ARCHIVE/Products/Applications/Blusion.app"
[[ -d "$APP" ]] || { echo "build-unsigned-ipa: no Blusion.app in the archive" >&2; exit 1; }

# Xcode 26's linker writes an ad-hoc signature on arm64 even when signing is off.
# A team signature has Authority= lines or a real TeamIdentifier; ad-hoc does not.
sign_info="$(/usr/bin/codesign -dv "$APP" 2>&1 || true)"
if grep -q '^Authority=' <<<"$sign_info"; then
  echo "build-unsigned-ipa: app has a team signature" >&2
  exit 1
fi
team_id="$(grep '^TeamIdentifier=' <<<"$sign_info" | head -n 1 | cut -d= -f2- || true)"
if [[ -n "$team_id" && "$team_id" != "not set" ]]; then
  echo "build-unsigned-ipa: app has TeamIdentifier=${team_id}" >&2
  exit 1
fi

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"
[[ "$BUNDLE_ID" == app.blusion.player ]] || { echo "build-unsigned-ipa: unexpected bundle id ${BUNDLE_ID}" >&2; exit 1; }
# The public tag v.NNNNa is the private commit count. The public rev-list count is only the sync history.
if [[ "${BLUSION_RELEASE_TAG:-}" =~ ^v\.([0-9]+)a$ ]]; then
  COMMIT_COUNT="${BASH_REMATCH[1]}"
  /usr/libexec/PlistBuddy -c "Set :BlusionCommitCount ${COMMIT_COUNT}" "$APP/Info.plist"
else
  COMMIT_COUNT="$(/usr/libexec/PlistBuddy -c 'Print :BlusionCommitCount' "$APP/Info.plist" 2>/dev/null || true)"
  [[ -n "$COMMIT_COUNT" && "$COMMIT_COUNT" != 0 ]] || {
    echo "build-unsigned-ipa: commit count was not recorded. Set BLUSION_RELEASE_TAG to the v.NNNNa release, or check out full git history." >&2
    exit 1
  }
fi

if grep -a -R -q -E 'PrivateAPIKeys|PrivateAddonSeeder|PrivateAPISettingsStore' "$APP"; then
  echo "build-unsigned-ipa: app contains private build symbols; refusing to package it" >&2
  exit 1
fi

mkdir -p "$ROOT/build/ipa-stage/Payload"
ditto "$APP" "$ROOT/build/ipa-stage/Payload/Blusion.app"
(cd "$ROOT/build/ipa-stage" && zip -qry "$IPA" Payload)
rm -rf "$ROOT/build/ipa-stage"
unzip -l "$IPA" | grep -q 'Payload/Blusion.app/Info.plist' || { echo "build-unsigned-ipa: IPA is missing Payload/Blusion.app" >&2; exit 1; }
if unzip -l "$IPA" | grep -q -E 'PrivateAPI|PrivateAddon|\.env'; then
  echo "build-unsigned-ipa: IPA contains a private path" >&2
  exit 1
fi
echo "build-unsigned-ipa: ${IPA} (${COMMIT_COUNT} commits, unsigned)"
