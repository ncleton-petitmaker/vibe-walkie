#!/bin/bash
set -euo pipefail

project_root="${VIBE_WALKIE_PROJECT_ROOT:-/Volumes/Docker/App Remote}"
credentials="$HOME/Library/Application Support/Vibe Walkie Release Tools/App Store Connect/credentials.env"
log_file="$HOME/Desktop/Vibe Walkie TestFlight upload.log"

source "$credentials"
export ASC_KEY_ID ASC_ISSUER_ID ASC_PRIVATE_KEY_PATH

archive_path="${VIBE_WALKIE_ARCHIVE_PATH:-}"
if [[ -z "$archive_path" ]]; then
  archive_path="$(find "$project_root/build" -type d -name '*.xcarchive' -print0 \
    | xargs -0 ls -td \
    | head -1)"
fi
[[ -d "$archive_path" ]] || { echo "Archive iOS introuvable." >&2; exit 65; }

build="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleVersion' "$archive_path/Info.plist")"
export_path="$project_root/build/TestFlight/export-$build"

cd "$project_root"
xcodebuild -exportArchive \
  -archivePath "$archive_path" \
  -exportPath "$export_path" \
  -exportOptionsPlist "$project_root/Config/ExportOptions-AppStore.plist" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_PRIVATE_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  -quiet 2>&1 | tee "$log_file"

ipa_path="$(find "$export_path" -maxdepth 2 -name '*.ipa' -print -quit)"
[[ -n "$ipa_path" ]] || { echo "IPA TestFlight introuvable." >&2; exit 65; }

"$project_root/scripts/verify-ios-app-identity.sh" "$ipa_path" | tee -a "$log_file"
xcrun altool --validate-app --type ios --file "$ipa_path" \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" 2>&1 | tee -a "$log_file"
xcrun altool --upload-app --type ios --file "$ipa_path" \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" 2>&1 | tee -a "$log_file"

BUILD_NUMBER="$build" node "$project_root/scripts/publish-testflight.mjs" --wait --assign 2>&1 | tee -a "$log_file"
echo "TESTFLIGHT_BUILD=$build" | tee -a "$log_file"
