# Publication Apple sans connexion web

Les publications courantes utilisent la clé API App Store Connect installée
hors du dépôt sur les deux Mac :

`~/Library/Application Support/Vibe Walkie Release Tools/App Store Connect/credentials.env`

Ce fichier et la clé privée associée doivent rester en mode `0600`. Il ne faut
jamais les copier dans Git, dans un journal ou dans une commande partagée.

## TestFlight

Depuis le Mac de développement :

```bash
./scripts/publish-testflight.sh
```

Cette commande déclenche l'archive dans la session graphique du Mac mini,
exporte et envoie l'IPA avec la clé API, attend le traitement Apple, puis affecte
la build aux groupes `Bêta publique Vibe Walkie` et `Équipe Vibe Walkie`.

Les diagnostics restent sur le Mac mini :

- `~/Desktop/Vibe Walkie TestFlight release.log`
- `~/Desktop/Vibe Walkie TestFlight release.status`

Le contrôle non destructif des prérequis se lance avec :

```bash
./scripts/publish-testflight.sh --check
```

## Compagnon Mac

```bash
VERSION=1.0.9 \
NOTES="Résumé des changements" \
INSTALL_AFTER_PUBLISH=1 \
./scripts/publish-macos-update.sh
```

Le script charge automatiquement les identifiants locaux, construit le binaire
universel, le signe, le notarise, l'agrafe, publie l'appcast et vérifie que le
DMG téléchargé correspond exactement au DMG envoyé.

Le compagnon vérifie normalement l'appcast toutes les quatre heures. Pour
afficher immédiatement la fenêtre Sparkle et rechercher une mise à jour :

```bash
./scripts/check-macos-update-now.sh
```

Cette commande utilise l'URL locale
`vibewalkie-mac://check-for-updates` ; elle ne contacte pas App Store Connect et
ne nécessite aucune authentification.

## Quand une connexion App Store Connect reste nécessaire

Une connexion web n'est requise que pour une opération administrative rare :
révoquer ou créer une clé API, accepter un nouveau contrat Apple, ou modifier
les droits du compte. Une publication normale ne doit jamais la demander.
