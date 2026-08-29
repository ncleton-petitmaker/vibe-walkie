# Architecture

## Composants

```text
iPhone (iOS 26+)                       Mac Apple Silicon (macOS 15+)
┌──────────────────────┐               ┌─────────────────────────┐
│ SwiftUI              │               │ SwiftUI / menu bar      │
│ Speech local         │               │ Accessibility / CGEvent │
│ Historique protégé   │               │ ScreenCaptureKit        │
│ Client Network       │── TLS 1.3 ───▶│ Serveur Network         │
└──────────┬───────────┘               └────────────┬────────────┘
           └──────── RemoteCore V2 ─────────────────┘
```

`RemoteCore` contient uniquement les modèles, le cadrage, les signatures, l’anti-rejeu et les limites partagés. Il ne dépend d’aucune interface utilisateur.

Le compagnon publie `_viberemote._tcp` avec Bonjour et écoute uniquement le réseau local. Cet identifiant historique reste stable entre les versions. Il n’exécute jamais de chaîne arbitraire : chaque type de message est routé vers une action bornée.

## Identité et confiance

Au premier lancement, le Mac crée une clé P-256 permanente et un certificat X.509 auto-signé avec Swift Certificates. Le certificat et la clé sont associés en `SecIdentity` dans le trousseau. L’empreinte SHA-256 est stable jusqu’à une réinitialisation volontaire.

Le QR transporte le nom du Mac, le service Bonjour, l’empreinte TLS, un secret aléatoire et une expiration de 120 secondes. Après preuve Curve25519, le Mac demande une confirmation humaine de 60 secondes. Seul **Autoriser** persiste la clé publique de l’iPhone.

## Transaction de dictée

1. `recording_started` capture immédiatement l’élément AX, la fenêtre, le rôle et le processus.
2. L’iPhone transcrit localement ; aucun texte n’est encore écrit sur le Mac.
3. L’annulation consomme la cible sans insertion.
4. Au relâchement, l’iPhone envoie un unique `insert_text`.
5. Le Mac refuse une cible sécurisée, expirée, absente ou différente.
6. L’iPhone affiche « livré » uniquement après l’ACK contenant le résultat d’insertion.

## Persistance

- iOS : clé Curve25519 dans le trousseau, Mac appairé dans `UserDefaults`, historique protégé dans Application Support.
- macOS : identité TLS dans le trousseau, pairs V2 dans Application Support avec protection jusqu’à la première authentification.
- aucune base distante, aucun identifiant utilisateur et aucune télémétrie.
