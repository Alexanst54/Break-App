# Optimisation de préproduction — 7 octobre 2026

La RPC authentifiée ba_poll renvoie l'état complet au premier chargement ou après un changement, et seulement l'heure serveur, une empreinte et unchanged sinon. L'empreinte couvre tout l'état observable sauf l'heure : identité, équipe, règles, horaires ouverts, file et dernière demande. Les droits sont revérifiés à chaque appel. Aucun cache partagé entre utilisateurs.

Le conseiller sans demande interroge toutes les 60 secondes au lieu de 30. Une demande en cours ou le pilotage conserve 15 secondes au premier plan ; un onglet masqué conserve 60 secondes. Le retour au premier plan actualise immédiatement. Les restrictions de temporisation du navigateur restent applicables.

Le changement de vue force un état complet. Les saisies non enregistrées restent préservées. Le repli vers ba_state est réservé au code PGRST202 (RPC absente), jamais aux refus d'autorisation.

## Mesure et limites

Mesure distante du 7 octobre : 80 lectures réussies, par groupes de 10, avec un seul compte. État initial 1 214 octets ; réponse inchangée moyenne 109,925 octets (91 % de réduction). Latence p95 10 795 ms, maximum 10 868 ms depuis l'environnement de contrôle. Cette latence inclut le réseau de cet environnement et n'isole pas le temps SQL. Elle ne valide pas une utilisation fluide à 80 connexions simultanées.

Test local reproductible : 711 octets pour un état sans demande contre 107 pour une réponse inchangée, soit 85 % de JSON en moins. Pour 80 personnes, 8 heures par jour, 22 jours, entièrement inactives : 844 800 appels par mois au lieu de 1 689 600, soit environ 90 Mo de réponses JSON inchangées. Ce scénario exclut les changements d'état, les en-têtes HTTP, Auth, les chargements de l'application et les autres usages.

La fonction conserve le calcul de l'état et la réconciliation existants : elle réduit le transfert réseau, pas le coût de calcul de chaque appel. La baisse de fréquence réduit aussi le nombre d'appels des conseillers inactifs. Ce n'est ni un test de 80 utilisateurs simultanés ni une garantie de gratuité.

Validation : 11 tests automatiques, aucun ignoré, compilation Vite et contrôle d'isolation. La vérification visuelle dans un navigateur n'était pas disponible. scripts/measure-poll.mjs permet une mesure distante de 80 lectures, 10 simultanées, avec un seul compte de test, sans stocker son mot de passe.

Le site reste privé. La production et la branche main ne sont pas modifiées. Les améliorations Realtime, partage entre onglets et réduction des champs spécifiques au conseiller restent hors de cette première passe.
