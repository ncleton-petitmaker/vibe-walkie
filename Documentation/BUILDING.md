# Reproducible Builds

## Requirements

- macOS with Xcode 26 or later;
- Swift 6;
- XcodeGen only when `project.yml` changes;
- no Homebrew, OpenSSL, server or shell required by the end user.

## Tests and unsigned builds

Run `scripts/ci-local.sh`. The script tests RemoteCore, regenerates projects when XcodeGen is available, then builds iOS Simulator and macOS arm64 without signing.

## Signing a fork

Do not edit the working identifiers directly. Copy `Config/Developer.example.xcconfig` to `Config/Developer.xcconfig`, enter the five identifiers and your Team ID, then add `-xcconfig Config/Developer.xcconfig` to your `xcodebuild` command. Git ignores this file.

A personal iOS installation requires an Apple Developer account and is subject to Apple's usual provisioning limits. The Mac companion can be launched from Xcode during development; distributing it to other users requires Developer ID and notarization.

## Dependencies

Exact versions are declared in `macOS/project.yml` and pinned in `Package.resolved`. Review every dependency update, its license and its effect on the privacy manifest.
