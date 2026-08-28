# Vibe Remote

Vibe Remote transforme un iPhone en télécommande locale pour Mac : dictée sur l’appareil, clavier, trackpad, sélection des applications et retour écran facultatif.

La voix ne quitte jamais l’iPhone. Le Mac reçoit seulement du texte et des commandes après un appairage confirmé physiquement. Il n’existe ni compte, ni cloud, ni publicité, ni télémétrie tierce.

## Obtenir l’application

- **iPhone** : version officielle prévue à 14,99 € en achat unique sur l’App Store français.
- **Mac Apple Silicon** : compagnon gratuit distribué sous forme de DMG signé et notarisé depuis le futur site officiel.
- **Code source** : iOS, macOS et `RemoteCore` sont sous licence [MPL-2.0](LICENSE).

L’achat finance le build officiel signé, les mises à jour Sparkle et le support. La licence libre autorise aussi la compilation personnelle avec son propre compte Apple Developer. La marque et les visuels ne sont pas concédés par la MPL ; consultez [TRADEMARKS.md](TRADEMARKS.md).

## Compatibilité V1

- iOS 26 ou supérieur ;
- macOS 15 ou supérieur ;
- Mac Apple Silicon ;
- iPhone et Mac sur le même réseau local.

Le protocole courant est la version 2. Les prototypes V1 ne sont volontairement pas compatibles : réinstallez les deux apps et recommencez l’appairage.

## Compiler

Prérequis développeur : Xcode 26+, Swift 6 et, uniquement pour régénérer les projets, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
swift test --package-path Packages/RemoteCore

xcodebuild \
  -project iOS/AppRemoteiOS.xcodeproj \
  -scheme AppRemoteiOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild \
  -project macOS/AppRemoteMac.xcodeproj \
  -scheme AppRemoteMac \
  CODE_SIGNING_ALLOWED=NO build
```

Les projets Xcode sont versionnés pour qu’un contributeur n’ait rien d’autre à installer que Xcode. Après une modification de `project.yml`, exécutez `xcodegen generate` dans `iOS/` ou `macOS/` et validez aussi le projet régénéré.

Les identifiants de travail sont `com.nicolascleton.viberemote`, `.controls` et `.mac`. Ils seront remplacés avec le nom final avant publication. Pour signer un fork, surchargez l’identifiant et l’équipe dans une configuration locale non versionnée ; aucun certificat, Team ID ou compte personnel n’est requis par les sources.

## Sécurité

Le transport impose TLS 1.3 avec certificat auto-signé par installation et empreinte transmise dans le QR. Les messages sont signés Curve25519, séquencés, limités en taille et en débit. Un nouvel iPhone n’est persisté qu’après le clic **Autoriser** sur le Mac.

La dictée utilise une transaction : capture immédiate de la cible, transcription locale, puis un unique `insert_text` au relâchement. Les champs sécurisés et les cibles modifiées sont refusés.

Voir [l’architecture](Documentation/ARCHITECTURE.md), le [modèle de menace](Documentation/THREAT_MODEL.md) et le [protocole](Documentation/PROTOCOL.md).

## Contribuer et signaler une faille

Lisez [CONTRIBUTING.md](CONTRIBUTING.md). Ne publiez jamais une vulnérabilité exploitable dans une issue : suivez [SECURITY.md](SECURITY.md).

## Statut commercial

La [revue du nom de travail](Documentation/BRAND_REVIEW.md) a trouvé un risque de confusion important : un nouveau nom est requis avant de publier le dépôt ou de figer les identifiants. Une Release Candidate nécessite aussi la notarisation, la validation TestFlight et les essais réels décrits dans [Documentation/RELEASES.md](Documentation/RELEASES.md).
