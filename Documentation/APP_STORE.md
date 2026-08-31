# Dossier App Store V1

> Le dossier de contenu est prêt dans [`Store/fr-FR`](../Store/fr-FR/). Le nom, les URLs et les identifiants définitifs sont bloqués par la [revue de marque](BRAND_REVIEW.md).

- Territoire : France.
- Langue : français.
- Prix : 14,99 €, achat initial unique.
- Aucun abonnement, IAP, compte, publicité ou tracking.
- Vendeur : Nicolas Cléton, individuel.
- Statut DSA attendu pour cette activité commerciale : trader individuel, coordonnées vérifiées dans App Store Connect.

## Notes de revue

Le compagnon Mac signé et notarisé sera disponible à l’URL publique renseignée après validation du nom. L’onboarding explique le téléchargement, le QR et l’approbation sur le Mac. Le mode **Découvrir sans Mac** est en lecture seule et ne simule aucune commande réussie.

La caméra n’est demandée qu’à l’ouverture du scanner. Le microphone et Speech ne sont demandés qu’au premier démarrage d’une dictée. L’Accessibilité est requise sur le Mac pour cibler et insérer ; la Capture d’écran n’est demandée qu’à l’activation facultative du retour écran.

Le mode Nomade V1.1 est facultatif et nécessite l’application Tailscale installée séparément. Aucun compte ou jeton Tailscale n’est transmis à Vibe Walkie. La revue peut utiliser le parcours local sans Tailscale ; les notes de revue décrivent aussi le test Nomade et sa validation humaine obligatoire sur le Mac.

App Privacy : aucune donnée collectée par le développeur, aucun tracking et aucun historique de dictées. Le chiffrement repose sur les API système et des bibliothèques open source ; `ITSAppUsesNonExemptEncryption` vaut `false` sous réserve de confirmation finale dans App Store Connect.
