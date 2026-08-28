# Matrice de validation réelle V1

Cette matrice est une porte de sortie. Une case ne passe à `RÉUSSI` qu’avec une date, un testeur, les modèles/versions utilisés et un lien vers le rapport ou le ticket. `NON TESTÉ` n’est jamais équivalent à une réussite.

## Installations propres sans terminal

| N° | Mac / macOS | Compte sans outils dev | Réseau | Temps DMG → 1re dictée | Résultat | Preuve |
|---:|---|:---:|---|---:|---|---|
| 01 | À renseigner | Oui | À renseigner | — | NON TESTÉ | — |
| 02 | À renseigner | Oui | À renseigner | — | NON TESTÉ | — |
| 03 | À renseigner | Oui | À renseigner | — | NON TESTÉ | — |
| 04 | À renseigner | Oui | À renseigner | — | NON TESTÉ | — |
| 05 | À renseigner | Oui | À renseigner | — | NON TESTÉ | — |
| 06 | À renseigner | Oui | À renseigner | — | NON TESTÉ | — |
| 07 | À renseigner | Oui | À renseigner | — | NON TESTÉ | — |
| 08 | À renseigner | Oui | À renseigner | — | NON TESTÉ | — |
| 09 | À renseigner | Oui | À renseigner | — | NON TESTÉ | — |
| 10 | À renseigner | Oui | À renseigner | — | NON TESTÉ | — |

Objectif UX : chacune des dix installations doit permettre une première dictée en moins de trois minutes après le téléchargement, sans Homebrew, Xcode ni Terminal.

## Appareils et systèmes

- [ ] Plusieurs iPhone physiques sous iOS 26.
- [ ] Plusieurs Mac Apple Silicon sous macOS 15 ou ultérieur.
- [ ] Compte administrateur et compte standard macOS.
- [ ] Tailles d’écran et tailles de texte iOS variées.
- [ ] VoiceOver, contraste accru et réduction des animations.

## Réseau et cycle de vie

- [ ] Plusieurs Wi-Fi domestiques.
- [ ] Pare-feu macOS actif.
- [ ] Changement de réseau local.
- [ ] Veille/réveil iPhone et Mac.
- [ ] Redémarrage des deux appareils.
- [ ] Perte réseau pendant dictée, commande et retour écran.

## Applications cibles

| Cible | Dictée | Clavier | Trackpad | Changement de champ refusé | Champ sécurisé refusé |
|---|---|---|---|---|---|
| Notes | NON TESTÉ | NON TESTÉ | NON TESTÉ | NON TESTÉ | N/A |
| Mail | NON TESTÉ | NON TESTÉ | NON TESTÉ | NON TESTÉ | N/A |
| Safari | NON TESTÉ | NON TESTÉ | NON TESTÉ | NON TESTÉ | NON TESTÉ |
| Chrome | NON TESTÉ | NON TESTÉ | NON TESTÉ | NON TESTÉ | NON TESTÉ |
| Slack/Teams | NON TESTÉ | NON TESTÉ | NON TESTÉ | NON TESTÉ | N/A |
| Pages | NON TESTÉ | NON TESTÉ | NON TESTÉ | NON TESTÉ | N/A |

## Distribution et mise à jour

- [ ] Montage du DMG et glisser-déposer vers Applications.
- [ ] Lancement accidentel depuis le DMG expliqué et récupérable.
- [ ] Accessibilité guidée avec vérification au retour.
- [ ] Capture d’écran jamais demandée avant le premier retour écran.
- [ ] Premier appairage et approbation Mac.
- [ ] Reconnexion après redémarrage.
- [ ] Révocation d’un iPhone et remise à zéro totale.
- [ ] Mise à jour Sparkle entre deux DMG signés.
- [ ] Désinstallation documentée et vérifiée.

## Bêta publique

Le formulaire TestFlight doit recueillir : appareil/OS, installation du compagnon, compréhension des permissions, appairage, temps jusqu’à la première dictée, stabilité, retour écran, désinstallation et consentement à être recontacté. Chaque anomalie critique ou élevée bloque la Release Candidate.
