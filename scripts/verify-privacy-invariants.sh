#!/usr/bin/env bash
set -euo pipefail

# Vibe Walkie deliberately keeps dictation, keystrokes and screen pixels off
# disk and out of diagnostics. Android has a module-local version of this
# check; this companion guard covers the Mac and Windows production sources.

mac_sources=(macOS/AppRemoteMac)
windows_sources=(Windows/VibeWalkie.Companion)
ios_sources=(iOS/AppRemoteiOS iOS/AppRemoteControls iOS/SharedIntents)

if rg -n 'NSLog\([^\n]*(localizedDescription|error\.)|\b(print|os_log)\([^\n]*(localizedDescription|error\.)' "${mac_sources[@]}" --glob '*.swift'; then
  echo 'macOS diagnostics must not serialise raw system error descriptions.' >&2
  exit 1
fi

if rg -n 'detail:\s*error\.localizedDescription' "${mac_sources[@]}" --glob '*.swift'; then
  echo 'Network status sent to a mobile device must not contain raw system errors.' >&2
  exit 1
fi

if rg -n 'applicationError\s*=\s*error\.localizedDescription' "${ios_sources[@]}" --glob '*.swift'; then
  echo 'iPhone diagnostics must not persist raw error descriptions.' >&2
  exit 1
fi

if rg -n '\b(Console\.(Write|WriteLine)|Debug\.(Write|WriteLine)|Trace\.(Write|WriteLine)|File\.(Append|Write)(All)?Text)\b' "${windows_sources[@]}" --glob '*.cs'; then
  echo 'Windows production diagnostics must not write unredacted text.' >&2
  exit 1
fi

if rg -n 'error\??\.(Message|StackTrace|ToString\(\))|Exception\.(Message|StackTrace)' Windows/VibeWalkie.Companion/LocalDiagnostics.cs; then
  echo 'Windows diagnostics may record an error category/type, never its contents.' >&2
  exit 1
fi

if rg -n '(RemoteErrorPayload|Error)\(error\.Code,\s*error\.Message\)' "${windows_sources[@]}" --glob '*.cs'; then
  echo 'Windows protocol errors must expose a stable code, never exception text.' >&2
  exit 1
fi
