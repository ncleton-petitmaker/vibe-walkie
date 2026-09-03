#!/bin/bash
set -euo pipefail

DMG="${1:?Usage: $0 VibeWalkie.dmg}"
codesign --verify --deep --strict --verbose=2 "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG"

MOUNT="$(mktemp -d)"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
cleanup() {
  if [[ -x "$LSREGISTER" && -d "$MOUNT/Vibe Walkie.app" ]]; then
    "$LSREGISTER" -u "$MOUNT/Vibe Walkie.app" >/dev/null 2>&1 || true
  fi
  hdiutil detach "$MOUNT" >/dev/null 2>&1 || true
  rmdir "$MOUNT" >/dev/null 2>&1 || true
}
trap cleanup EXIT
hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MOUNT" >/dev/null
codesign --verify --deep --strict --verbose=2 "$MOUNT/Vibe Walkie.app"
ARCHS="$(lipo -archs "$MOUNT/Vibe Walkie.app/Contents/MacOS/Vibe Walkie")"
[[ " $ARCHS " == *" arm64 "* && " $ARCHS " == *" x86_64 "* ]] || {
  echo "Le compagnon n'est pas universel : $ARCHS" >&2
  exit 65
}
spctl --assess --type execute --verbose=4 "$MOUNT/Vibe Walkie.app"
