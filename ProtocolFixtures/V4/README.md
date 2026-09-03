# Vibe Walkie protocol V4 fixtures

These files are the language-neutral compatibility contract for Swift, Kotlin
and C#. JSON is UTF-8, keys are sorted when encoded, dates are ISO-8601 UTC,
UUIDs use their canonical string representation and byte arrays use standard
base64. A TCP record is a four-byte unsigned big-endian length followed by one
JSON envelope. Implementations must reject records larger than 524288 bytes.

Every Swift, Kotlin and C# implementation consumes these exact files.
`control-configuration-palette.json` proves that a companion exposes only
opaque shortcut references and their display metadata, never hardware keys.
`signature-ed25519.json` uses a deterministic test key only; it is never
included as an application identity.
`errors.json`, `framing.json` and `screen-frame.json` keep the error surface,
the TCP record limits and binary JPEG/base64 fields compatible across all
three implementations.
