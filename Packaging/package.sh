#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Tama"
DISPLAY="Tama"
VERSION="${1:-0.1.0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR=".build/release"
DIST="dist"
APP="$DIST/$DISPLAY.app"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
REQUIRE_NOTARIZATION="${REQUIRE_NOTARIZATION:-0}"
ENTITLEMENTS="Packaging/Tama.entitlements"

cd "$REPO_ROOT"

if [ "$REQUIRE_NOTARIZATION" = "1" ] && { [ -z "$SIGN_IDENTITY" ] || [ -z "$NOTARY_PROFILE" ]; }; then
  echo "ERROR: REQUIRE_NOTARIZATION=1 needs SIGN_IDENTITY and NOTARY_PROFILE." >&2
  exit 1
fi

echo "==> Building release binary"
swift build -c release --product "$APP_NAME"

echo "==> Assembling app bundle: $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
sed "s/0\.1\.0/$VERSION/" Packaging/Info.plist > "$APP/Contents/Info.plist"

# App icon (Finder / Dock / DMG).
if [ -f Packaging/AppIcon.icns ]; then
  cp Packaging/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

# Bundle the SwiftPM resource bundle (prices.json) into Contents/Resources ONLY.
# CostEstimator resolves it via Bundle.main.resourceURL (= Contents/Resources); Bundle.module
# is never used. It must NOT go at the .app root or in Contents/MacOS — a non-Contents item at
# the bundle root makes the .app unsignable ("unsealed contents in the bundle root"), which
# blocks both ad-hoc signing AND notarization.
RES_BUNDLE="$BUILD_DIR/Tama_TamaCore.bundle"
if [ -d "$RES_BUNDLE" ]; then
  cp -R "$RES_BUNDLE" "$APP/Contents/Resources/"
fi

test -d "$APP/Contents/Resources/$(basename "$RES_BUNDLE")" \
  || echo "WARN: resource bundle missing from Contents/Resources"

# ---- Optional: code signing + notarization (Gatekeeper trust) -------------------------------
# Set SIGN_IDENTITY to a "Developer ID Application: NAME (TEAMID)" identity to sign + harden.
# Set NOTARY_PROFILE to a stored notarytool keychain profile to also notarize + staple. Create
# the profile once with:
#   xcrun notarytool store-credentials NOTARY_PROFILE \
#     --apple-id you@example.com --team-id TEAMID --password <app-specific-password>
# With neither set, the build still produces an UNSIGNED app/DMG (Gatekeeper will warn users).
# Set REQUIRE_NOTARIZATION=1 for public release builds; the script will fail unless both signing
# and notarization credentials are configured.
if [ -n "$SIGN_IDENTITY" ]; then
  echo "==> Code-signing app (hardened runtime): $SIGN_IDENTITY"
  ENT_ARGS=()
  [ -f "$ENTITLEMENTS" ] && ENT_ARGS=(--entitlements "$ENTITLEMENTS")
  codesign --force --deep --options runtime --timestamp \
    "${ENT_ARGS[@]}" --sign "$SIGN_IDENTITY" "$APP"
  codesign --verify --deep --strict --verbose=2 "$APP"
else
  # No Developer ID: re-sign ad-hoc AFTER the bundle is assembled. The linker ad-hoc-signs the
  # bare binary, but adding Info.plist + resource bundles invalidates that signature — which makes
  # macOS report a quarantined download as "damaged" (the scary message). A VALID ad-hoc signature
  # downgrades that to the normal "unidentified developer", which users clear via right-click → Open
  # (no Terminal). It is still NOT notarized — only a Developer ID + notarization removes the prompt.
  echo "==> Ad-hoc signing app (no SIGN_IDENTITY → not notarized; users right-click → Open once)"
  codesign --force --deep --sign - "$APP"
  codesign --verify --deep --strict "$APP" && echo "    ad-hoc signature valid" \
    || echo "WARN: ad-hoc signature did not verify"
fi

echo "==> Creating DMG"
DMG="$DIST/$APP_NAME-$VERSION.dmg"
rm -f "$DMG"
# Stage the .app + an /Applications symlink + a prebuilt window layout, then bake them into the
# DMG. The committed Packaging/dmg.DS_Store positions Tama on the LEFT and Applications on the
# RIGHT (natural left→right drag); baking it in at create time needs NO Finder automation /
# Automation permission. Regenerate it with: python3 Packaging/make-dmg-dsstore.py Packaging/dmg.DS_Store
STAGE="$DIST/.dmg-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
if [ -f Packaging/dmg.DS_Store ]; then
  cp Packaging/dmg.DS_Store "$STAGE/.DS_Store"
else
  echo "    (no Packaging/dmg.DS_Store — DMG will use default icon arrangement)"
fi
hdiutil create -volname "$DISPLAY" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

# Notarize the DMG BEFORE hashing/copying so the SHA-256 and the stable copy cover the stapled
# file. Stapling rewrites the DMG, so order matters here.
if [ -n "$SIGN_IDENTITY" ] && [ -n "$NOTARY_PROFILE" ]; then
  echo "==> Signing DMG"
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
  echo "==> Notarizing DMG (waits for Apple)"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  echo "==> Stapling ticket"
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
else
  echo "WARN: notarization skipped (set SIGN_IDENTITY + NOTARY_PROFILE). DMG not notarized."
fi

echo "==> SHA-256"
shasum -a 256 "$DMG" | tee "$DMG.sha256"

# Stable versionless copy, so a GitHub Release can serve a constant asset name and the
# README's .../releases/latest/download/Tama.dmg link never goes stale across versions.
STABLE="$DIST/$APP_NAME.dmg"
cp "$DMG" "$STABLE"

echo "Done: $DMG (and $STABLE)"
