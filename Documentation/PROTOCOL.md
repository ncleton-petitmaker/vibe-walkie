# Protocol V3

`ProtocolVersion.current = 3`. An envelope using any other version receives `protocolMismatch`, then the connection closes. The user-facing message asks for both apps to be updated.

## Transport

- Bonjour: `_viberemote._tcp`, local domain (historical identifier retained for update compatibility);
- control port: 54389;
- TLS 1.3 minimum with certificate pinning;
- optional Roaming endpoint: MagicDNS `*.ts.net` name, optional `100.64.0.0/10` IPv4 address, fixed port 54389;
- JSON messages prefixed by a big-endian 32-bit length;
- maximum size defined in `ProtocolLimits`;
- `sessionID`, `sequence`, `messageID`, `replyTo` and timestamp in every envelope.

## Pairing

1. Mac → iPhone: `pairing_challenge` with nonce.
2. iPhone → Mac: signed `pairing_response`, public key and QR secret for a new device.
3. Mac → iPhone: `pairing_pending` with request, name, code and expiry.
4. Mac click: `connection_status`, or `pairing_denied` / `pairing_approval_expired` error.

A known device omits the QR secret and must prove possession of the same private key.

The local QR code expires after 120 seconds. The Roaming QR code expires after 600 seconds and can be scanned, imported from an image or pasted in compact form. There is intentionally no web pairing link. An unauthenticated connection closes after ten seconds; the Mac accepts at most eight pending sessions and applies a global new-connection limit.

## Roaming route

`PairingQRPayload` and `ConnectionStatusPayload` may carry a `NomadEndpoint`. `PairedMac` stores it optionally; the absence of the field remains decodable. Tailscale replaces neither pinned TLS, Curve25519 signatures nor Mac approval. The protocol does not use Serve, Funnel, SSH, OAuth or the Tailscale administration API.

## Dictation

`recording_started` returns a `TargetToken` in its ACK. `insert_text` contains the final text and that token. The final ACK contains `InsertionResult`. `cancel` consumes the target. There is no `keyboard_edit` in V3.

Manual typing uses `keyboard_text` with `userInitiated = true` and remains separate from dictation.

## Controls

Allowed commands are named keyboard events, bounded pointer movement/click/drag/scroll, window inventory/activation and screen-stream enable/disable. Any unknown or invalid type fails without generic execution.

The panel around Push-to-Talk uses seven `ControlZone` values. The Mac keeps the reference configuration and sends it with `control_configuration_snapshot`. The iPhone can propose an update through `control_configuration_update`. Hardware shortcuts are captured on the Mac, limited to a CoreGraphics-known keycode, then triggered by `mac_shortcut_press`. Imported images are resized and capped so the complete configuration remains below the frame limit.

## Idempotency

An already executed `messageID` returns the cached ACK. It never executes the action again. A lower sequence is treated as a replay and logically closes the command.
