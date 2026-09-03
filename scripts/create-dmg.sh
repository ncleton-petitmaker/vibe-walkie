#!/bin/bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 /chemin/Vibe\ Walkie.app /chemin/VibeWalkie.dmg" >&2
  exit 64
fi

APP_PATH="$1"
OUTPUT_DMG="$2"
[[ -d "$APP_PATH" ]] || { echo "Application introuvable: $APP_PATH" >&2; exit 66; }

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BACKGROUND_SVG="$ROOT_DIR/Installer/VibeWalkie-DMG-background.svg"
[[ -f "$BACKGROUND_SVG" ]] || { echo "Fond d'installateur introuvable: $BACKGROUND_SVG" >&2; exit 66; }

ARCHS="$(lipo -archs "$APP_PATH/Contents/MacOS/Vibe Walkie")"
[[ " $ARCHS " == *" arm64 "* && " $ARCHS " == *" x86_64 "* ]] || {
  echo "Le compagnon doit être universel (arm64 + x86_64), reçu : $ARCHS" >&2
  exit 65
}
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

if diskutil list | grep -Fq "Vibe Walkie"; then
  echo "Un volume Vibe Walkie est déjà monté. Éjectez-le avant de créer l'installateur." >&2
  exit 73
fi

WORK_DIR="$(mktemp -d)"
RW_DMG="$WORK_DIR/VibeWalkie-rw.dmg"
BACKGROUND_PNG="$WORK_DIR/background.png"
MOUNT_POINT="/Volumes/Vibe Walkie"
DEVICE=""
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

cleanup() {
  if [[ -n "$DEVICE" ]]; then
    if [[ -x "$LSREGISTER" && -d "$MOUNT_POINT/Vibe Walkie.app" ]]; then
      "$LSREGISTER" -u "$MOUNT_POINT/Vibe Walkie.app" >/dev/null 2>&1 || true
    fi
    hdiutil detach "$DEVICE" -force >/dev/null 2>&1 || true
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# `sips` fait partie de macOS et conserve exactement le canevas 720 × 460 du
# SVG. Cela rend le script autonome sur une machine Xcode fraîche.
sips -s format png "$BACKGROUND_SVG" --out "$BACKGROUND_PNG" >/dev/null

mkdir -p "$WORK_DIR/empty"
hdiutil create \
  -size 40m \
  -fs HFS+ \
  -volname "Vibe Walkie" \
  -srcfolder "$WORK_DIR/empty" \
  -format UDRW \
  -ov "$RW_DMG" >/dev/null

ATTACH_OUTPUT="$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG")"
DEVICE="$(awk '/Apple_HFS/ { print $1; exit }' <<< "$ATTACH_OUTPUT")"
[[ -n "$DEVICE" ]] || { echo "Impossible de monter l'image disque" >&2; exit 74; }
[[ -d "$MOUNT_POINT" ]] || { echo "Point de montage introuvable: $MOUNT_POINT" >&2; exit 74; }

ditto "$APP_PATH" "$MOUNT_POINT/Vibe Walkie.app"
ln -s /Applications "$MOUNT_POINT/Applications"
mkdir -p "$MOUNT_POINT/.background"
ditto "$BACKGROUND_PNG" "$MOUNT_POINT/.background/background.png"
if [[ -f "$APP_PATH/Contents/Resources/AppIcon.icns" ]]; then
  ditto "$APP_PATH/Contents/Resources/AppIcon.icns" "$MOUNT_POINT/.VolumeIcon.icns"
  SetFile -a C "$MOUNT_POINT"
  SetFile -a V "$MOUNT_POINT/.VolumeIcon.icns"
fi
SetFile -a V "$MOUNT_POINT/.background"
[[ ! -d "$MOUNT_POINT/.fseventsd" ]] || SetFile -a V "$MOUNT_POINT/.fseventsd"

# Un DMG doit expliquer le geste au premier regard : deux grandes icônes, une
# flèche, aucun fichier parasite et une fenêtre qui s'ouvre à la bonne taille.
osascript - "$MOUNT_POINT" <<'APPLESCRIPT'
on run argv
set backgroundAlias to POSIX file ((item 1 of argv) & "/.background/background.png") as alias
tell application "Finder"
    tell disk "Vibe Walkie"
        open
        tell container window
            set current view to icon view
            set toolbar visible to false
            set statusbar visible to false
            set pathbar visible to false
            set bounds to {180, 180, 900, 640}
        end tell
        tell icon view options of container window
            set arrangement to not arranged
            set icon size to 112
            set text size to 14
            set background picture to backgroundAlias
        end tell
        set position of item "Vibe Walkie.app" to {190, 255}
        set position of item "Applications" to {530, 255}
        try
            set position of item ".background" to {920, 760}
        end try
        try
            set position of item ".fseventsd" to {960, 800}
        end try
        try
            set position of item ".VolumeIcon.icns" to {1000, 840}
        end try
        update without registering applications
        delay 2
        close
        open
        update without registering applications
        delay 3
        close
    end tell
end tell
end run
APPLESCRIPT

sync
if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -u "$MOUNT_POINT/Vibe Walkie.app" >/dev/null 2>&1 || true
fi
hdiutil detach "$DEVICE" >/dev/null
DEVICE=""

mkdir -p "$(dirname "$OUTPUT_DMG")"
hdiutil convert "$RW_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$OUTPUT_DMG" >/dev/null

if [[ -n "${DMG_SIGN_IDENTITY:-}" ]]; then
  codesign --force --timestamp --sign "$DMG_SIGN_IDENTITY" "$OUTPUT_DMG"
fi

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$OUTPUT_DMG" --keychain-profile "$NOTARY_PROFILE" --wait
elif [[ -n "${ASC_KEY_PATH:-}" && -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" ]]; then
  [[ -f "$ASC_KEY_PATH" ]] || { echo "Clé App Store Connect introuvable." >&2; exit 66; }
  xcrun notarytool submit "$OUTPUT_DMG" \
    --key "$ASC_KEY_PATH" \
    --key-id "$ASC_KEY_ID" \
    --issuer "$ASC_ISSUER_ID" \
    --wait
elif [[ -n "${ASC_KEY_PATH:-}${ASC_KEY_ID:-}${ASC_ISSUER_ID:-}" ]]; then
  echo "ASC_KEY_PATH, ASC_KEY_ID et ASC_ISSUER_ID doivent être fournis ensemble." >&2
  exit 64
else
  echo "DMG créé sans soumission notariale. Définissez NOTARY_PROFILE ou les variables ASC_KEY_*." >&2
fi

if [[ -n "${NOTARY_PROFILE:-}" || -n "${ASC_KEY_PATH:-}" ]]; then
  xcrun stapler staple "$OUTPUT_DMG"
  xcrun stapler validate "$OUTPUT_DMG"
fi

hdiutil verify "$OUTPUT_DMG" >/dev/null
echo "Installateur créé : $OUTPUT_DMG"
