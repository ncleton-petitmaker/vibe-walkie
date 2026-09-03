#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-1.0.0}"
BUILD="${BUILD:-$(date -u +%Y%m%d%H%M)}"
NOTES="${NOTES:-Améliorations de stabilité et d’expérience.}"
VPS_HOST="${VPS_HOST:-yaka-vps}"
PUBLIC_BASE_URL="${PUBLIC_BASE_URL:-https://app-remote.92.222.247.135.sslip.io}"
DEVICE_UDID="${DEVICE_UDID:-00008120-001260191462201E}"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build/ios-ota-$BUILD.noindex}"
ARCHIVE_PATH="$BUILD_DIR/VibeWalkie.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
REMOTE_IPA="/tmp/vibe-walkie-$BUILD.ipa"

usage() {
  cat <<'USAGE'
Publie une build iPhone Ad Hoc sur le canal OTA privé.

Variables facultatives :
  VERSION=1.0.0
  BUILD=202609031330
  NOTES="Correctifs…"
  DEVICE_UDID=00008120-001260191462201E
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "VERSION doit suivre x.y.z (reçu : $VERSION)" >&2
  exit 64
}
[[ "$BUILD" =~ ^[0-9]+$ ]] || {
  echo "BUILD doit être numérique (reçu : $BUILD)" >&2
  exit 64
}

for command in xcodebuild xcodegen unzip codesign security ssh scp curl plutil shasum; do
  command -v "$command" >/dev/null || {
    echo "Commande absente : $command" >&2
    exit 69
  }
done
test -f "$ROOT_DIR/Localization/locale-manifest.json"
test -f "$ROOT_DIR/Distribution/ExportOptions-OTA.plist"

mkdir -p "$BUILD_DIR"
(
  cd "$ROOT_DIR/iOS"
  xcodegen generate
)

echo "→ Archive iPhone OTA $VERSION ($BUILD)"
xcodebuild archive \
  -project "$ROOT_DIR/iOS/AppRemoteiOS.xcodeproj" \
  -scheme AppRemoteiOS \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  -derivedDataPath "$BUILD_DIR/DerivedData.noindex" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD" \
  DEVELOPMENT_TEAM=7XX6KYD3MY \
  CODE_SIGN_STYLE=Automatic \
  "SWIFT_ACTIVE_COMPILATION_CONDITIONS=\$(inherited) OTA_UPDATES" \
  -allowProvisioningUpdates

echo "→ Export Ad Hoc"
rm -rf "$EXPORT_DIR"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$ROOT_DIR/Distribution/ExportOptions-OTA.plist" \
  -allowProvisioningUpdates

IPA_PATH="$(find "$EXPORT_DIR" -maxdepth 1 -type f -name '*.ipa' -print -quit)"
[[ -n "$IPA_PATH" ]] || {
  echo "IPA introuvable après export." >&2
  exit 65
}

VERIFY_DIR="$BUILD_DIR/verify"
rm -rf "$VERIFY_DIR"
mkdir -p "$VERIFY_DIR"
unzip -q "$IPA_PATH" -d "$VERIFY_DIR"
APP_PATH="$(find "$VERIFY_DIR/Payload" -maxdepth 1 -type d -name '*.app' -print -quit)"
[[ -n "$APP_PATH" ]] || {
  echo "Application introuvable dans l’IPA." >&2
  exit 65
}

ACTUAL_BUNDLE="$(plutil -extract CFBundleIdentifier raw -o - "$APP_PATH/Info.plist")"
ACTUAL_BUILD="$(plutil -extract CFBundleVersion raw -o - "$APP_PATH/Info.plist")"
[[ "$ACTUAL_BUNDLE" == "com.nicolascleton.viberemote" && "$ACTUAL_BUILD" == "$BUILD" ]] || {
  echo "Identité IPA invalide : $ACTUAL_BUNDLE ($ACTUAL_BUILD)." >&2
  exit 65
}

EXTENSION_PLIST="$APP_PATH/PlugIns/Vibe Walkie Controls.appex/Info.plist"
ACTUAL_EXTENSION_BUNDLE="$(plutil -extract CFBundleIdentifier raw -o - "$EXTENSION_PLIST")"
[[ "$ACTUAL_EXTENSION_BUNDLE" == "com.nicolascleton.viberemote.controls" ]] || {
  echo "Bundle de l’extension invalide : $ACTUAL_EXTENSION_BUNDLE." >&2
  exit 65
}
strings "$APP_PATH/Vibe Walkie" | grep -Fq "$PUBLIC_BASE_URL/api/releases/ios/check" || {
  echo "Le contrôle OTA n’est pas compilé dans l’application." >&2
  exit 65
}

PROFILE_PLIST="$VERIFY_DIR/profile.plist"
security cms -D -i "$APP_PATH/embedded.mobileprovision" > "$PROFILE_PLIST"
plutil -extract ProvisionedDevices json -o - "$PROFILE_PLIST" | grep -Fq "$DEVICE_UDID" || {
  echo "L’iPhone attendu n’est pas inclus dans le profil Ad Hoc." >&2
  exit 65
}
codesign --verify --deep --strict "$APP_PATH"

NOTES_B64="$(printf '%s' "$NOTES" | base64 | tr -d '\n')"
echo "→ Publication chiffrée vers $VPS_HOST"
scp -q "$IPA_PATH" "$VPS_HOST:$REMOTE_IPA"
ssh "$VPS_HOST" bash -s -- "$REMOTE_IPA" "$VERSION" "$BUILD" "$NOTES_B64" "$PUBLIC_BASE_URL" <<'REMOTE'
set -euo pipefail
artifact="$1"
version="$2"
build="$3"
notes_b64="$4"
public_base_url="$5"
cleanup() { rm -f "$artifact"; }
trap cleanup EXIT
set -a
source /opt/app-remote/.env
set +a
curl --fail --silent --show-error \
  --request POST "$public_base_url/api/releases/ios/upload" \
  --header "Authorization: Bearer $RELEASE_DEPLOY_KEY" \
  --header "X-Release-Version: $version" \
  --header "X-Release-Build: $build" \
  --header "X-Release-Notes: $notes_b64" \
  --header "X-Release-Force: false" \
  --header 'Content-Type: application/octet-stream' \
  --data-binary "@$artifact"
REMOTE

echo
echo "→ Vérification distante"
CHECK_PATH="$BUILD_DIR/check.json"
MANIFEST_PATH="$BUILD_DIR/manifest.plist"
DOWNLOADED_IPA="$BUILD_DIR/downloaded-$BUILD.ipa"
curl --fail --silent --show-error "$PUBLIC_BASE_URL/api/releases/ios/check" -o "$CHECK_PATH"
PUBLISHED_BUILD="$(plutil -extract latestBuild raw -o - "$CHECK_PATH")"
MANIFEST_URL="$(plutil -extract manifestUrl raw -o - "$CHECK_PATH")"
[[ "$PUBLISHED_BUILD" == "$BUILD" ]] || {
  echo "Le service OTA annonce la build $PUBLISHED_BUILD au lieu de $BUILD." >&2
  exit 65
}
curl --fail --silent --show-error "$MANIFEST_URL" -o "$MANIFEST_PATH"
MANIFEST_BUNDLE="$(/usr/libexec/PlistBuddy -c 'Print :items:0:metadata:bundle-identifier' "$MANIFEST_PATH")"
DOWNLOAD_URL="$(/usr/libexec/PlistBuddy -c 'Print :items:0:assets:0:url' "$MANIFEST_PATH")"
[[ "$MANIFEST_BUNDLE" == "$ACTUAL_BUNDLE" ]] || {
  echo "Bundle du manifeste invalide : $MANIFEST_BUNDLE." >&2
  exit 65
}
curl --fail --silent --show-error "$DOWNLOAD_URL" -o "$DOWNLOADED_IPA"
[[ "$(shasum -a 256 "$IPA_PATH" | awk '{print $1}')" == "$(shasum -a 256 "$DOWNLOADED_IPA" | awk '{print $1}')" ]] || {
  echo "L’IPA téléchargée diffère de l’IPA publiée." >&2
  exit 65
}

echo "✓ Mise à jour iPhone OTA publiée : $VERSION ($BUILD)"
echo "  Installation : $PUBLIC_BASE_URL/install/ios"
echo "  IPA locale : $IPA_PATH"
