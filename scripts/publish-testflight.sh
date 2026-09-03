#!/bin/bash
# Déclenche le flux TestFlight dans le Trousseau graphique du Mac mini, puis
# attend son résultat. Aucun navigateur ni mot de passe Apple n'est utilisé.
set -euo pipefail

MAC_MINI_HOST="${MAC_MINI_HOST:-mac-mini}"
REMOTE_PROJECT_ROOT="${REMOTE_PROJECT_ROOT:-/Volumes/Docker/App Remote}"
REMOTE_SCRIPT="$REMOTE_PROJECT_ROOT/scripts/release-testflight-on-macmini.command"
POLL_SECONDS="${POLL_SECONDS:-10}"
MAX_POLLS="${MAX_POLLS:-270}"

quote_remote() {
  printf '%q' "$1"
}

remote_home="$(ssh "$MAC_MINI_HOST" 'printf %s "$HOME"')"
REMOTE_STATUS="${REMOTE_STATUS:-$remote_home/Desktop/Vibe Walkie TestFlight release.status}"
REMOTE_CREDENTIALS="${REMOTE_CREDENTIALS:-$remote_home/Library/Application Support/Vibe Walkie Release Tools/App Store Connect/credentials.env}"
script_q="$(quote_remote "$REMOTE_SCRIPT")"
status_q="$(quote_remote "$REMOTE_STATUS")"
credentials_q="$(quote_remote "$REMOTE_CREDENTIALS")"

if [[ "${1:-}" == "--check" ]]; then
  # L'expansion des variables ASC est volontairement effectuée sur le Mac mini.
  # shellcheck disable=SC2029
  ssh "$MAC_MINI_HOST" "set -e; test -x $script_q; test \"\$(stat -f %Lp $credentials_q)\" = 600; source $credentials_q; xcrun notarytool history --key \"\$ASC_PRIVATE_KEY_PATH\" --key-id \"\$ASC_KEY_ID\" --issuer \"\$ASC_ISSUER_ID\" >/dev/null"
  echo "✓ Mac mini, Trousseau et clé API App Store Connect prêts"
  exit 0
fi

echo "→ Démarrage de la publication TestFlight sur $MAC_MINI_HOST"
# shellcheck disable=SC2029
ssh "$MAC_MINI_HOST" "printf 'STARTING\\n' > $status_q && /usr/bin/open -a Terminal $script_q"

for ((attempt = 1; attempt <= MAX_POLLS; attempt++)); do
  # shellcheck disable=SC2029
  status="$(ssh "$MAC_MINI_HOST" "test -f $status_q && cat $status_q || true")"
  case "$status" in
    SUCCEEDED*)
      echo "✓ TestFlight publié : ${status#SUCCEEDED }"
      exit 0
      ;;
    FAILED*)
      echo "Échec TestFlight : ${status#FAILED }" >&2
      echo "Journal : ~/Desktop/Vibe Walkie TestFlight release.log sur $MAC_MINI_HOST" >&2
      exit 1
      ;;
  esac
  sleep "$POLL_SECONDS"
done

echo "Délai dépassé ; vérifiez ~/Desktop/Vibe Walkie TestFlight release.log sur $MAC_MINI_HOST." >&2
exit 75
