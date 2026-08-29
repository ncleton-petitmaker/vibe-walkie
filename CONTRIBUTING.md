# Contribuer à Vibe Walkie

Merci de proposer des changements petits, testés et faciles à relire.

1. Ouvrez une issue pour les changements de protocole, de sécurité ou d’expérience utilisateur importants.
2. Créez une branche depuis `main`.
3. Ajoutez ou adaptez les tests avant la pull request.
4. Exécutez `Scripts/ci-local.sh`.
5. Décrivez le risque, la validation et les éventuelles migrations dans la pull request.

Toute contribution est fournie sous MPL-2.0. Vous certifiez être autorisé à la soumettre. Aucun visuel, police, capture, secret, UDID, adresse IP ou certificat tiers ne doit entrer dans le dépôt.

Les interfaces du protocole V2 sont publiques et doivent rester compatibles dans une même version majeure. Tout changement de format nécessite une documentation dans `Documentation/PROTOCOL.md`, un test d’aller-retour et une stratégie d’incompatibilité explicite.

Le formatage suit SwiftFormat fourni par Xcode ; SwiftLint bloque les erreurs simples. Les warnings Xcode doivent être traités, pas masqués.
