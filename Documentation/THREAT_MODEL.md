# Modèle de menace

## Actifs

- texte dicté et historique local ;
- capacité de frappe, clic et pilotage du Mac ;
- images du retour écran ;
- clés d’appareil, identité TLS et secret éphémère d’appairage ;
- chaîne de mise à jour et certificats de distribution.

## Adversaires considérés

- appareil hostile sur le même Wi‑Fi ;
- interception ou empoisonnement de la découverte Bonjour ;
- capture/rejeu de trames ;
- QR photographié mais expiré ;
- iPhone précédemment autorisé puis révoqué ;
- cible AX changée pendant la dictée ;
- compromission d’un artefact de mise à jour ;
- contribution publique contenant un secret.

## Mesures

| Menace | Mesure |
|---|---|
| Interception locale | TLS 1.3 et empreinte exacte transmise hors bande par QR |
| Faux iPhone | signature Curve25519, secret QR et approbation explicite sur le Mac |
| Rejeu | séquences monotones, identifiants de message et cache d’ACK idempotent |
| Déni de service | trames et payloads bornés, rate limiting, une approbation en attente |
| Mauvaise cible | capture AX immédiate, token court, identité stricte, refus des champs sécurisés |
| Double insertion | un seul `insert_text`, consommation du token, ACK rejoué sans réexécution |
| Mise à jour falsifiée | Developer ID, notarisation, EdDSA Sparkle et HTTPS GitHub |
| Secret dans Git | Gitleaks, Dependabot, revue et environnement `release` protégé |

## Limites assumées

Un Mac ou iPhone déjà compromis au niveau du compte utilisateur peut lire ce que cet utilisateur voit ou saisit. Le protocole ne protège pas contre un attaquant ayant déverrouillé physiquement les deux appareils. Bonjour révèle la présence du service sur le LAN. Le retour écran transmet nécessairement les pixels affichés à l’iPhone autorisé.

## Hors périmètre V1

Accès Internet, comptes, multi-tenant, synchronisation cloud, Mac Intel et compatibilité protocole V1.
