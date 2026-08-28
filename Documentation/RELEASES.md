# Politique de release

Vibe Remote suit le versionnage sémantique. Chaque release possède un changelog, un tag signé et des notes utilisateur en français.

## Portes automatiques

- tests RemoteCore, macOS et iOS verts ;
- builds iOS Simulator et macOS arm64 verts ;
- lint, détection de secrets et audit de dépendances verts ;
- archive App Store validée ;
- archive Developer ID, DMG, notarisation, stapling et Gatekeeper validés ;
- mise à jour Sparkle signée EdDSA et testée depuis la version précédente.

## Portes manuelles

- zéro défaut critique ou élevé ;
- dix installations propres sans terminal, dont comptes sans outils développeur ;
- matrice réelle iPhone/iOS 26 et Mac/macOS 15+ ;
- TestFlight approuvé et blocages corrigés ;
- confidentialité/DSA publiées ;
- revue de marque favorable ;
- approbation App Store.

Le tableau synthétique des portes est dans [RELEASE_STATUS.md](RELEASE_STATUS.md). Le suivi probant des essais physiques se fait dans [QA_MATRIX.md](QA_MATRIX.md). Le statut du nom public est consigné dans [BRAND_REVIEW.md](BRAND_REVIEW.md).

La CI ne promeut jamais automatiquement une version iOS approuvée : la publication reste manuelle dans App Store Connect. Une mise à jour Mac n’est forcée que pour une incompatibilité ou une faille critique.

## Secrets GitHub

L’environnement protégé `release` attend les certificats Developer ID et Apple Distribution en base64, leurs mots de passe, la clé API App Store Connect et `SPARKLE_PRIVATE_KEY`. Aucun secret ne doit être défini comme variable publique ou commité.
