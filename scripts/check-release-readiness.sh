#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/Scripts/ci-local.sh"

for command in git xcodebuild xcrun codesign hdiutil; do
  command -v "$command" >/dev/null || { echo "Commande absente: $command" >&2; exit 1; }
done

git -C "$ROOT" diff --quiet
git -C "$ROOT" diff --cached --quiet
git -C "$ROOT" status --porcelain --untracked-files=normal | grep -q . && {
  echo "Le dépôt doit être propre avant une release." >&2
  exit 1
}

echo "Portes locales franchies. Les portes notarisation, TestFlight, marque et appareils réels restent externes."
