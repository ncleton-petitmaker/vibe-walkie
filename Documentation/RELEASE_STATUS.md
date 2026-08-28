# État des portes de sortie V1

Mis à jour le 28 août 2026. `PRÊT` signifie qu’une preuve locale reproductible existe ; `EXTERNE` exige un compte, un certificat, du matériel ou une validation tierce ; `BLOQUÉ` empêche explicitement la publication.

| Porte | Statut | Preuve / action suivante |
|---|---|---|
| Protocole V2, appairage, dictée transactionnelle | PRÊT | Tests `RemoteCore`, iOS et macOS |
| Identité TLS Swift autonome et stable | PRÊT | Tests création, corruption, stabilité, régénération |
| Builds iOS Simulator et macOS arm64 | PRÊT | `Scripts/ci-local.sh` |
| Lint Swift et scripts | PRÊT | SwiftLint strict et ShellCheck |
| Scan des secrets et fichiers interdits | PRÊT | Gitleaks + garde CI ; à répéter sur l’historique final |
| Dépôt open source documenté | PRÊT en local | Publication volontairement gelée jusqu’au nouveau nom |
| Nom public disponible | **BLOQUÉ** | Voir [BRAND_REVIEW.md](BRAND_REVIEW.md) ; choisir et valider un nouveau nom |
| Certificat Developer ID Application | EXTERNE | Créer/télécharger depuis le compte Apple Developer |
| Signature, notarisation, stapling, Gatekeeper | EXTERNE | Exécuter le workflow Mac avec le certificat et les identifiants de notarisation |
| Mise à jour Sparkle entre deux versions signées | EXTERNE | Publier deux bêtas après gel du nom et du feed |
| Certificat Apple Distribution / App Store Connect | EXTERNE | Configurer le compte individuel, contrats et clé API |
| DSA, confidentialité et export compliance | EXTERNE | Publier les URLs, vérifier trader individuel et qualification chiffrement |
| Dix installations propres en moins de trois minutes | EXTERNE | Exécuter et documenter [QA_MATRIX.md](QA_MATRIX.md) |
| Bêta TestFlight publique | EXTERNE | Nécessite nom, enregistrement App Store et archive signée |
| Approbation App Store | EXTERNE | Soumission manuelle après toutes les portes précédentes |
| Tag `1.0.0` signé et DMG final | EXTERNE | Seulement après approbation et tests réels |

La version `1.0.0` ne doit pas être taguée tant qu’une ligne est `BLOQUÉE` ou `EXTERNE` sans preuve attachée.
