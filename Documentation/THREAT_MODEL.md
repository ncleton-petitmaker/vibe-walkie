# Threat Model

## Assets

- dictated text while it is processed in memory;
- ability to type, click and control the Mac;
- screen-view images;
- device keys, TLS identity and ephemeral pairing secret;
- update chain and distribution certificates.

## Considered adversaries

- hostile device on the same Wi-Fi network;
- hostile peer or overly broad ACL in the same Tailscale tailnet;
- interception or poisoning of Bonjour discovery;
- frame capture and replay;
- photographed but expired QR code;
- previously authorized and later revoked iPhone;
- AX target changed during dictation;
- compromised update artifact;
- public contribution containing a secret.

## Mitigations

| Threat | Mitigation |
|---|---|
| Local interception | TLS 1.3 and exact fingerprint transferred out of band through the QR code |
| Interception through Tailscale or DERP | Tailscale WireGuard tunnel plus Vibe Walkie's own pinned TLS 1.3 |
| Impersonated iPhone | Curve25519 signature, QR secret and explicit approval on the Mac |
| Replay | monotonic sequences, message identifiers and idempotent ACK cache |
| Denial of service | bounded frames and payloads, global rate limiting, at most eight unauthenticated sessions and a ten-second timeout |
| Wrong target | immediate AX capture, short-lived token, strict identity and secure-field rejection |
| Double insertion | a single `insert_text`, token consumption and replayed ACK without re-execution |
| Forged update | Developer ID, notarization, Sparkle EdDSA and GitHub HTTPS |
| Secret in Git | Gitleaks, Dependabot, review and protected `release` environment |

## Accepted limitations

A Mac or iPhone already compromised at the user-account level can read what that user sees or enters. The protocol does not protect against an attacker who has physically unlocked both devices. Bonjour reveals the service's presence on the LAN. In Roaming mode, the tailnet and its ACLs remain the user's responsibility and are subject to Tailscale's terms. Screen view necessarily transmits displayed pixels to the authorized iPhone.

## Out of scope for V1

Vibe Walkie server, public/Funnel access, Vibe Walkie accounts, multitenancy, cloud synchronization, Intel Macs and protocol V1 compatibility.
