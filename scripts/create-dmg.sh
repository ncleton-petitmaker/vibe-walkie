#!/bin/bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 /chemin/Vibe\ Remote.app /chemin/VibeRemote.dmg" >&2
  exit 64
fi

APP_PATH="$1"
OUTPUT_DMG="$2"
[[ -d "$APP_PATH" ]] || { echo "Application introuvable: $APP_PATH" >&2; exit 66; }

ARCHS="$(lipo -archs "$APP_PATH/Contents/MacOS/Vibe Remote")"
[[ "$ARCHS" == "arm64" ]] || { echo "Architecture inattendue: $ARCHS" >&2; exit 65; }

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP_PATH" "$STAGING/Vibe Remote.app"
ln -s /Applications "$STAGING/Applications"

mkdir -p "$(dirname "$OUTPUT_DMG")"
hdiutil create \
  -volname "Vibe Remote" \
  -srcfolder "$STAGING" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov "$OUTPUT_DMG"
