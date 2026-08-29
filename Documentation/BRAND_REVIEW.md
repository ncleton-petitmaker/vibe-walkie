# Revue du nom public

Statut au 29 août 2026 : **NOM SÉLECTIONNÉ ET RÉSERVÉ — « Vibe Walkie » est enregistré dans App Store Connect ; la validation juridique reste à terminer avant la publication commerciale**.

Ce document est un dossier de décision produit, pas un avis juridique. Une fiche App Store peut être créée pour tester et réserver le nom, mais sa disponibilité chez Apple ne vaut ni disponibilité juridique ni validation de marque.

## Conflits trouvés

- L’application `id6759615708` a utilisé « Vibe Remote – AI Dev » avant d’être renommée « Btelo Coding – AI Vibe Remote » : <https://apps.apple.com/fr/app/btelo-coding-ai-vibe-remote/id6759615708>.
- Le site <https://vibe-remote.net/> présente un produit nommé exactement « Vibe Remote », lui aussi destiné à piloter un Mac depuis un téléphone.
- Le nom `vibe-remote` est également utilisé dans l’écosystème logiciel, notamment sur PyPI.

Le 29 août 2026, la recherche publique de l’App Store français ne montrait aucune app portant exactement le titre « Vibe Remote ». La vérification décisive a néanmoins échoué après l’enregistrement du Bundle ID et la tentative de création de la fiche dans App Store Connect, avec le message : « Le nom de l’app saisi est déjà utilisé. » Le titre exact ne peut donc pas être réservé sur ce compte sans réclamation fondée sur des droits de propriété industrielle et commerciale.

Le second point suffit à créer un risque important de confusion commerciale pour un produit voisin. La porte « revue de marque favorable » n’est donc pas franchie, indépendamment de l’existence ou non d’une marque enregistrée exacte.

## Vérifications encore requises pour Vibe Walkie

1. Recherche à l’identique et par similarité dans Data INPI : <https://data.inpi.fr/>.
2. Recherche France et Union européenne dans TMview, recommandé par l’EUIPO : <https://www.tmdn.org/tmview/>.
3. Recherche App Store, moteurs web, GitHub, noms de domaine et principaux registres de paquets.
4. Vérification des classes pertinentes avec un conseil en propriété industrielle avant le dépôt si la marque doit être protégée.

## Critères d’acceptation définitive

- distinctif en français et prononçable ;
- aucun produit logiciel proche portant un nom identique ou fortement similaire ;
- nom App Store, organisation/dépôt GitHub et domaine exploitables ;
- recherche INPI/TMview sans risque significatif identifié ;
- validation écrite de la décision avant de remplacer les noms, identifiants et URLs de travail.

## Décisions techniques de renommage

- le nom produit, les textes iOS/macOS, les métadonnées Store et les artefacts deviennent `Vibe Walkie` ;
- le service Bonjour historique `_viberemote._tcp` reste stable afin qu’une mise à jour partielle ne casse ni la découverte ni les appairages ;
- les Bundle IDs `com.nicolascleton.viberemote*` restent stables, car la fiche App Store et les autorisations système y sont déjà liées ;
- les clés de trousseau et chemins de données historiques restent stables pour ne pas supprimer l’identité TLS ni les appairages lors d’une simple mise à jour ;
- le dépôt, le feed Sparkle et le domaine historiques seront migrés séparément pour conserver des redirections fonctionnelles.

Le protocole V2 et les données locales conservent leurs identifiants techniques historiques. Le changement de marque ne doit exiger ni réinstallation simultanée ni nouvel appairage.

## Vérification des candidats du 29 août 2026

### Nom sélectionné

**Vibe Walkie** a été accepté et réservé par l’enregistrement effectif de la fiche App Store Connect :

- Apple ID : `6806599345` ;
- Bundle ID : `com.nicolascleton.viberemote` ;
- SKU : `VIBENOMADE-IOS-001` ;
- langue principale : français.

Les recherches publiques effectuées à l’identique dans les App Stores français, américain et britannique, sur le Web et dans les résultats de marques indexés n’ont révélé aucun logiciel portant exactement ce nom. App Store Connect a également accepté le titre. Cela ne constitue pas une validation juridique : la recherche par similarité dans Data INPI et TMview, puis l’appréciation du risque dans les classes pertinentes, restent obligatoires avant la publication commerciale.

### Candidats écartés

- **Vibe Deck** : produit logiciel homonyme permettant déjà de piloter des terminaux par la voix et à distance.
- **Vibe Walk** : produit homonyme de contrôle à distance d'un environnement de développement depuis un téléphone, avec une promesse centrée sur le travail en marchant.
- **VibeWork** : application iPhone et services logiciels déjà exploités sous ce nom.
- **Vibe Flow / Vibeflow** : plusieurs produits logiciels homonymes, dont une application macOS de dictée vocale et une société soutenue par Y Combinator.
- **Vibe Control** : extension logicielle homonyme et forte collision sémantique avec des produits de contrôle à distance pour adultes.
- **Vibe Active** : marque et service logiciel de télécommunications déjà exploités.
- **Vibe Touch** : forte collision commerciale avec la gamme We-Vibe Touch et ses fonctions de contrôle à distance.
- **Vibe Nomad** : disponible et accepté par Apple, mais moins directement lié au geste de parler et de piloter le Mac en marchant.

### Solution de repli

**VibeDeskless** ne présentait pas de conflit public exact dans les recherches effectuées. Le nom n'a pas été réservé dans App Store Connect et reste donc un candidat de repli non vérifié par Apple.
