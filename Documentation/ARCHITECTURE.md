# Architecture

## Components

```text
iPhone (iOS 26+)                       Apple silicon Mac (macOS 15+)
┌──────────────────────┐               ┌─────────────────────────┐
│ SwiftUI              │               │ SwiftUI / menu bar      │
│ On-device Speech     │               │ Accessibility / CGEvent │
│ Touch and dictation  │               │ ScreenCaptureKit        │
│ Network client       │── TLS 1.3 ───▶│ Network server :54389   │
└──────────┬───────────┘               └────────────┬────────────┘
           └──────── RemoteCore V3 ─────────────────┘
```

`RemoteCore` contains only shared models, framing, signatures, replay protection and limits. It has no user-interface dependency.

The companion advertises `_viberemote._tcp` with Bonjour and listens on fixed TLS port 54389. In standard mode, the iPhone discovers it on the LAN. In optional Roaming mode, the same listener is reached directly through the MagicDNS name or `100.64.0.0/10` address provided by Tailscale. This historical Bonjour identifier remains stable across versions. The server never executes arbitrary strings: every message type maps to a bounded action.

At launch, the iPhone starts Bonjour immediately. If no TLS connection is ready after 750 ms, it tries the MagicDNS name in parallel, followed by the Tailscale IPv4 address if resolution fails. The first connection whose certificate exactly matches the paired fingerprint wins; the others are cancelled. Bonjour discovery remains active during a Roaming session: when the Mac reappears on the LAN, the iPhone starts another race with the same local head start and automatically returns to the local path. A ten-second anti-loop delay prevents repeated switching on an unstable network.

## Identity and trust

On first launch, the Mac creates a permanent P-256 key and a self-signed X.509 certificate with Swift Certificates. The certificate and key are associated as a `SecIdentity` in Keychain. The SHA-256 fingerprint remains stable until an intentional reset.

The QR code carries the Mac name, Bonjour service, TLS fingerprint, a random secret and a 120-second expiry. The Roaming QR code adds an optional `NomadEndpoint` and remains valid for ten minutes so it can be transferred as an image or compact code. After Curve25519 proof, the Mac always requests 60-second human confirmation. Only **Allow** persists the iPhone public key.

## Multiple Macs

The iPhone keeps a registry of companions identified by their TLS certificate fingerprint, together with the selected Mac identifier. An installation that previously knew only one Mac is migrated automatically to this registry. Adding a companion therefore no longer replaces the previous one.

Only one control session is active at a time. When the user chooses another Mac, the client cancels the old target's connection, network attempts and pending replies, clears its interface state, then starts a new Local/Roaming cycle with the selected Mac's certificate. The same iPhone Curve25519 identity can be approved independently on multiple Macs; no private key is duplicated and no cloud account is introduced.

## Dictation transaction

1. `recording_started` immediately captures the AX element, window, role and process.
2. The iPhone transcribes locally; no text has been written to the Mac yet.
3. Cancellation consumes the target without insertion.
4. On release, the iPhone sends one `insert_text` message.
5. The Mac rejects a secure, expired, missing or changed target.
6. The iPhone displays “delivered” only after the ACK containing the insertion result.

## Persistence

- iOS: Curve25519 key in Keychain, paired-Mac registry and selected target in `UserDefaults`. No transcript is persisted.
- macOS: TLS identity in Keychain, approved peers in Application Support with protection until first authentication.
- no remote database, user identifier or telemetry;
- the optional Roaming endpoint contains only a `*.ts.net` name, optional Tailscale IPv4 address and fixed port. No Tailscale account or token enters `RemoteCore`.
