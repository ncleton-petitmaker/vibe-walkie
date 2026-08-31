# Protocole V3

`ProtocolVersion.current = 3`. Toute enveloppe d’une autre version reçoit `protocolMismatch`, puis la connexion est fermée. Le message utilisateur demande la mise à jour des deux applications.

## Transport

- Bonjour : `_viberemote._tcp`, domaine local (identifiant historique conservé pour la compatibilité des mises à jour) ;
- port de contrôle : 54389 ;
- TLS 1.3 minimum avec certificat épinglé ;
- endpoint Nomade facultatif : nom MagicDNS `*.ts.net`, IPv4 `100.64.0.0/10` facultative, port fixe 54389 ;
- messages JSON précédés d’une longueur 32 bits big-endian ;
- taille maximale définie dans `ProtocolLimits` ;
- `sessionID`, `sequence`, `messageID`, `replyTo` et timestamp dans chaque enveloppe.

## Appairage

1. Mac → iPhone : `pairing_challenge` avec nonce.
2. iPhone → Mac : `pairing_response` signé, clé publique et secret QR si nouveau.
3. Mac → iPhone : `pairing_pending` avec demande, nom, code et expiration.
4. Clic Mac : `connection_status`, ou erreur `pairing_denied` / `pairing_approval_expired`.

Un appareil connu omet le secret QR et doit prouver la possession de la même clé privée.

Le QR local expire après 120 secondes. Le QR Nomade expire après 600 secondes et peut être scanné, importé depuis une image ou collé sous sa forme compacte. Il n’existe volontairement aucun lien web d’appairage. Une connexion non authentifiée est fermée après dix secondes ; le Mac accepte au plus huit sessions en attente et applique une limite globale aux nouvelles connexions.

## Route Nomade

`PairingQRPayload` et `ConnectionStatusPayload` peuvent porter un `NomadEndpoint`. `PairedMac` le mémorise de façon facultative ; l’absence du champ reste décodable. Tailscale ne remplace ni le TLS épinglé, ni la signature Curve25519, ni l’approbation Mac. Le protocole n’utilise pas Serve, Funnel, SSH, OAuth ou l’API d’administration Tailscale.

## Dictée

`recording_started` retourne dans son ACK un `TargetToken`. `insert_text` contient le texte final et ce token. L’ACK final contient `InsertionResult`. `cancel` consomme la cible. Il n’existe aucun `keyboard_edit` en V3.

La frappe manuelle utilise `keyboard_text` avec `userInitiated = true` et reste distincte de la dictée.

## Contrôles

Les commandes autorisées sont les événements clavier nommés, mouvements/clics/glissements/scroll bornés, inventaire/activation de fenêtre et activation/désactivation du flux écran. Tout type inconnu ou invalide échoue sans exécution générique.

Le bloc autour du Push-to-Talk utilise sept `ControlZone`. Le Mac conserve la configuration de référence et l’envoie avec `control_configuration_snapshot`. L’iPhone peut proposer une mise à jour par `control_configuration_update`. Les combinaisons matérielles sont capturées sur le Mac, bornées à un keycode connu de CoreGraphics, puis déclenchées par `mac_shortcut_press`. Les images importées sont redimensionnées et plafonnées afin que la configuration complète reste sous la limite d’une trame.

## Idempotence

Un `messageID` déjà exécuté renvoie l’ACK mis en cache. Il ne rejoue jamais l’action. Une séquence inférieure est un rejeu et ferme logiquement la commande.
