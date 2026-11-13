// Bundles one entry into a single self-contained HTML file.
//   node tools/build.mjs game          -> dist/eclipse-duel.html (+ dist/eclipse-duel.artifact.html fragment)
//   node tools/build.mjs <lab>         -> build/<lab>.html   (entry: src/labs/<lab>.js)
//   flags: --dev (no minify, inline sourcemap)
//          --as <name>  game only: write build/<name>.html instead of dist/ (a private copy for one team's captures,
//                       so parallel teams never load a half-written dist file)
import { build } from 'esbuild';
import fs from 'node:fs';
import path from 'node:path';
import url from 'node:url';

const ROOT = path.resolve(path.dirname(url.fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const target = args[0] && !args[0].startsWith('--') ? args[0] : 'game';
const dev = args.includes('--dev');
const asIdx = args.indexOf('--as');
const asName = asIdx >= 0 ? args[asIdx + 1] : null;
const entry = target === 'game' ? 'src/main.js' : `src/labs/${target}.js`;
if (!fs.existsSync(path.join(ROOT, entry))) { console.error('no entry: ' + entry); process.exit(1); }

const result = await build({
  absWorkingDir: ROOT,
  entryPoints: [entry],
  bundle: true,
  format: 'iife',
  minify: !dev,
  sourcemap: dev ? 'inline' : false,
  write: false,
  target: ['es2020'],
  loader: { '.glsl': 'text', '.css': 'text', '.svg': 'text', '.txt': 'text', '.edb': 'binary' },
  define: { __DEV__: JSON.stringify(dev), __TARGET__: JSON.stringify(target) },
  legalComments: 'none',
  logLevel: 'warning',
});
const js = result.outputFiles[0].text.replace(/<\/script/gi, '<\\/script');
const frag = fs.readFileSync(path.join(ROOT, 'src/index.html'), 'utf8').replace('/*__JS__*/', () => js);
const full = '<!doctype html>\n<html lang="ko">\n<head>\n<meta charset="utf-8">\n' +
  '<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no,viewport-fit=cover">\n' +
  '</head>\n<body>\n' + frag + '\n</body>\n</html>\n';
const write = (rel, text) => {
  const p = path.join(ROOT, rel);
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, text);
  console.log(rel, (text.length / 1024).toFixed(0) + ' KB');
};
if (target === 'game' && asName) {
  write(`build/${asName}.html`, full);
} else if (target === 'game') {
  write('dist/eclipse-duel.html', full);
  write('dist/eclipse-duel.artifact.html', frag);
} else {
  write(`build/${target}.html`, full);
}
