# Réponses App Privacy

Réponse prévue dans App Store Connect : **Non, nous ne collectons pas de données depuis cette app**.

- Aucun identifiant de compte : il n’existe pas de compte.
- Aucun suivi publicitaire ou inter-apps.
- Aucun SDK de télémétrie, publicité ou crash reporting tiers.
- L’audio reste sur l’iPhone et n’est pas transmis au développeur ni au Mac.
- Le texte et les commandes vont uniquement au Mac approuvé, directement sur le réseau local ou via le réseau Tailscale facultatif de l’utilisateur. Ils ne sont pas reçus par le développeur.
- Aucune transcription n’est conservée dans un historique.
- Le mode Nomade ne lit ni compte, ni jeton OAuth, ni ACL Tailscale. Il mémorise localement le nom MagicDNS du Mac et son adresse Tailscale facultative.
- Sparkle appartient uniquement au compagnon Mac et son profilage système est désactivé.

Avant soumission, comparer cette déclaration au comportement du binaire final et de toutes ses dépendances. Tout ajout futur de diagnostic distant impose une nouvelle analyse et une mise à jour des réponses.

URL publique : `https://vibewalkie.app/privacy`.
