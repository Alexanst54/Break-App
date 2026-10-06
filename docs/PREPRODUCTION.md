# Exploiter la préproduction

## Isolation

| Élément | Préproduction |
|---|---|
| Branche GitHub | `preprod/break-app-v2` |
| Projet Supabase | `Break-App-Preprod` |
| Référence autorisée | `xxktlqrmlojetbfuiidz` |
| Site privé | `https://break-app-preprod-alex.alexanst53.chatgpt.site` |
| Données | Fictives, aucune copie de production |

Le Site est accessible à son propriétaire. Son ouverture à des collègues nécessite une décision de partage séparée. Les publications de ce Site ne modifient pas GitHub Pages. Le workflow de la branche ne possède aucun droit de déploiement.

## Comptes de recette

- `pilotage@break-app.test` : administrateur de test.
- `conseiller1@break-app.test` : Camille test.
- `conseiller2@break-app.test` : Sam test.

Le mot de passe est fourni au propriétaire dans la conversation, jamais dans les sources. Les comptes ont été initialisés comme fixtures dans cette base neuve. Aucun e-mail n'a été envoyé et aucun compte réel n'a été importé.

Pour de nouveaux utilisateurs, créer leur compte dans Supabase Authentication puis l'autoriser dans l'onglet Pilotage. Le premier administrateur doit être ajouté par l'opérateur dans `break_app.members`. Les inscriptions libres ne donnent aucun accès aux pauses.

## Migrations

Les migrations de cette branche créent le schéma V2 et les tâches serveur. Elles refusent une base contenant les tables V1. Elles ne constituent pas un script de migration de la production. Le fichier historique `supabase.sql` a été neutralisé pour éviter de réinstaller les anciennes fonctions.

Une base de préproduction neuve peut recevoir les migrations dans leur ordre chronologique. Utiliser les outils Supabase avec la référence de test vérifiée. Ne jamais lier le CLI au projet de production pour cette branche.

## Recette rapide

1. Ouvrir le Site privé, se connecter avec le compte pilotage.
2. Définir une place dans l'équipe de test.
3. Dans deux profils de navigateur distincts, ouvrir les comptes conseiller (le Site privé demande aussi l'accès propriétaire).
4. Demander une pause : une proposition est réservée, l'autre conseiller attend.
5. Confirmer le premier départ, puis son retour : une place est proposée au suivant.
6. Laisser une proposition expirer : la demande est historisée, aucune pause n'est démarrée.
7. Régler une durée d'une minute avant un départ : après la minute, la pause apparaît en dépassement mais reste occupée.
8. Vérifier suspension, réduction de capacité, export CSV et perte de connexion.
9. Restaurer les paramètres souhaités et clôturer les demandes de test.

## Limites et décisions avant production

- La confirmation de retour est une règle métier nouvelle, à valider avec le pilotage.
- Les notifications navigateur nécessitent une autorisation et ne sont pas garanties si le navigateur est fermé ou suspendu. Les tâches serveur continuent, mais aucune notification push hors navigateur n'est implémentée.
- Les plages horaires ne traversent pas minuit ; les pauses actives restent visibles en dehors des horaires.
- Historique limité à 90 jours et 5 000 lignes par export ; pour un volume supérieur, ajouter la pagination d'export.
- Le second projet utilise le forfait gratuit indiqué à la création ; ses quotas et une éventuelle mise en pause pour inactivité restent applicables.
- La protection Auth contre les mots de passe compromis doit être activée lorsqu'elle est disponible sur le forfait. Elle n'est pas remplacée par un contrôle côté navigateur.
- Une future mise en production exige un plan de migration V1→V2, attribution des comptes réels, sauvegarde et retour arrière. Une fusion directe de cette branche ne suffit pas.
- Les tables publiques `users`, `posts`, `comments` signalées sur l'ancien projet n'existent pas dans la base neuve. Elles restent inchangées en production conformément à la consigne.
