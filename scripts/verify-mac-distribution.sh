#!/bin/bash
set -euo pipefail

DMG="${1:?Usage: $0 VibeRemote.dmg}"
codesign --verify --deep --strict --verbose=2 "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG"

MOUNT="$(mktemp -d)"
trap 'hdiutil detach "$MOUNT" >/dev/null 2>&1 || true; rmdir "$MOUNT" >/dev/null 2>&1 || true' EXIT
hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MOUNT" >/dev/null
codesign --verify --deep --strict --verbose=2 "$MOUNT/Vibe Remote.app"
spctl --assess --type execute --verbose=4 "$MOUNT/Vibe Remote.app"
