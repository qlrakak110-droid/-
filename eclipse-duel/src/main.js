// ECLIPSE DUEL — game entry.
// Boot: stored quality -> createApp -> environment -> VFX -> camera -> audio -> input -> UI -> game (roster, presets,
// compile) behind a loading veil; then the title (or #demo / #fight / #training straight into a match) and ctx.ready().
// The action-RPG mode (src/rpg) is created next to the game and shares its roster and VFX access; #rpg=<hero> boots it.

import { createApp } from './core/app.js';
import { createEnvironment } from './env/index.js';
import { createVfx } from './vfx/index.js';
import { createCameraDirector } from './cam/index.js';
import { createAudio } from './audio/index.js';
import { createInput } from './input/index.js';
import { createUI } from './ui/index.js';
import { createGame } from './game/index.js';
import { createRpg } from './rpg/index.js';
import { installProfiler } from './game/prof.js';

/** The quality chosen in a menu is stored in localStorage; apply it as the `q` flag before the app reads its flags. */
function applyStoredQuality() {
  try {
    const h = String(location.hash || '');
    if (/(^|[#&])(test|q=)/.test(h)) return;
    const q = localStorage.getItem('ed.quality');
    if (q !== 'low' && q !== 'mid' && q !== 'high') return;
    const rest = h.replace(/^#/, '');
    history.replaceState(null, '', location.pathname + location.search + '#' + (rest ? rest + '&' : '') + 'q=' + q);
  } catch (e) { /* storage or history unavailable: default tier */ }
}

/** Loading veil: black screen with the eclipse mark, removed once the first screen is up. */
function showVeil() {
  const el = document.createElement('div');
  el.id = 'ed-veil';
  el.style.cssText = 'position:absolute;inset:0;z-index:90;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:18px;' +
    'background:#040508;color:#d8b46a;font:600 13px/1.4 "Cinzel","Noto Serif KR",serif;letter-spacing:.32em;transition:opacity .6s ease;pointer-events:auto';
  el.innerHTML = '<svg width="92" height="92" viewBox="0 0 100 100" aria-hidden="true"><defs><radialGradient id="edv" r="50%"><stop offset="62%" stop-color="#d8b46a" stop-opacity="0"/>' +
    '<stop offset="70%" stop-color="#f4dca0" stop-opacity=".9"/><stop offset="100%" stop-color="#d8b46a" stop-opacity="0"/></radialGradient></defs>' +
    '<circle cx="50" cy="50" r="48" fill="url(#edv)"><animate attributeName="r" values="44;48;44" dur="2.4s" repeatCount="indefinite"/></circle><circle cx="50" cy="50" r="30" fill="#040508"/></svg>' +
    '<div>일식결투 · ECLIPSE DUEL</div><div style="font:500 11px/1 system-ui;letter-spacing:.2em;color:#8d887e">불러오는 중 · LOADING</div>';
  (document.getElementById('app') || document.body).appendChild(el);
  return el;
}

const nextFrame = () => new Promise((r) => requestAnimationFrame(() => r()));

async function boot() {
  applyStoredQuality();
  const veil = showVeil();
  await nextFrame();
  const ctx = createApp();
  const profiler = ctx.flags.prof ? installProfiler(ctx) : null;
  createEnvironment(ctx);
  createVfx(ctx);
  createCameraDirector(ctx);
  createAudio(ctx);
  createInput(ctx);
  createUI(ctx);
  const unlock = () => { if (ctx.audio) ctx.audio.unlock(); };
  window.addEventListener('pointerdown', unlock, { once: true, capture: true });
  window.addEventListener('keydown', unlock, { once: true, capture: true });

  const game = await createGame(ctx, { profiler });
  // the action-RPG mode: takes the stage from the duel (game.leaveForRpg) and gives it back at the title
  const rpg = await createRpg(ctx, { fighters: game.fighters, fx: game.fx, profiler, enter: () => game.leaveForRpg(), exit: () => game.title() });
  const f = ctx.flags;
  if (f.rpg !== undefined) {
    rpg.start(f.rpg === true ? 'kael' : String(f.rpg), { bot: f.rpgbot !== undefined, sandbox: f.rpgsandbox !== undefined, encounter: typeof f.rpgenc === 'string' ? f.rpgenc : undefined });
  }
  // warm everything once: programs (scene, shadows, distortion), textures, light set
  if (ctx.env && ctx.env.prewarm) ctx.env.prewarm();
  ctx.frame(1 / 60, true);

  if (ctx.test) veil.remove();
  else { veil.style.opacity = '0'; veil.style.pointerEvents = 'none'; setTimeout(() => veil.remove(), 700); }
  ctx.start();
  ctx.ready();
  return game;
}

boot().catch((e) => {
  console.error('[ed] boot failed', e);
  const el = document.getElementById('ed-veil');
  if (el) el.lastChild.textContent = '오류 · ERROR: ' + (e && e.message);
});
