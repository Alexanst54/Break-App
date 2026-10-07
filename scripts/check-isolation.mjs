import { readFile, readdir } from 'node:fs/promises';
import { validateConfig } from '../src/config.js';
validateConfig();
async function walk(dir) {
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const file = `${dir}/${entry.name}`;
    if (entry.isDirectory()) await walk(file);
    else if (/\.(js|html|css|json)$/.test(file)) {
      const text = await readFile(file, 'utf8');
      if (text.includes('ferxlbwivyyfhnwgmcja') || /sb_secret_[A-Za-z0-9_-]{20,}/.test(text)) throw new Error(`Cible ou clé interdite : ${file}`);
    }
  }
}
await walk('src');
try { await walk('dist'); } catch (e) { if (e.code !== 'ENOENT') throw e; }
console.log('Isolation vérifiée : seul le projet de préproduction est référencé.');
