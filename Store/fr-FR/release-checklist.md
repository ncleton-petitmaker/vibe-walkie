# Checklist App Store Connect

## Contrats et identité

- [ ] Nouveau nom validé et réservé.
- [ ] Enregistrement de l’app créé sous le compte individuel de Nicolas.
- [ ] Contrat Paid Apps accepté, coordonnées bancaires et fiscales valides.
- [ ] Statut DSA déclaré honnêtement. Pour une activité commerciale, le statut attendu est celui d’un **trader individuel**, avec adresse, téléphone et e-mail vérifiés avant publication dans l’UE.
- [ ] France activée et prix 14,99 € sélectionné dans les paliers alors disponibles.

## Conformité

- [ ] Politique de confidentialité et assistance accessibles publiquement.
- [ ] Réponses App Privacy confrontées au binaire final.
- [ ] `PrivacyInfo.xcprivacy` validé sans avertissement.
- [ ] Questionnaire export compliance complété. Le plist déclare actuellement `ITSAppUsesNonExemptEncryption=false`, mais cette qualification doit être confirmée pour l’usage de TLS et de cryptographie applicative ainsi que pour les obligations françaises avant soumission.
- [ ] Certificat Apple Distribution, profils et clé API App Store Connect actifs.

## Binaire et revue

- [ ] Archive Release construite par la CI depuis un tag signé.
- [ ] Validation App Store sans erreur ni avertissement de confidentialité/conformité.
- [ ] Upload TestFlight terminé et build traité par Apple.
- [ ] Bêta publique approuvée, formulaire analysé et blocages corrigés.
- [ ] DMG de revue signé/notarisé accessible sans authentification.
- [ ] Mode **Découvrir sans Mac** vérifié sur le build soumis.
- [ ] Notes de revue, contact et instructions d’appairage renseignés.
- [ ] Promotion finale effectuée manuellement après franchissement de toutes les portes.

Références : [prix](https://developer.apple.com/help/app-store-connect/manage-app-pricing/set-a-price/), [App Privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/), [DSA](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/) et [export compliance](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/).
