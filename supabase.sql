-- Fichier historique remplacé par les migrations de préproduction.
-- Voir docs/PREPRODUCTION.md. Ne pas exécuter sur la production.
do $$ begin raise exception 'Utiliser supabase/migrations sur la préproduction uniquement'; end $$;
