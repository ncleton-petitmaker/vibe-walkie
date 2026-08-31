<p align="center">
  <img src="Brand/VibeWalkieIcon-source.png" width="112" alt="Icône Vibe Walkie">
</p>

<h1 align="center">Vibe Walkie</h1>

<p align="center">
  <strong>Le travail sans le bureau.</strong><br>
  Marchez, parlez et gardez votre Mac sous le pouce depuis votre iPhone.
</p>

<p align="center">
  <a href="https://vibewalkie.app">Site officiel</a>
  ·
  <a href="https://testflight.apple.com/join/9AUshVWm">TestFlight</a>
  ·
  <a href="#compiler-le-projet">Compiler le projet</a>
  ·
  <a href="CONTRIBUTING.md">Contribuer</a>
</p>

<p align="center">
  <img alt="iOS 26+" src="https://img.shields.io/badge/iOS-26%2B-111111?logo=apple">
  <img alt="macOS 15+" src="https://img.shields.io/badge/macOS-15%2B-111111?logo=apple">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white">
  <img alt="Local et Tailscale" src="https://img.shields.io/badge/réseau-local%20%2B%20Tailscale-0A84FF">
  <a href="LICENSE"><img alt="Licence MPL 2.0" src="https://img.shields.io/badge/licence-MPL--2.0-7B42BC"></a>
</p>

Vibe Walkie transforme l’iPhone en télécommande pour Mac : dictée sur l’appareil, clavier, trackpad, sélection des applications et retour d’écran facultatif. La connexion est locale par défaut ; le mode Nomade peut emprunter votre propre réseau Tailscale. Aucun compte Vibe Walkie, abonnement ou serveur Vibe Walkie n’est nécessaire.

## Nouveautés

- **Multi‑Mac** — associez plusieurs Macs au même iPhone et changez de machine depuis le bouton en haut à gauche.
- **Mode Nomade** — rejoignez votre Mac à distance via Tailscale, avec retour automatique au réseau local lorsqu’il est disponible.
- **Commandes personnalisables** — organisez les touches rapides, leurs noms et leurs icônes selon votre façon de travailler.
- **Contrôle plus complet** — clavier intégré, pavé tactile amélioré et retour d’écran réunis dans la même télécommande.

## Vibe Walkie en images

<p align="center">
  <img src="Store/fr-FR/screenshots/iphone-6.9/01-travail-sans-bureau.png" width="31%" alt="Travaillez sans rester devant le bureau avec Vibe Walkie">
  &nbsp;
  <img src="Store/fr-FR/screenshots/iphone-6.9/02-dictee-en-marchant.png" width="31%" alt="Dictez à votre Mac en marchant">
  &nbsp;
  <img src="Store/fr-FR/screenshots/iphone-6.9/03-depuis-le-canape.png" width="31%" alt="Contrôlez votre Mac depuis le canapé">
</p>

<p align="center">
  <img src="Store/fr-FR/screenshots/iphone-6.9/04-controle-ecran.png" width="31%" alt="Retour d’écran et commandes Mac sur l’iPhone">
  &nbsp;
  <img src="Store/fr-FR/screenshots/iphone-6.9/05-changer-application.png" width="31%" alt="Changez d’application Mac depuis l’iPhone">
  &nbsp;
  <img src="Store/fr-FR/screenshots/iphone-6.9/06-multi-mac-nomade.png" width="31%" alt="Choisissez entre plusieurs Macs et contrôlez-les localement ou via Tailscale">
</p>

## Ce que l’app permet

| Fonction | Expérience |
| --- | --- |
| **Dicter en marchant** | Maintenez le bouton, parlez, puis relâchez pour envoyer le texte final dans le champ actif. |
| **Piloter le pointeur** | Déplacez le curseur, cliquez et faites défiler depuis le pavé tactile de l’iPhone. |
| **Changer d’application** | Retrouvez les fenêtres ouvertes sur le Mac et activez la bonne cible du pouce. |
| **Voir l’écran du Mac** | Activez le retour visuel uniquement lorsque vous en avez besoin. |
| **Garder les gestes utiles** | Clavier, Effacer, Espace, Entrée et raccourcis restent immédiatement accessibles. |
| **Changer de Mac** | Associez plusieurs compagnons et basculez vers la bonne machine depuis le sélecteur « Mes Macs ». |
| **Travailler à distance** | Utilisez le réseau local en priorité, puis votre tailnet Tailscale lorsque le Mac est ailleurs. |
| **Personnaliser les commandes** | Configurez les sept boutons visibles et la palette globale avec vos touches, noms et icônes. |

La voix ne quitte jamais l’iPhone. Le Mac reçoit uniquement le texte final et les commandes validées, après un appairage confirmé physiquement.

## Comment ça fonctionne

1. Ouvrez le compagnon Vibe Walkie sur le Mac.
2. Scannez son QR avec l’iPhone ; utilisez le QR Nomade si le Mac est à distance.
3. Confirmez l’iPhone depuis la demande affichée sur le Mac.
4. Dictez, pointez ou changez d’application depuis l’iPhone.
5. Répétez l’appairage sur vos autres Macs, puis changez de machine depuis le bouton en haut à gauche.

Le mode Nomade facultatif se configure ensuite depuis le compagnon Mac. Il détecte Tailscale sans modifier le tailnet ni ses ACL, et conserve l’approbation humaine de chaque nouvel iPhone.

```text
┌──────────────┐   local ou Tailscale + TLS 1.3   ┌─────────────────┐
│    iPhone    │  ─────────────────────────────▶  │       Mac       │
│ voix + gestes│  ◀─────────────────────────────  │ texte + contrôle│
└──────────────┘       aucun serveur Vibe Walkie   └─────────────────┘
```

## Obtenir l’application

### Version officielle

- **iPhone** — la bêta publique est [disponible via TestFlight](https://testflight.apple.com/join/9AUshVWm), sous réserve de l’approbation bêta d’Apple. La version commerciale est prévue à **14,99 €**, en achat unique sur l’App Store français.
- **Mac Apple Silicon** — le compagnon gratuit sera proposé sur [vibewalkie.app](https://vibewalkie.app) dans un DMG signé et notarisé.

L’achat finance le build officiel signé, les mises à jour et l’assistance. Le code reste librement compilable avec votre propre compte Apple Developer.

### Compiler soi-même

Le dépôt contient l’app iOS, le compagnon macOS, le protocole partagé `RemoteCore`, les tests et la documentation de publication.

## Compatibilité

- iOS 26 ou supérieur ;
- macOS 15 ou supérieur ;
- Mac Apple Silicon ;
- iPhone et Mac sur le même réseau local pour le fonctionnement standard ;
- pour le mode Nomade : Tailscale installé séparément sur les deux appareils et accès au même tailnet (ou Mac partagé).

Le protocole courant est la **version 3**. Les versions antérieures ne sont volontairement pas compatibles : mettez à jour les deux applications ensemble.

## Compiler le projet

### Prérequis

- Xcode 26 ou supérieur ;
- Swift 6 ;
- [XcodeGen](https://github.com/yonaskolb/XcodeGen), uniquement pour régénérer les projets après une modification de `project.yml`.

Les projets Xcode sont versionnés : un premier build ne demande donc rien d’autre que Xcode.

```bash
# Tests du cœur partagé
swift test --package-path Packages/RemoteCore

# App iOS — simulateur, sans signature
xcodebuild \
  -project iOS/AppRemoteiOS.xcodeproj \
  -scheme AppRemoteiOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build

# Compagnon macOS — sans signature
xcodebuild \
  -project macOS/AppRemoteMac.xcodeproj \
  -scheme AppRemoteMac \
  CODE_SIGNING_ALLOWED=NO build
```

Après une modification de `project.yml`, exécutez `xcodegen generate` dans `iOS/` ou `macOS/`, puis validez également le projet régénéré.

Les Bundle IDs `com.nicolascleton.viberemote`, `.controls` et `.mac` restent stables car ils sont déjà liés à la fiche App Store et aux autorisations locales. Ils ne sont pas visibles par les utilisateurs. Pour signer un fork, surchargez l’identifiant et l’équipe dans une configuration locale non versionnée.

## Architecture du dépôt

```text
Vibe Walkie
├── iOS/                    application iPhone SwiftUI
├── macOS/                  compagnon Mac SwiftUI
├── Packages/RemoteCore/    protocole et modèles partagés
├── Store/                  visuels et métadonnées App Store
├── Documentation/          architecture, sécurité et releases
└── scripts/                outils de build et de validation
```

Pour aller plus loin : [architecture](Documentation/ARCHITECTURE.md) · [protocole](Documentation/PROTOCOL.md) · [modèle de menace](Documentation/THREAT_MODEL.md).

## Sécurité et confidentialité

- TLS 1.3 avec une identité propre à chaque installation Mac ;
- empreinte du certificat transmise dans le QR d’appairage ;
- messages signés Curve25519, séquencés, bornés en taille et limités en débit ;
- approbation explicite de chaque nouvel iPhone sur le Mac ;
- capture et revérification de la cible avant toute insertion dictée ;
- refus de la dictée dans les champs sécurisés ;
- aucune publicité ni télémétrie tierce.

Tailscale est facultatif et agit uniquement comme transport réseau. Vibe Walkie ne reçoit ni compte, ni jeton OAuth, ni configuration d’ACL Tailscale ; l’empreinte TLS du Mac reste l’autorité d’authentification.

Une vulnérabilité ne doit jamais être publiée directement dans une issue. Suivez la procédure de signalement décrite dans [SECURITY.md](SECURITY.md).

## Contribuer

Les contributions sont bienvenues : correction, test, accessibilité, documentation ou proposition de protocole. Commencez par lire [CONTRIBUTING.md](CONTRIBUTING.md) et le [code de conduite](CODE_OF_CONDUCT.md).

## Licence et marque

Le code iOS, macOS et `RemoteCore` est publié sous [MPL-2.0](LICENSE). La marque **Vibe Walkie** et ses visuels restent protégés séparément ; consultez [TRADEMARKS.md](TRADEMARKS.md).

Le statut de préparation commerciale et les portes restantes sont suivis dans [Documentation/RELEASE_STATUS.md](Documentation/RELEASE_STATUS.md).
