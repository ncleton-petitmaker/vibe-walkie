# App Privacy answers — en-US

Planned App Store Connect answer: **No, we do not collect data from this app**.

- There is no account identifier because there is no account.
- No advertising or cross-app tracking.
- No third-party analytics, advertising, or crash-reporting SDK.
- Audio stays on the iPhone and is not sent to the developer or the Mac.
- Text and commands go only to the approved Mac, directly over the local network or the user’s optional Tailscale network. The developer does not receive them.
- Dictation transcripts are not retained in a history.
- Remote Mode does not read Tailscale accounts, OAuth tokens, or ACLs. It stores the Mac MagicDNS name and optional Tailscale address locally.
- Sparkle is used only by the Mac companion and system profiling is disabled.

Before submission, compare this declaration with the final binary and every dependency. Any future remote diagnostics require a new privacy review and updated answers.

Public URL: `https://vibewalkie.app/en/privacy`.
