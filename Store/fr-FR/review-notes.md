# Notes pour l’équipe App Review

> Brouillon V1.1. Retirer la section Nomade tant que le drapeau Release reste désactivé.

Vibe Walkie requiert normalement son compagnon macOS 15+ Apple Silicon. Le DMG de revue signé et notarisé sera disponible ici : `{{REVIEW_DMG_URL}}`.

## Revue sans Mac

Depuis l’écran d’accueil, choisir **Découvrir sans Mac**. Ce mode est entièrement en lecture seule, utilise des données clairement simulées, n’ouvre aucune connexion et ne prétend jamais qu’une commande a été exécutée.

## Revue avec un Mac

1. Installer le compagnon dans `/Applications` depuis le DMG.
2. Ouvrir le compagnon ; aucun compte n’est demandé.
3. Accorder Accessibilité lorsque le parcours guidé l’explique.
4. Dans l’app iPhone, choisir **Connecter mon Mac** et scanner le QR.
5. Comparer le code affiché, puis cliquer **Autoriser** sur le Mac.
6. Ouvrir Notes sur le Mac et maintenir le bouton de dictée sur l’iPhone.

La caméra est demandée uniquement à l’ouverture du scanner. Le microphone et la reconnaissance vocale sont demandés uniquement au premier usage de la dictée. La permission Capture d’écran du Mac n’est demandée qu’au premier usage du retour écran facultatif.

Le fonctionnement standard est direct sur le réseau local. Le mode Nomade facultatif utilise l’application Tailscale installée séparément sur l’iPhone et le Mac ; il n’utilise aucun serveur, compte, jeton OAuth, Funnel ou API d’administration Vibe Walkie. Tailscale peut établir une liaison directe ou utiliser son relais DERP chiffré. Le TLS 1.3 épinglé et l’approbation Vibe Walkie restent obligatoires.

## Test facultatif du mode Nomade

1. Connecter l’iPhone et le Mac au même tailnet Tailscale.
2. Sur le Mac, ouvrir **Mode Nomade**, vérifier le nom MagicDNS puis choisir **Activer**.
3. Utiliser **Appairer un iPhone à distance** et transférer le QR sous forme d’image ou copier le code compact.
4. Sur l’iPhone, importer l’image ou coller le code.
5. Comparer le code à six chiffres et cliquer **Autoriser** devant le Mac dans les 60 secondes.
6. Quitter le Wi‑Fi local et choisir **Tester la connexion** : l’état devient **Nomade · Tailscale**.

L’app ne contient ni abonnement, achat intégré, publicité, télémétrie tierce ou fonction cachée.

Contact de revue : `{{REVIEW_CONTACT}}`.
