#!/bin/bash
# Archive iOS dans la session graphique du Mac mini : c'est nécessaire pour
# utiliser les clés privées du Trousseau login sans exposer leur mot de passe.
set -euo pipefail

project_root="${VIBE_WALKIE_PROJECT_ROOT:-/Volumes/Docker/App Remote}"
login="$HOME/Library/Keychains/login.keychain-db"
legacy="$HOME/Library/Keychains/yakacrm-build.keychain-db"
log_file="$HOME/Desktop/App Remote iOS archive.log"

restore_keychains() {
  security list-keychains -d user -s "$legacy" "$login" >/dev/null 2>&1 || true
}
trap restore_keychains EXIT

security list-keychains -d user -s "$login"
cd "$project_root"

build="${VIBE_WALKIE_BUILD:-$(date +%Y%m%d%H%M)}"
archive_path="${VIBE_WALKIE_ARCHIVE_PATH:-$project_root/build/OTA/VibeWalkie-1.0.0-$build-macmini.xcarchive}"
extra_settings=()
if [[ "${VIBE_WALKIE_OTA:-0}" == "1" ]]; then
  extra_settings+=("SWIFT_ACTIVE_COMPILATION_CONDITIONS=OTA_UPDATES")
fi

if [[ "${VIBE_WALKIE_EXPORT_ONLY:-0}" != "1" ]]; then
  set +u
  xcodebuild archive \
    -project iOS/AppRemoteiOS.xcodeproj \
    -scheme AppRemoteiOS \
    -configuration Release \
    -archivePath "$archive_path" \
    -destination generic/platform=iOS \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM=7XX6KYD3MY \
    MARKETING_VERSION=1.0.0 \
    CURRENT_PROJECT_VERSION="$build" \
    "${extra_settings[@]}" \
    -allowProvisioningUpdates \
    -allowProvisioningDeviceRegistration \
    -quiet 2>&1 | tee "$log_file"
  set -u
  "$project_root/scripts/verify-ios-app-identity.sh" "$archive_path" | tee -a "$log_file"
fi

if [[ "${VIBE_WALKIE_OTA:-0}" == "1" ]]; then
  if [[ "${VIBE_WALKIE_MANUAL_SIGNING:-0}" == "1" ]]; then
    default_export_options="$project_root/Distribution/ExportOptions-OTA-Manual.plist"
    default_export_path="$project_root/build/OTA/export-update-fix-$build-manual"
  else
    default_export_options="$project_root/build/OTA/ExportOptions.plist"
    default_export_path="$project_root/build/OTA/export-update-fix-$build-automatic"
  fi
  export_path="${VIBE_WALKIE_EXPORT_PATH:-$default_export_path}"
  export_options="${VIBE_WALKIE_EXPORT_OPTIONS:-$default_export_options}"
  xcodebuild -exportArchive \
    -archivePath "$archive_path" \
    -exportPath "$export_path" \
    -exportOptionsPlist "$export_options" \
    -allowProvisioningUpdates \
    -quiet 2>&1 | tee -a "$log_file"
  ipa_path="$(find "$export_path" -maxdepth 2 -name '*.ipa' -print -quit)"
  [[ -n "$ipa_path" ]] || {
    echo "IPA exportée introuvable dans $export_path" | tee -a "$log_file" >&2
    exit 65
  }
  "$project_root/scripts/verify-ios-app-identity.sh" "$ipa_path" | tee -a "$log_file"
  echo "VIBE_WALKIE_EXPORT_PATH=$export_path" | tee -a "$log_file"
fi

echo "VIBE_WALKIE_BUILD=$build" | tee -a "$log_file"
echo "VIBE_WALKIE_ARCHIVE_PATH=$archive_path" | tee -a "$log_file"
echo "Archive terminée : $log_file"
