# Public Name Review

Status on August 29, 2026: **NAME SELECTED AND RESERVED — “Vibe Walkie” is registered in App Store Connect; legal clearance remains to be completed before commercial release**.

This document is a product decision record, not legal advice. An App Store record can be created to test and reserve a name, but availability from Apple is neither legal clearance nor trademark approval.

## Conflicts found

- App `id6759615708` used “Vibe Remote – AI Dev” before being renamed “Btelo Coding – AI Vibe Remote”: <https://apps.apple.com/fr/app/btelo-coding-ai-vibe-remote/id6759615708>.
- <https://vibe-remote.net/> presents a product named exactly “Vibe Remote,” also designed to control a Mac from a phone.
- The `vibe-remote` name is also used in the software ecosystem, including on PyPI.

On August 29, 2026, public search in the French App Store showed no app with the exact title “Vibe Remote.” The decisive check nevertheless failed after registering the bundle ID and attempting to create the App Store Connect record, with the message that the entered app name was already in use. The exact title therefore cannot be reserved on this account without a claim based on industrial or commercial property rights.

The second point alone creates a significant risk of commercial confusion for a neighboring product. The “favorable trademark review” gate is therefore not met, regardless of whether an exact registered trademark exists.

## Checks still required for Vibe Walkie

1. Exact and similarity searches in Data INPI: <https://data.inpi.fr/>.
2. France and European Union searches in TMview, as recommended by EUIPO: <https://www.tmdn.org/tmview/>.
3. App Store, web search, GitHub, domain-name and major package-registry searches.
4. Review of relevant classes with an industrial-property adviser before filing if the trademark is to be protected.

## Final acceptance criteria

- distinctive and pronounceable in French;
- no nearby software product with an identical or strongly similar name;
- usable App Store name, GitHub organization/repository and domain;
- INPI/TMview search with no significant identified risk;
- written approval of the decision before replacing working names, identifiers and URLs.

## Technical renaming decisions

- the product name, iOS/macOS copy, Store metadata and artifacts become `Vibe Walkie`;
- the historical `_viberemote._tcp` Bonjour service remains stable so a partial update breaks neither discovery nor pairing;
- `com.nicolascleton.viberemote*` bundle IDs remain stable because the App Store record and system permissions are already tied to them;
- historical Keychain keys and data paths remain stable so a routine update does not delete the TLS identity or pairings;
- the historical repository, Sparkle feed and domain will be migrated separately to preserve working redirects.

Protocol V2 and local data retain their historical technical identifiers. The rebrand must require neither simultaneous reinstallation nor new pairing.

## Candidate review on August 29, 2026

### Selected name

**Vibe Walkie** was accepted and reserved by successfully creating the App Store Connect record:

- Apple ID : `6806599345` ;
- Bundle ID : `com.nicolascleton.viberemote` ;
- SKU : `VIBENOMADE-IOS-001` ;
- primary language: French.

Exact-match public searches in the French, US and UK App Stores, on the web and in indexed trademark results found no software using this exact name. App Store Connect also accepted the title. This is not legal clearance: similarity searches in Data INPI and TMview, followed by risk assessment in the relevant classes, remain mandatory before commercial release.

### Rejected candidates

- **Vibe Deck**: same-name software that already controls terminals remotely and by voice.
- **Vibe Walk**: same-name product for remotely controlling a development environment from a phone, with a promise centered on working while walking.
- **VibeWork**: iPhone app and software services already operating under this name.
- **Vibe Flow / Vibeflow**: several same-name software products, including a macOS voice-dictation app and a Y Combinator-backed company.
- **Vibe Control**: same-name software extension and strong semantic collision with adult remote-control products.
- **Vibe Active**: existing trademark and telecommunications software service.
- **Vibe Touch**: strong commercial collision with the We-Vibe Touch range and its remote-control features.
- **Vibe Nomad**: available and accepted by Apple, but less directly connected to speaking and controlling a Mac while walking.

### Fallback

**VibeDeskless** showed no exact public conflict in the searches performed. The name was not reserved in App Store Connect and therefore remains a fallback candidate not verified by Apple.
