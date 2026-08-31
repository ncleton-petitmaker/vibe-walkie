# Architecture

## Composants

```text
iPhone (iOS 26+)                       Mac Apple Silicon (macOS 15+)
┌──────────────────────┐               ┌─────────────────────────┐
│ SwiftUI              │               │ SwiftUI / menu bar      │
│ Speech local         │               │ Accessibility / CGEvent │
│ Gestes et dictée     │               │ ScreenCaptureKit        │
│ Client Network       │── TLS 1.3 ───▶│ Serveur Network :54389  │
└──────────┬───────────┘               └────────────┬────────────┘
           └──────── RemoteCore V3 ─────────────────┘
```

`RemoteCore` contient uniquement les modèles, le cadrage, les signatures, l’anti-rejeu et les limites partagés. Il ne dépend d’aucune interface utilisateur.

Le compagnon publie `_viberemote._tcp` avec Bonjour et écoute le port TLS fixe 54389. En mode standard, l’iPhone le découvre sur le LAN. En mode Nomade facultatif, le même listener est atteint directement par le nom MagicDNS ou l’adresse `100.64.0.0/10` fournis par Tailscale. Cet identifiant Bonjour historique reste stable entre les versions. Le serveur n’exécute jamais de chaîne arbitraire : chaque type de message est routé vers une action bornée.

Au lancement, l’iPhone démarre Bonjour immédiatement. Sans connexion TLS prête après 750 ms, il tente en parallèle le nom MagicDNS, puis l’IPv4 Tailscale si la résolution échoue. La première connexion dont le certificat correspond exactement à l’empreinte appairée gagne ; les autres sont annulées. L’écoute Bonjour reste active pendant une session Nomade : lorsque le Mac réapparaît sur le LAN, l’iPhone relance une course avec la même avance locale et revient automatiquement au trajet local. Un délai anti-boucle de dix secondes évite les bascules répétées sur un réseau instable.

## Identité et confiance

Au premier lancement, le Mac crée une clé P-256 permanente et un certificat X.509 auto-signé avec Swift Certificates. Le certificat et la clé sont associés en `SecIdentity` dans le trousseau. L’empreinte SHA-256 est stable jusqu’à une réinitialisation volontaire.

Le QR transporte le nom du Mac, le service Bonjour, l’empreinte TLS, un secret aléatoire et une expiration de 120 secondes. Le QR Nomade ajoute un `NomadEndpoint` facultatif et reste valable dix minutes pour permettre son transfert par image ou code. Après preuve Curve25519, le Mac demande toujours une confirmation humaine de 60 secondes. Seul **Autoriser** persiste la clé publique de l’iPhone.

## Plusieurs Macs

L’iPhone conserve un registre de compagnons, identifié par l’empreinte de leur certificat TLS, ainsi que l’identifiant du Mac sélectionné. Une installation qui ne connaissait qu’un seul Mac est migrée automatiquement vers ce registre. Ajouter un compagnon ne remplace donc plus le précédent.

Une seule session de contrôle est active à la fois. Lorsque l’utilisateur choisit un autre Mac, le client annule la connexion, les tentatives réseau et les réponses en attente de l’ancienne cible, efface son état d’interface, puis démarre un nouveau cycle Local/Nomade avec le certificat du Mac choisi. La même identité Curve25519 de l’iPhone peut être approuvée séparément sur plusieurs Macs ; aucune clé privée n’est dupliquée et aucun compte cloud n’est introduit.

## Transaction de dictée

1. `recording_started` capture immédiatement l’élément AX, la fenêtre, le rôle et le processus.
2. L’iPhone transcrit localement ; aucun texte n’est encore écrit sur le Mac.
3. L’annulation consomme la cible sans insertion.
4. Au relâchement, l’iPhone envoie un unique `insert_text`.
5. Le Mac refuse une cible sécurisée, expirée, absente ou différente.
6. L’iPhone affiche « livré » uniquement après l’ACK contenant le résultat d’insertion.

## Persistance

- iOS : clé Curve25519 dans le trousseau, registre des Macs appairés et cible sélectionnée dans `UserDefaults`. Aucune transcription n’est persistée.
- macOS : identité TLS dans le trousseau, pairs approuvés dans Application Support avec protection jusqu’à la première authentification.
- aucune base distante, aucun identifiant utilisateur et aucune télémétrie ;
- l’endpoint Nomade facultatif contient uniquement un nom `*.ts.net`, une IPv4 Tailscale facultative et le port fixe. Aucun compte ou jeton Tailscale n’entre dans `RemoteCore`.
