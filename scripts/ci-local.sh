#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

swift test --package-path "$ROOT/Packages/RemoteCore"

if command -v xcodegen >/dev/null 2>&1; then
  (cd "$ROOT/iOS" && xcodegen generate)
  (cd "$ROOT/macOS" && xcodegen generate)
fi

xcodebuild \
  -project "$ROOT/iOS/AppRemoteiOS.xcodeproj" \
  -scheme AppRemoteiOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build

SIMULATOR_ID="$(xcrun simctl list devices available -j | /usr/bin/python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
for runtime, candidates in devices.items():
    if ".SimRuntime.iOS-" not in runtime:
        continue
    for device in candidates:
        if device.get("isAvailable"):
            print(device["udid"])
            raise SystemExit
')"
if [[ -z "$SIMULATOR_ID" ]]; then
  echo "Aucun simulateur iPhone disponible. Installez un runtime iOS dans Xcode." >&2
  exit 1
fi

xcodebuild test \
  -project "$ROOT/iOS/AppRemoteiOS.xcodeproj" \
  -scheme AppRemoteiOS \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  CODE_SIGNING_ALLOWED=NO

xcodebuild \
  -project "$ROOT/macOS/AppRemoteMac.xcodeproj" \
  -scheme AppRemoteMac \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild test \
  -project "$ROOT/macOS/AppRemoteMac.xcodeproj" \
  -scheme AppRemoteMac \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO

if command -v swiftlint >/dev/null 2>&1; then
  swiftlint lint --strict --config "$ROOT/.swiftlint.yml" \
    "$ROOT/Packages" "$ROOT/iOS" "$ROOT/macOS"
fi

if rg -n \
  'itms-services|remoteHost|remotePort|keyboard_edit|keyboardEdit|_appremote\._tcp|com\.yakaperformance\.appremote' \
  "$ROOT/Packages" "$ROOT/iOS" "$ROOT/macOS" \
  --glob '!**/Tests/**' --glob '!**/*Tests/**' \
  --glob '!**/build*/**' --glob '!**/.build/**' --glob '!**/*.xcodeproj/**'; then
  echo "Une référence interdite au prototype subsiste." >&2
  exit 1
fi
