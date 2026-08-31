# Contributing to Vibe Walkie

Please keep changes small, tested and easy to review.

1. Open an issue for significant protocol, security or user-experience changes.
2. Create a branch from `main`.
3. Add or update tests before opening the pull request.
4. Run `Scripts/ci-local.sh`.
5. Describe risks, validation and any required migration in the pull request.

All contributions are provided under MPL-2.0. You certify that you are authorized to submit them. Do not commit third-party artwork, fonts, screenshots, secrets, UDIDs, IP addresses or certificates.

Protocol V2 interfaces are public and must remain compatible within the same major version. Any format change requires documentation in `Documentation/PROTOCOL.md`, a round-trip test and an explicit incompatibility strategy.

Formatting follows the SwiftFormat bundled with Xcode; SwiftLint blocks straightforward mistakes. Xcode warnings must be addressed, not hidden.
