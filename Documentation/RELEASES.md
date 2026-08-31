# Release Policy

Vibe Walkie follows semantic versioning. Every release has a changelog, signed tag and French user-facing notes.

## Automated gates

- passing RemoteCore, macOS and iOS tests;
- passing iOS Simulator and macOS arm64 builds;
- passing lint, secret detection and dependency audit;
- validated App Store archive;
- validated Developer ID archive, DMG, notarization, stapling and Gatekeeper;
- EdDSA-signed Sparkle update tested from the previous release.

## Manual gates

- no critical or high-severity defects;
- ten clean installations without a terminal, including accounts without developer tools;
- real-device matrix for iPhone/iOS 26 and Mac/macOS 15+;
- approved TestFlight build with blockers resolved;
- published privacy and DSA information;
- favorable trademark review;
- App Store approval.

The gate summary is in [RELEASE_STATUS.md](RELEASE_STATUS.md). Evidence from physical testing is tracked in [QA_MATRIX.md](QA_MATRIX.md). Public-name status is recorded in [BRAND_REVIEW.md](BRAND_REVIEW.md).

CI never promotes an approved iOS version automatically: release remains manual in App Store Connect. A Mac update is forced only for incompatibility or a critical vulnerability.

## GitHub secrets

The protected `release` environment expects base64-encoded Developer ID and Apple Distribution certificates, their passwords, the App Store Connect API key and `SPARKLE_PRIVATE_KEY`. No secret may be committed or defined as a public variable.
