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

cd "$REPO_ROOT"

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

# Bundle the SwiftPM resource bundle (prices.json) next to the binary, in Resources,
# AND at the .app top level (where Bundle.main.bundleURL-based searches resolve it).
RES_BUNDLE="$BUILD_DIR/Tama_TamaCore.bundle"
if [ -d "$RES_BUNDLE" ]; then
  cp -R "$RES_BUNDLE" "$APP/Contents/MacOS/"
  cp -R "$RES_BUNDLE" "$APP/Contents/Resources/"
  cp -R "$RES_BUNDLE" "$APP/"
fi

test -d "$APP/$(basename "$RES_BUNDLE")" || echo "WARN: resource bundle missing from app root"

# ---- Optional: code signing + notarization (Gatekeeper trust) -------------------------------
# Set SIGN_IDENTITY to a "Developer ID Application: NAME (TEAMID)" identity to sign + harden.
# Set NOTARY_PROFILE to a stored notarytool keychain profile to also notarize + staple. Create
# the profile once with:
#   xcrun notarytool store-credentials NOTARY_PROFILE \
#     --apple-id you@example.com --team-id TEAMID --password <app-specific-password>
# With neither set, the build still produces an UNSIGNED app/DMG (Gatekeeper will warn users).
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
ENTITLEMENTS="Packaging/Tama.entitlements"

if [ -n "$SIGN_IDENTITY" ]; then
  echo "==> Code-signing app (hardened runtime): $SIGN_IDENTITY"
  ENT_ARGS=()
  [ -f "$ENTITLEMENTS" ] && ENT_ARGS=(--entitlements "$ENTITLEMENTS")
  codesign --force --deep --options runtime --timestamp \
    "${ENT_ARGS[@]}" --sign "$SIGN_IDENTITY" "$APP"
  codesign --verify --deep --strict --verbose=2 "$APP"
else
  echo "WARN: SIGN_IDENTITY unset → shipping an UNSIGNED app. Gatekeeper will warn users."
fi

echo "==> Creating DMG"
DMG="$DIST/$APP_NAME-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "$DISPLAY" -srcfolder "$APP" -ov -format UDZO "$DMG"

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
