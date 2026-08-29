# Protocole V2

`ProtocolVersion.current = 2`. Toute enveloppe d’une autre version reçoit `protocolMismatch`, puis la connexion est fermée. Le message utilisateur demande la mise à jour des deux applications.

## Transport

- Bonjour : `_viberemote._tcp`, domaine local (identifiant historique conservé pour la compatibilité des mises à jour) ;
- port de contrôle : 54389 ;
- TLS 1.3 minimum avec certificat épinglé ;
- messages JSON précédés d’une longueur 32 bits big-endian ;
- taille maximale définie dans `ProtocolLimits` ;
- `sessionID`, `sequence`, `messageID`, `replyTo` et timestamp dans chaque enveloppe.

## Appairage

1. Mac → iPhone : `pairing_challenge` avec nonce.
2. iPhone → Mac : `pairing_response` signé, clé publique et secret QR si nouveau.
3. Mac → iPhone : `pairing_pending` avec demande, nom, code et expiration.
4. Clic Mac : `connection_status`, ou erreur `pairing_denied` / `pairing_approval_expired`.

Un appareil connu omet le secret QR et doit prouver la possession de la même clé privée.

## Dictée

`recording_started` retourne dans son ACK un `TargetToken`. `insert_text` contient le texte final et ce token. L’ACK final contient `InsertionResult`. `cancel` consomme la cible. Il n’existe aucun `keyboard_edit` en V2.

La frappe manuelle utilise `keyboard_text` avec `userInitiated = true` et reste distincte de la dictée.

## Contrôles

Les commandes autorisées sont les événements clavier nommés, mouvements/clics/glissements/scroll bornés, inventaire/activation de fenêtre et activation/désactivation du flux écran. Tout type inconnu ou invalide échoue sans exécution générique.

## Idempotence

Un `messageID` déjà exécuté renvoie l’ACK mis en cache. Il ne rejoue jamais l’action. Une séquence inférieure est un rejeu et ferme logiquement la commande.
