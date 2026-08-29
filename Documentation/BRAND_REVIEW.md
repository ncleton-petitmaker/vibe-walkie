# Revue du nom public

Statut au 29 août 2026 : **BLOQUÉ POUR LA PUBLICATION COMMERCIALE — réservation Apple en cours, risque de confusion non levé**.

Ce document est un dossier de décision produit, pas un avis juridique. Une fiche App Store peut être créée pour tester et réserver le nom, mais sa disponibilité chez Apple ne vaut ni disponibilité juridique ni validation de marque.

## Conflits trouvés

- L’application `id6759615708` a utilisé « Vibe Remote – AI Dev » avant d’être renommée « Btelo Coding – AI Vibe Remote » : <https://apps.apple.com/fr/app/btelo-coding-ai-vibe-remote/id6759615708>.
- Le site <https://vibe-remote.net/> présente un produit nommé exactement « Vibe Remote », lui aussi destiné à piloter un Mac depuis un téléphone.
- Le nom `vibe-remote` est également utilisé dans l’écosystème logiciel, notamment sur PyPI.

Le 29 août 2026, la recherche publique de l’App Store français ne montrait aucune app portant exactement le titre « Vibe Remote ». Le formulaire « Nouvelle app » d’App Store Connect accepte le texte sans erreur immédiate ; la réponse définitive nécessite l’enregistrement du Bundle ID puis la création de la fiche.

Le second point suffit à créer un risque important de confusion commerciale pour un produit voisin. La porte « revue de marque favorable » n’est donc pas franchie, indépendamment de l’existence ou non d’une marque enregistrée exacte.

## Vérifications encore requises pour le prochain nom

1. Recherche à l’identique et par similarité dans Data INPI : <https://data.inpi.fr/>.
2. Recherche France et Union européenne dans TMview, recommandé par l’EUIPO : <https://www.tmdn.org/tmview/>.
3. Recherche App Store, moteurs web, GitHub, noms de domaine et principaux registres de paquets.
4. Vérification des classes pertinentes avec un conseil en propriété industrielle avant le dépôt si la marque doit être protégée.

## Critères d’acceptation du prochain nom

- distinctif en français et prononçable ;
- aucun produit logiciel proche portant un nom identique ou fortement similaire ;
- nom App Store, organisation/dépôt GitHub et domaine exploitables ;
- recherche INPI/TMview sans risque significatif identifié ;
- validation écrite de la décision avant de remplacer les noms, identifiants et URLs de travail.

## Éléments provisoires à remplacer ensemble

- nom produit et textes `Vibe Remote` ;
- identifiants `com.nicolascleton.viberemote*` ;
- service Bonjour `_viberemote._tcp` ;
- dépôt et URLs `vibe-remote` ;
- clés de trousseau, noms de certificats, feed Sparkle, politique de marque et visuels commerciaux.

Le protocole V2 et les données locales du prototype n’ont aucune obligation de migration vers le futur nom : une réinstallation et un nouvel appairage sont déjà assumés.
