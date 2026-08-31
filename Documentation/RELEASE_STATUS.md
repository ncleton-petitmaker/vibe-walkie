# État des portes de sortie V1

Mis à jour le 29 août 2026. `PRÊT` signifie qu’une preuve locale reproductible existe ; `EXTERNE` exige un compte, un certificat, du matériel ou une validation tierce ; `BLOQUÉ` empêche explicitement la publication.

| Porte | Statut | Preuve / action suivante |
|---|---|---|
| Protocole V3, appairage, dictée transactionnelle et bloc configurable | PRÊT | 59 tests `RemoteCore`, 18 tests iOS et 39 tests macOS verts |
| Mode Nomade Tailscale — code et tests unitaires | PRÊT | Détection réelle `Running`, MagicDNS/IP, listener signé et port 54389 joignable sur l’adresse Tailscale du Mac de validation ; builds iOS/macOS et suites automatiques verts |
| Mode Nomade Tailscale — matrice physique | EXTERNE | Direct, DERP, 5G, veille et 50 séquences à documenter dans [QA_MATRIX.md](QA_MATRIX.md) avant annonce publique. L’installation iPhone de développement attend un nouveau profil Nicolas : la session du compte Xcode est actuellement rejetée. |
| Identité TLS Swift autonome et stable | PRÊT | Tests création, corruption, stabilité, régénération |
| Builds iOS Simulator et macOS arm64 | PRÊT | `scripts/ci-local.sh`, builds Release non signés iOS/macOS et DMG arm64 contrôlé |
| Lint Swift et scripts | PRÊT | SwiftLint strict et ShellCheck |
| Scan des secrets et fichiers interdits | PRÊT | Gitleaks sans fuite sur tout l’historique actuel + garde CI ; à répéter sur l’historique final |
| Dépôt open source documenté | PRÊT en local | Publication volontairement gelée jusqu’au nouveau nom |
| Nom public disponible | **BLOQUÉ** | Titre exact absent de la recherche publique et formulaire Apple préparé, mais produit concurrent homonyme actif ; voir [BRAND_REVIEW.md](BRAND_REVIEW.md) |
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
