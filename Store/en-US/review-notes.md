# App Review notes — en-US

> V1.1 draft. Remove the Remote Mode section while its Release flag remains disabled.

Vibe Walkie normally requires its macOS 15+ Apple silicon companion. The signed and notarized review DMG will be available at `{{REVIEW_DMG_URL}}`.

## Review without a Mac

On the welcome screen, choose **Explore without a Mac**. This is a clearly labeled, read-only tour. It sends no commands, opens no connection, and never claims that an action succeeded.

## Review with a Mac

1. Install the companion in `/Applications` from the DMG.
2. Open the companion; no account is requested.
3. Grant Accessibility when the guided flow explains why.
4. On iPhone, choose **Add a Mac** and scan the QR code.
5. Compare the displayed code, then click **Allow** on the Mac.
6. Open Notes on the Mac and hold the dictation button on iPhone.

Camera access is requested only when the scanner opens. Microphone and speech-recognition access are requested only on first dictation use. Mac Screen Recording is requested only when optional Screen View is first used.

Audio and transcription remain on the iPhone. The app supports French and English interface and dictation choices; Apple’s on-device speech model is checked before use.

Standard operation is direct over the local network. Optional Remote Mode uses the separately installed Tailscale app on iPhone and Mac; it uses no Vibe Walkie server, account, OAuth token, Funnel, or administration API. Pinned TLS 1.3 and explicit Vibe Walkie approval remain required.

The app contains no subscription, in-app purchase, advertising, third-party analytics, or hidden feature.

Review contact: `{{REVIEW_CONTACT}}`.
