# V1 Release Gate Status

Updated August 29, 2026. `READY` means reproducible local evidence exists; `EXTERNAL` requires an account, certificate, hardware or third-party approval; `BLOCKED` explicitly prevents release.

| Gate | Status | Evidence / next action |
|---|---|---|
| V3 protocol, pairing, transactional dictation and configurable controls | READY | 59 passing `RemoteCore` tests, 18 iOS tests and 39 macOS tests |
| Tailscale Roaming — code and unit tests | READY | Real `Running` detection, MagicDNS/IP, signed listener and port 54389 reachable through the validation Mac's Tailscale address; passing iOS/macOS builds and automated suites |
| Tailscale Roaming — physical matrix | EXTERNAL | Direct, DERP, 5G, sleep and 50 sequences must be documented in [QA_MATRIX.md](QA_MATRIX.md) before public announcement. The development iPhone installation is waiting for a new Nicolas profile because Xcode currently rejects the account session. |
| Self-contained and stable Swift TLS identity | READY | Creation, corruption, stability and regeneration tests |
| iOS Simulator and macOS arm64 builds | READY | `scripts/ci-local.sh`, unsigned iOS/macOS Release builds and verified arm64 DMG |
| Swift and script linting | READY | Strict SwiftLint and ShellCheck |
| Secret and forbidden-file scanning | READY | Gitleaks clean across current history plus CI guard; repeat against final history |
| Documented open-source repository | READY locally | Publication intentionally frozen until the new name |
| Public name available | **BLOCKED** | Exact title absent from public search and Apple form prepared, but a competing product uses the same name; see [BRAND_REVIEW.md](BRAND_REVIEW.md) |
| Developer ID Application certificate | EXTERNAL | Create or download it from the Apple Developer account |
| Signing, notarization, stapling and Gatekeeper | EXTERNAL | Run the Mac workflow with the certificate and notarization credentials |
| Sparkle update between two signed releases | EXTERNAL | Publish two betas after freezing the name and feed |
| Apple Distribution certificate / App Store Connect | EXTERNAL | Configure the individual account, agreements and API key |
| DSA, privacy and export compliance | EXTERNAL | Publish URLs and verify individual-trader and encryption classifications |
| Ten clean installations in under three minutes | EXTERNAL | Run and document [QA_MATRIX.md](QA_MATRIX.md) |
| Public TestFlight beta | EXTERNAL | Requires name, App Store record and signed archive |
| App Store approval | EXTERNAL | Submit manually after all previous gates |
| Signed `1.0.0` tag and final DMG | EXTERNAL | Only after approval and real-device testing |

Version `1.0.0` must not be tagged while any row is `BLOCKED` or `EXTERNAL` without attached evidence.
