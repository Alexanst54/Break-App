# Break App V2 — préproduction

Gestion des pauses avec comptes individuels, propositions FIFO, confirmation de retour, pilotage par équipe et historique exportable.

**Cette branche est une préproduction indépendante. Ne pas fusionner dans `main` sans une migration de production dédiée et une validation métier.**

- Production existante : GitHub Pages, branche `main`. Aucune modification effectuée.
- Branche de travail : `preprod/break-app-v2`.
- Base de test : `Break-App-Preprod` (`xxktlqrmlojetbfuiidz`), séparée de la production.
- Aperçu privé : https://break-app-preprod-alex.alexanst53.chatgpt.site
- Les comptes, pauses et journaux de production ne sont pas copiés.

## Développement

Node.js 24, npm. Les dépendances sont figées dans `package-lock.json`.

```sh
npm ci
npm test
npm run build
npm run check
npm run dev
```

`src/config.js` contient uniquement la clé publique et la référence de test. Un garde-fou bloque toute autre référence. La bibliothèque Supabase est intégrée au build ; aucun CDN ni police externe n'est nécessaire.

## Fonctionnement

1. Un compte Supabase Auth doit être autorisé dans `break_app.members`.
2. Une demande rejoint la file de son équipe. Une place disponible est réservée temporairement.
3. Le conseiller confirme son départ avant l'expiration de la proposition.
4. L'heure de fin prévue est fixée au départ. Un changement de paramètres ne modifie pas les pauses déjà commencées.
5. Au dépassement, la pause reste active jusqu'au retour confirmé par le conseiller ou le pilotage.
6. La file est ordonnée par heure de demande, puis identifiant. Une proposition expirée est historisée ; le conseiller peut refaire une demande.
7. Suspendre les départs ou réduire la capacité replace les propositions excédentaires dans la file. Une capacité inférieure aux pauses actives n'interrompt pas celles-ci.
8. Un traitement serveur toutes les 15 secondes gère les propositions même sans navigateur. Les horaires sont interprétés en Europe/Paris ; les plages traversant minuit ne sont pas prises en charge.
9. L'historique et le journal du pilotage sont conservés 90 jours, puis purgés quotidiennement. Les attentes de plus de 12 heures sont clôturées.

## Sécurité

Tables dans un schéma privé non exposé, RLS activée et droits directs retirés. Les RPC publiques sont `SECURITY INVOKER` et accessibles uniquement au rôle `authenticated`. Les fonctions privées autorisées vérifient le compte et le rôle à chaque appel. Les autres fonctions privées n'ont aucun droit d'exécution pour les clients.

Les rôles ne proviennent jamais de métadonnées modifiables par l'utilisateur. Un compte désactivé perd immédiatement l'accès aux RPC. Il n'y a plus de jeton d'identité basé sur le navigateur, ni de prénom modifiable permettant de créer plusieurs demandes. Limite : 10 demandes par heure et au moins 5 secondes entre deux demandes.

Les comptes de test sont fictifs. Leurs mots de passe sont transmis hors dépôt. Ne pas utiliser de données réelles dans cet environnement.

## Pilotage

Paramètres par équipe, suspension, horaires et jours, durée, délai d'acceptation, comptes autorisés, retours individuels, clôture collective, historique CSV (compatible Excel, formules neutralisées). Les paramètres sont protégés contre l'écrasement concurrent par numéro de révision. Les saisies non enregistrées sont préservées lors du rafraîchissement.

Les indicateurs sont calculés sur les lignes chargées : demandes, pauses terminées, attente moyenne avant départ, dépassements terminés. L'export est limité à 5 000 lignes ; une indication signale toute troncature.

## Tests et installation

Voir [préproduction](docs/PREPRODUCTION.md) et [bilan de l'audit](docs/AUDIT-TRACKING.md).

`npm test` exécute PostgreSQL via PGlite, les droits, scénarios métier, export et interface DOM. `scripts/smoke-preprod.mjs` teste Auth et RPC sur la seule base de préproduction ; le mot de passe de test est reçu via stdin et n'est jamais enregistré dans le dépôt.

Les workflows GitHub vérifient le code et produisent un artefact statique. Ils ne déploient ni Pages ni Supabase.
