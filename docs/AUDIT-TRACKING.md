# Traitement de l'audit dans la préproduction

| Sujet | Traitement V2 |
|---|---|
| Tables publiques non protégées | Base neuve : seules les tables privées V2 sont installées. Anciennes tables de production inchangées. |
| SQL obsolète | Migrations versionnées et refus sur base V1 ; ancien installateur neutralisé. |
| Identité libre et jeton navigateur | Compte Supabase Auth, liste de membres autorisés et rôle serveur. |
| Consultation publique des pauses | RPC refusées à anon ; membres désactivés et comptes non autorisés refusés. |
| RPC administrateur exposées | Wrappers invoker, privilèges limités, vérification serveur à chaque action. |
| Fin automatique des pauses | Retour explicite ; dépassement visible sans libération de place. |
| Dépendance aux navigateurs | Reconciliation par pg_cron toutes les 15 secondes, purge quotidienne. |
| Changement de durée | Heure de fin prévue fixée au départ. |
| Réduction de capacité | Retrait des propositions excédentaires ; capacité revérifiée au départ. |
| Concurrence des actions | Verrou transactionnel commun avant toutes les mutations, index unique de demande ouverte, révision des paramètres. |
| Doubles clics et réponses inversées | Boutons verrouillés et file séquentielle de RPC ; invalidation au changement de session. |
| Appartenance d'une pause | Identifiant auth.uid(), propriété vérifiée côté serveur, indicateur personnel calculé serveur. |
| Expiration et refus | Statut terminal et messages explicites ; historique conservé. |
| Homonymes et changement de prénom | Identités UUID et nom administré ; homonymes autorisés. |
| FIFO ambigu | Tri par requested_at puis id. |
| Lisibilité et compteur | État personnel, durée, dépassement, compteurs libres/actives/proposées/attente. |
| Notifications | Activation et test explicites, son réglable, alertes visuelles ; pas de push navigateur fermé. |
| Délai de proposition | Paramètre offer_seconds éditable avec bornes serveur. |
| Saisies perdues | Formulaire dirty préservé, rechargement explicite et protection contre une mise à jour concurrente. |
| Retours d'actions | Messages de succès, erreurs et nombre de lignes mises à jour. |
| Auth et session | Écoute des changements de session, mot de passe effacé après tentative, contrôles membres à chaque RPC. |
| Accessibilité | Champs étiquetés, boutons natifs, focus visible, annonces de statut/erreurs, responsive. |
| Polling | 15 s si demande active, 30 s au repos, 60 s en arrière-plan ; recul exponentiel jusqu'à 120 s après échec. |
| Reconstruction DOM | Listes reconstruites seulement si leur contenu change ; compteurs actualisés seuls chaque seconde. |
| Index doublons | Nouveau schéma sans doublons ; index des FK et de file/historique. |
| search_path et normalisation | Chemin vide sur toutes les fonctions et espaces normalisés dans les noms administrés. |
| Deux tables d'administrateurs | Une seule table members avec rôle serveur. |
| Code monolithique/CDN | Modules séparés et dépendances intégrées au build, versions verrouillées. |
| Documentation | README et procédure préproduction réécrits. |
| Tests | PostgreSQL PGlite, DOM, export, isolation et recette Auth/RPC réelle sur la nouvelle base. |
| Historique et indicateurs | Durées, attente moyenne, dépassements, journal des actions, export CSV Excel. |
| Équipes et horaires | Paramètres par équipe, jours, horaires Paris, suspension. |
| Conservation | Historique métier 90 jours ; journaux cron 7 jours. |

## Vérifications et limites

Les tests DOM n'évaluent pas le rendu dans un navigateur réel. Le contrôle navigateur n'était pas disponible dans l'environnement de travail ; la recette visuelle et les autorisations de notifications restent à vérifier sur les postes cibles.

Le contrôle Supabase ne signale pas d'erreur de sécurité sur la base neuve. Les notices RLS sans politique sont intentionnelles : schéma non exposé et aucun droit direct ; seules les fonctions autorisées accèdent aux tables. Les index encore inutilisés sont normaux pour une base de test vide.

Aucun ajustement de la production, aucune fusion dans main, aucun changement de la publication GitHub Pages. Les vulnérabilités de l'ancien projet restent à traiter lors d'une opération distincte autorisée.
