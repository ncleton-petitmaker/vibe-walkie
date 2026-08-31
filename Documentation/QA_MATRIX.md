# V1 Real-World QA Matrix

This matrix is a release gate. A row moves to `PASSED` only with a date, tester, device models and versions, plus a link to the report or ticket. `NOT TESTED` never counts as a pass.

## Clean installations without a terminal

| No. | Mac / macOS | Account without dev tools | Network | DMG → first dictation | Result | Evidence |
|---:|---|:---:|---|---:|---|---|
| 01 | TBD | Yes | TBD | — | NOT TESTED | — |
| 02 | TBD | Yes | TBD | — | NOT TESTED | — |
| 03 | TBD | Yes | TBD | — | NOT TESTED | — |
| 04 | TBD | Yes | TBD | — | NOT TESTED | — |
| 05 | TBD | Yes | TBD | — | NOT TESTED | — |
| 06 | TBD | Yes | TBD | — | NOT TESTED | — |
| 07 | TBD | Yes | TBD | — | NOT TESTED | — |
| 08 | TBD | Yes | TBD | — | NOT TESTED | — |
| 09 | TBD | Yes | TBD | — | NOT TESTED | — |
| 10 | TBD | Yes | TBD | — | NOT TESTED | — |

UX target: each of the ten installations must allow a first dictation within three minutes of download, without Homebrew, Xcode or Terminal.

## Devices and systems

- [ ] Multiple physical iPhones running iOS 26.
- [ ] Multiple Apple silicon Macs running macOS 15 or later.
- [ ] Administrator and standard macOS accounts.
- [ ] Different iOS screen and text sizes.
- [ ] VoiceOver, increased contrast and reduced motion.

## Network and lifecycle

- [ ] Multiple home Wi-Fi networks.
- [ ] macOS firewall enabled.
- [ ] Local-network change.
- [ ] iPhone and Mac sleep/wake.
- [ ] Restart both devices.
- [ ] Network loss during dictation, commands and screen view.

## Multiple Macs

- [ ] Migrate a single-Mac installation without pairing again.
- [ ] Add a second and then third companion without replacing earlier ones.
- [ ] Switch A → B → A on the same LAN, with no command delivered to the old target.
- [ ] Switch between a local Mac and a Mac reachable only through Tailscale.
- [ ] Cancel or deny new pairing, then reconnect to the previous Mac.
- [ ] Forget the active Mac and automatically select the remaining companion.
- [ ] Forget an inactive Mac without interrupting the current session.
- [ ] Keep two Macs with the same name distinct through their certificates.

## Target applications

| Target | Dictation | Keyboard | Trackpad | Changed field rejected | Secure field rejected |
|---|---|---|---|---|---|
| Notes | NOT TESTED | NOT TESTED | NOT TESTED | NOT TESTED | N/A |
| Mail | NOT TESTED | NOT TESTED | NOT TESTED | NOT TESTED | N/A |
| Safari | NOT TESTED | NOT TESTED | NOT TESTED | NOT TESTED | NOT TESTED |
| Chrome | NOT TESTED | NOT TESTED | NOT TESTED | NOT TESTED | NOT TESTED |
| Slack/Teams | NOT TESTED | NOT TESTED | NOT TESTED | NOT TESTED | N/A |
| Pages | NOT TESTED | NOT TESTED | NOT TESTED | NOT TESTED | N/A |

## Distribution and updates

- [ ] Mount the DMG and drag to Applications.
- [ ] Explain and recover from accidental launch inside the DMG.
- [ ] Guided Accessibility permission with verification on return.
- [ ] Never request Screen Recording before the first screen-view use.
- [ ] First pairing and Mac approval.
- [ ] Reconnect after restart.
- [ ] Revoke an iPhone and perform a complete reset.
- [ ] Sparkle update between two signed DMGs.
- [ ] Documented and verified uninstallation.

## Public beta

The TestFlight form must collect: device/OS, companion installation, permission comprehension, pairing, time to first dictation, stability, screen view, uninstallation and consent to follow-up. Every critical or high-severity issue blocks the Release Candidate.

## Roaming mode V1.1

The website must not announce this mode as available until every row below is validated.

| Scenario | Direct Tailscale | DERP | 5G | Result / evidence |
|---|:---:|:---:|:---:|---|
| Tailscale missing, stopped or disconnected is explained clearly | — | — | — | NOT TESTED |
| MagicDNS unavailable, fallback to IPv4 `100.64.0.0/10` | — | — | — | NOT TESTED |
| Blocking ACL and forged certificate are rejected | — | — | — | NOT TESTED |
| Local/Roaming race, losing attempt cancelled and automatic return to LAN | — | — | — | Route priority automated; physical race still pending |
| Sleep/wake and Wi-Fi → 5G, reconnect in < 10 s once reachable | — | — | — | NOT TESTED |
| QR through camera, image and code; allow/deny/expiry/replay | — | — | — | NOT TESTED |
| Dictation, keyboard, trackpad, shortcuts and app selection for 15 min | NOT TESTED | NOT TESTED | NOT TESTED | — |
| Adaptive screen view for 15 min | NOT TESTED | NOT TESTED | NOT TESTED | — |
| 50 sequences with no lost or duplicated command | NOT TESTED | NOT TESTED | NOT TESTED | — |
| No measurable slowdown of the local trackpad | — | — | — | NOT TESTED |

Initial remote pairing succeeds only when a person compares the code and clicks **Allow** in front of the Mac within 60 seconds. No person present, denial or expiry must close the session.

Local evidence from August 29, 2026: Tailscale `Running`, MagicDNS endpoint and CGNAT IPv4 detected by the Nicolas-signed companion, with TLS port 54389 reachable through both the MagicDNS name and Tailscale address. This validates the Mac listener, not yet the complete path from an iPhone over 5G or DERP.
