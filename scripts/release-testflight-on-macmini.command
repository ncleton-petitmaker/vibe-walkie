#!/bin/bash
# Flux TestFlight complet à exécuter dans la session graphique du Mac mini.
# La clé API App Store Connect est chargée par le script d'export ; aucune
# connexion au site d'Apple n'est requise.
set -euo pipefail

project_root="${VIBE_WALKIE_PROJECT_ROOT:-/Volumes/Docker/App Remote}"
build="${VIBE_WALKIE_BUILD:-$(date -u +%Y%m%d%H%M)}"
archive_path="${VIBE_WALKIE_ARCHIVE_PATH:-$project_root/build/TestFlight/VibeWalkie-1.0.0-$build.xcarchive}"
log_file="$HOME/Desktop/Vibe Walkie TestFlight release.log"
status_file="$HOME/Desktop/Vibe Walkie TestFlight release.status"

finish() {
  result=$?
  if [[ "$result" == "0" ]]; then
    printf 'SUCCEEDED BUILD=%s\n' "$build" > "$status_file"
  else
    printf 'FAILED BUILD=%s CODE=%s\n' "$build" "$result" > "$status_file"
  fi
}
trap finish EXIT

printf 'RUNNING BUILD=%s\n' "$build" > "$status_file"
mkdir -p "$(dirname "$archive_path")"

{
  echo "→ Préparation du projet iOS"
  (
    cd "$project_root/iOS"
    xcodegen generate
  )

  echo "→ Archive App Store $build"
  VIBE_WALKIE_BUILD="$build" \
  VIBE_WALKIE_ARCHIVE_PATH="$archive_path" \
  VIBE_WALKIE_OTA=0 \
    "$project_root/scripts/archive-ios-on-macmini.command"

  echo "→ Envoi et affectation TestFlight"
  VIBE_WALKIE_ARCHIVE_PATH="$archive_path" \
    "$project_root/scripts/export-upload-testflight-on-macmini.command"

  echo "TESTFLIGHT_RELEASE=OK BUILD=$build"
} 2>&1 | tee "$log_file"
