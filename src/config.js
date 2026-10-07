export const config = Object.freeze({
  environment: 'preproduction',
  projectRef: 'xxktlqrmlojetbfuiidz',
  url: 'https://xxktlqrmlojetbfuiidz.supabase.co',
  publishableKey: 'sb_publishable_CAQDiuZAtt79A699y_unGg_IEzIL9GM',
});
export function validateConfig(value = config) {
  const host = new URL(value.url).hostname;
  if (value.environment !== 'preproduction' || value.projectRef !== 'xxktlqrmlojetbfuiidz' || host !== `${value.projectRef}.supabase.co`) {
    throw new Error('Connexion bloquée : cette version utilise uniquement la base de préproduction.');
  }
  if (!value.publishableKey.startsWith('sb_publishable_')) throw new Error('Clé publique de préproduction invalide.');
}
