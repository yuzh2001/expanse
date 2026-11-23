#!/bin/bash
# Builds Expanse.app into ./build.
#
# Signing: uses your "Apple Development" certificate if you have one, so macOS keeps the
# Accessibility / Screen Recording grants across rebuilds. Without one it signs ad hoc, which
# works too, but macOS will ask you to grant the permissions again after each rebuild.
# Override with CODESIGN_IDENTITY="Your Identity" (or "-" for ad hoc).
# DEV=1 builds "Expanse Dev" (bundle id .dev), installable beside the release.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
if [[ "${DEV:-}" = 1 ]]; then APP="build/Expanse Dev.app"; else APP="build/Expanse.app"; fi

if [[ -z "${CODESIGN_IDENTITY:-}" ]]; then
  if security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Development"; then
    CODESIGN_IDENTITY="Apple Development"
  else
    CODESIGN_IDENTITY="-"
  fi
fi

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Expanse"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Expanse"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ "${DEV:-}" = 1 ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.invignation.expanse.dev" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleName 'Expanse Dev'" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName 'Expanse Dev'" "$APP/Contents/Info.plist"
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --timestamp=none --sign "$CODESIGN_IDENTITY" "$APP"

echo "Built $APP (signed with: $CODESIGN_IDENTITY)"
