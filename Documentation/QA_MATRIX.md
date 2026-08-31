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

## Plusieurs Macs

- [ ] Migration d’une installation mono-Mac sans nouvel appairage.
- [ ] Ajout d’un deuxième puis d’un troisième compagnon sans écraser les précédents.
- [ ] Bascule A → B → A sur le même LAN, sans commande livrée à l’ancienne cible.
- [ ] Bascule entre un Mac local et un Mac accessible uniquement par Tailscale.
- [ ] Annulation/refus d’un nouvel appairage puis reconnexion au Mac précédent.
- [ ] Oubli du Mac actif avec sélection automatique du compagnon restant.
- [ ] Oubli d’un Mac inactif sans interrompre la session courante.
- [ ] Deux Macs portant le même nom restent distingués par leur certificat.

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

## Mode Nomade V1.1

Le site ne peut annoncer ce mode comme disponible qu’après validation de toutes les lignes suivantes.

| Scénario | Direct Tailscale | DERP | 5G | Résultat / preuve |
|---|:---:|:---:|:---:|---|
| Tailscale absent, arrêté ou déconnecté expliqué clairement | — | — | — | NON TESTÉ |
| MagicDNS indisponible, repli IPv4 `100.64.0.0/10` | — | — | — | NON TESTÉ |
| ACL bloquante et certificat falsifié refusés | — | — | — | NON TESTÉ |
| Course Local/Nomade, annulation du perdant et retour automatique au LAN | — | — | — | Priorité de route automatisée ; course physique restante |
| Veille/réveil et Wi‑Fi → 5G, reconnexion < 10 s une fois joignable | — | — | — | NON TESTÉ |
| QR par caméra, image et code ; autorisation/refus/expiration/rejeu | — | — | — | NON TESTÉ |
| Dictée, clavier, trackpad, raccourcis et sélection d’apps pendant 15 min | NON TESTÉ | NON TESTÉ | NON TESTÉ | — |
| Retour écran adaptatif pendant 15 min | NON TESTÉ | NON TESTÉ | NON TESTÉ | — |
| 50 séquences sans commande perdue ni dupliquée | NON TESTÉ | NON TESTÉ | NON TESTÉ | — |
| Aucun ralentissement mesurable du trackpad local | — | — | — | NON TESTÉ |

Le premier appairage distant n’est réussi que si une personne compare le code et clique **Autoriser** devant le Mac dans les 60 secondes. Une absence de personne, un refus ou une expiration doivent fermer la session.

Preuve locale du 29 août 2026 : Tailscale `Running`, endpoint MagicDNS et IPv4 CGNAT détectés par le compagnon signé Nicolas, et port TLS 54389 joignable via le nom MagicDNS et l’adresse Tailscale. Cette preuve valide le listener Mac, pas encore le trajet complet depuis l’iPhone en 5G ou via DERP.
