# Pause conseillers — GitHub Pages + Supabase

Cette version remplace Power Automate par Supabase.

## Fonctionnement

- GitHub Pages héberge `index.html`.
- Supabase stocke les pauses et la file d'attente.
- 7 conseillers maximum en pause.
- Une pause dure 15 minutes.
- La file est FIFO.
- Une pause terminée libère automatiquement une place.
- Les postes interrogent Supabase toutes les 10 secondes.
- Le prénom est conservé uniquement dans le navigateur du conseiller.
- Le bouton de réinitialisation globale a volontairement été retiré de la page conseiller.

## 1. Créer le projet Supabase

1. Créez un projet sur https://supabase.com/
2. Ouvrez **SQL Editor**.
3. Copiez tout le contenu de `supabase.sql`.
4. Exécutez le script.

## 2. Récupérer les informations API

Dans Supabase, ouvrez les paramètres API du projet et récupérez :

- l'URL du projet ;
- la clé **publishable** (sur les anciens projets elle peut être appelée `anon`).

Ne mettez JAMAIS la clé `service_role` ou une clé `secret` dans le HTML.

## 3. Configurer index.html

Dans `index.html`, trouvez :

const SUPABASE_URL = 'COLLEZ_ICI_URL_SUPABASE';
const SUPABASE_KEY = 'COLLEZ_ICI_CLE_PUBLISHABLE_SUPABASE';

Remplacez les deux valeurs par celles de votre projet.

## 4. Publier sur GitHub Pages

Créez ou utilisez un dépôt GitHub.

Placez `index.html` à la racine du dépôt.

Dans GitHub :

Settings → Pages → Deploy from a branch → choisissez la branche contenant `index.html` et le dossier `/ (root)`.

GitHub Pages publie les fichiers statiques du dépôt.

## 5. Tester

Ouvrez la page depuis son URL GitHub Pages.

Testez avec deux navigateurs ou deux fenêtres :

1. PC 1 : saisissez Alexis → Demander une pause.
2. PC 2 : vous devez voir Alexis apparaître.
3. Ajoutez 6 autres personnes.
4. Une 8e personne doit aller dans la file.
5. Au bout de 15 minutes, la première pause est supprimée et la première personne en attente passe automatiquement.

## Administration

Pour réinitialiser manuellement :

Supabase → SQL Editor

delete from public.pause_breaks;
delete from public.pause_queue;

Puis rechargez la page.

## Sécurité

La clé publishable/anon peut être utilisée dans un front-end lorsque les permissions sont correctement protégées par RLS.

Le script retire les permissions directes sur les tables et expose uniquement les fonctions nécessaires.

La clé `service_role`/secret ne doit jamais être mise dans `index.html`.
