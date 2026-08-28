# Compilation reproductible

## Prérequis

- macOS avec Xcode 26 ou supérieur ;
- Swift 6 ;
- XcodeGen uniquement si `project.yml` est modifié ;
- aucun Homebrew, OpenSSL, serveur ou shell requis par l’utilisateur final.

## Tests et builds non signés

Exécutez `Scripts/ci-local.sh`. Le script lance RemoteCore, régénère les projets lorsque XcodeGen est présent, puis compile iOS Simulator et macOS arm64 sans signature.

## Signature d’un fork

Ne modifiez pas les identifiants de travail directement. Copiez `Config/Developer.example.xcconfig` vers `Config/Developer.xcconfig`, renseignez les cinq identifiants et votre Team ID, puis ajoutez `-xcconfig Config/Developer.xcconfig` à votre commande `xcodebuild`. Ce fichier est ignoré par Git.

L’installation personnelle iOS nécessite un compte Apple Developer et les limites habituelles du provisioning Apple. Le compagnon Mac peut être lancé depuis Xcode pour le développement ; une distribution à d’autres utilisateurs exige Developer ID et notarisation.

## Dépendances

Les versions exactes sont décrites dans `macOS/project.yml` et figées dans `Package.resolved`. Vérifiez toute mise à jour de dépendance, sa licence et son impact sur le manifeste de confidentialité.
