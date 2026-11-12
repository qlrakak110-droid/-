// Audio lab: audition every procedural sound and music track, watch its waveform / spectrogram, and run the
// measurement report.
//   node tools/build.mjs audio                     -> build/audio.html (open it, click anything: audio unlocks)
//   node tools/shot.mjs audio --eval "__ED.lab.play('report')"      measured table of every sound + music
//   node tools/shot.mjs audio --eval "__ED.lab.play('selftest')"    API safety checks
//   node tools/shot.mjs audio --do "__ED.lab.play('sheet')" --size 1800x1300 --out shots/audio/sheet        every SFX
//   node tools/shot.mjs audio --do "__ED.lab.play('musicSheet')" --size 1800x1300 --out shots/audio/music  every track

import { createLab } from '../core/lab.js';
import { createAudio } from '../audio/index.js';
import { runReport, selfTest, spectrogram, measure } from '../audio/analyze.js';

const GROUPS = [['weapon', '무기 · Weapon'], ['combat', '타격 · Combat'], ['move', '움직임 · Movement'], ['fire', '불 · Fire'], ['ice', '얼음 · Ice'],
  ['volt', '번개 · Lightning'], ['magic', '마법 · Magic'], ['ult', '궁극기 · Ultimate'], ['time', '시간 · Time'], ['ui', 'UI'], ['announce', '알림 · Announcer']];
const TRACK_LABELS = { title: '타이틀 Title', battle: '전투 Battle', ultimate: '궁극기 Ultimate', victory: '승리 Victory' };

const CSS = `
.al{position:absolute;inset:0;z-index:6;pointer-events:auto;overflow:auto;background:radial-gradient(120% 90% at 50% 0%,#141019 0%,#07080c 60%);
  color:var(--ed-ink,#ece6da);font:13px/1.4 var(--ed-body,system-ui);padding:16px;box-sizing:border-box;-webkit-user-select:none;user-select:none}
.al *{box-sizing:border-box}
.al h1{margin:0;font:600 18px/1.2 var(--ed-display,serif);letter-spacing:.08em;color:var(--ed-gold,#d8b46a)}
.al h1 small{display:block;font:12px var(--ed-body,system-ui);letter-spacing:.02em;color:var(--ed-dim,#9a958c);margin-top:3px}
.al .top{display:flex;flex-wrap:wrap;gap:12px 20px;align-items:center;justify-content:space-between;margin-bottom:14px}
.al .chip{display:inline-flex;align-items:center;gap:6px;padding:4px 10px;border-radius:999px;border:1px solid #3a3440;font-size:12px;color:var(--ed-dim,#9a958c)}
.al .chip i{width:8px;height:8px;border-radius:50%;background:#7a3a3a;display:inline-block}
.al .chip.on i{background:#6fd38a;box-shadow:0 0 8px #6fd38a}
.al .vol{display:flex;gap:14px;flex-wrap:wrap}
.al label{display:flex;align-items:center;gap:6px;font-size:12px;color:var(--ed-dim,#9a958c)}
.al input[type=range]{width:96px;accent-color:var(--ed-gold,#d8b46a)}
.al .main{display:grid;grid-template-columns:minmax(0,1.35fr) minmax(0,1fr);gap:14px}
@media (max-width:860px){.al .main{grid-template-columns:1fr}}
.al .card{background:rgba(22,20,28,.82);border:1px solid #2a2530;border-radius:10px;padding:12px 12px 10px;margin-bottom:12px}
.al .card h2{margin:0 0 8px;font:600 11px/1 var(--ed-body,system-ui);letter-spacing:.14em;text-transform:uppercase;color:#b9ab93}
.al .btns{display:flex;flex-wrap:wrap;gap:6px}
.al button{font:12px/1 ui-monospace,Menlo,Consolas,monospace;padding:8px 10px;border-radius:7px;border:1px solid #3b3542;background:#1b1922;color:#e8e1d4;cursor:pointer;
  transition:background .12s,border-color .12s,transform .06s}
.al button:hover{border-color:var(--ed-gold,#d8b46a);background:#24202b}
.al button:active{transform:translateY(1px)}
.al button.loop::after{content:" ⟳";color:var(--ed-frost,#7fd4ff)}
.al button.live{background:#3a2412;border-color:var(--ed-ember,#ff6a2b);color:#ffd9bd}
.al button.track{font-family:var(--ed-body,system-ui);font-size:13px;padding:9px 12px}
.al .row{display:flex;flex-wrap:wrap;gap:10px 16px;align-items:center;margin-top:10px}
.al canvas.pv{width:100%;height:240px;display:block;border-radius:8px;background:#05050a}
.al .meta{margin-top:8px;font:12px/1.5 ui-monospace,Menlo,Consolas,monospace;color:#cfc6b6;white-space:pre-wrap;min-height:3em}
.al .desc{color:var(--ed-dim,#9a958c);font-size:12px;margin-top:4px;min-height:1.4em}
.al .grp-fire button:hover{border-color:var(--ed-ember,#ff6a2b)} .al .grp-ice button:hover{border-color:var(--ed-frost,#7fd4ff)} .al .grp-volt button:hover{border-color:var(--ed-volt,#b48cff)}
.al-sheet{position:absolute;inset:0;z-index:7;background:#06060a;pointer-events:auto}
`;

/** Magma-like palette for spectrograms, t in [0, 1]. */
function heat(t) {
  const S = [[0, 0, 0, 0], [0.25, 40, 12, 70], [0.5, 150, 30, 90], [0.72, 236, 92, 40], [0.88, 255, 196, 90], [1, 255, 250, 225]];
  let i = 1;
  while (i < S.length - 1 && S[i][0] < t) i++;
  const a = S[i - 1], b = S[i], u = Math.max(0, Math.min(1, (t - a[0]) / (b[0] - a[0])));
  return [a[1] + (b[1] - a[1]) * u, a[2] + (b[2] - a[2]) * u, a[3] + (b[3] - a[3]) * u];
}

/** Draw waveform (top 30 %) and spectrogram (rest) of a buffer into a canvas rectangle. */
function drawBuffer(g, buf, x, y, w, h) {
  const sp = spectrogram(buf, { cols: Math.max(32, Math.floor(w)), rows: Math.max(32, Math.floor(h * 0.68)) });
  let mx = -200;
  for (const v of sp.db) if (v > mx) mx = v;
  const img = g.createImageData(sp.cols, sp.rows);
  for (let i = 0; i < sp.db.length; i++) {
    const [r, gg, b] = heat(Math.max(0, Math.min(1, (sp.db[i] - mx + 80) / 80)));
    img.data[i * 4] = r; img.data[i * 4 + 1] = gg; img.data[i * 4 + 2] = b; img.data[i * 4 + 3] = 255;
  }
  const wh = Math.floor(h * 0.3);
  g.putImageData(img, Math.round(x), Math.round(y + wh + 2));
  g.fillStyle = '#0b0a10';
  g.fillRect(x, y, w, wh);
  const d0 = buf.getChannelData(0), d1 = buf.getChannelData(buf.numberOfChannels - 1), n = buf.length, mid = y + wh / 2;
  g.fillStyle = '#d8b46a';
  for (let c = 0; c < w; c++) {
    let lo = 0, hi = 0;
    for (let i = Math.floor((c / w) * n), e = Math.floor(((c + 1) / w) * n); i < e; i++) { const v = (d0[i] + d1[i]) / 2; if (v < lo) lo = v; if (v > hi) hi = v; }
    g.fillRect(x + c, mid - hi * wh * 0.48, 1, Math.max(1, (hi - lo) * wh * 0.48));
  }
}

function buildPanel(ctx, audio) {
  const style = document.createElement('style');
  style.textContent = CSS;
  document.head.appendChild(style);
  const root = document.createElement('div');
  root.className = 'al';
  root.innerHTML = `
    <div class="top">
      <h1>ECLIPSE DUEL · AUDIO LAB<small>일식결투 음향 실험실 — every sound is synthesised in code</small></h1>
      <span class="chip" data-state><i></i><b>locked</b></span>
      <div class="vol">
        <label>master <input type="range" min="0" max="1" step="0.01" value="1" data-vol="master"></label>
        <label>sfx <input type="range" min="0" max="1" step="0.01" value="1" data-vol="sfx"></label>
        <label>music <input type="range" min="0" max="1" step="0.01" value="0.8" data-vol="music"></label>
      </div>
    </div>
    <div class="main"><div data-left></div><div data-right></div></div>`;
  document.getElementById('ui').appendChild(root);
  const left = root.querySelector('[data-left]'), right = root.querySelector('[data-right]');
  const chip = root.querySelector('[data-state]');
  const card = (title, parent, cls = '') => { const c = document.createElement('div'); c.className = 'card ' + cls; c.innerHTML = `<h2>${title}</h2><div class="btns"></div>`; parent.appendChild(c); return c; };
  const button = (parent, label, fn, cls = '') => { const b = document.createElement('button'); b.textContent = label; b.className = cls; b.onclick = () => { audio.unlock(); fn(b); }; parent.appendChild(b); return b; };

  // music transport
  const mc = card('음악 · Music', left);
  const mbtns = mc.querySelector('.btns');
  const trackBtns = {};
  for (const t of audio.tracks()) trackBtns[t] = button(mbtns, TRACK_LABELS[t] || t, () => audio.music(t), 'track');
  button(mbtns, '■ stop', () => audio.music(null), 'track');
  const row = document.createElement('div');
  row.className = 'row';
  row.innerHTML = '<label>intensity <input type="range" min="0" max="1" step="0.01" value="0.5" data-int></label><span data-int-v>0.50</span>';
  mc.appendChild(row);
  row.querySelector('[data-int]').oninput = (e) => { audio.setIntensity(+e.target.value); row.querySelector('[data-int-v]').textContent = (+e.target.value).toFixed(2); };
  const tools = document.createElement('div');
  tools.className = 'btns row';
  mc.appendChild(tools);
  button(tools, 'duck 0.6 / 1.5 s', () => audio.duck(0.6, 1.5));
  button(tools, 'slow-mo 0.3 / 3 s', () => ctx.time.slowmo(0.3, 3, { easeIn: 0.15, easeOut: 0.4 }));
  button(tools, 'spam ×30', () => { for (let i = 0; i < 30; i++) audio.play('hit_slash_heavy', { delay: i * 0.01 }); });
  let tour = 0;
  button(tools, '▶ play all', () => { const t = ++tour; audio.list().forEach((n, i) => setTimeout(() => { if (t === tour) { audio.play(n); show(n); } }, i * 1400)); });
  button(tools, '■ stop all', () => { tour++; audio.stopAll(0.2); for (const b of root.querySelectorAll('button.live')) b.classList.remove('live'); loopHandles.clear(); });

  // sound groups
  const loopHandles = new Map();
  for (const [grp, title] of GROUPS) {
    const names = audio.list().filter((n) => audio.info(n).group === grp);
    if (!names.length) continue;
    const c = card(title, left, 'grp-' + grp);
    const bb = c.querySelector('.btns');
    for (const n of names) {
      const info = audio.info(n);
      const b = button(bb, n, (el) => {
        show(n);
        if (!info.loop) { audio.play(n); return; }
        const h = loopHandles.get(n);
        if (h) { h.stop(0.5); loopHandles.delete(n); el.classList.remove('live'); } else { loopHandles.set(n, audio.loop(n)); el.classList.add('live'); }
      }, info.loop ? 'loop' : '');
      b.title = info.desc;
    }
  }

  // preview
  const pc = card('미리보기 · Preview', right);
  pc.querySelector('.btns').remove();
  const cv = document.createElement('canvas');
  cv.className = 'pv';
  const title = document.createElement('div'), desc = document.createElement('div'), meta = document.createElement('div');
  title.style.cssText = 'font:600 14px var(--ed-display,serif);color:#f2dfb4;margin-bottom:6px';
  desc.className = 'desc'; meta.className = 'meta';
  pc.append(title, cv, desc, meta);
  const rc = card('측정 · Measure', right);
  const rb = rc.querySelector('.btns');
  const out = document.createElement('pre');
  out.style.cssText = 'margin:8px 0 0;max-height:320px;overflow:auto;font:11px/1.35 ui-monospace,Menlo,Consolas,monospace;color:#cfc6b6;white-space:pre';
  rc.appendChild(out);
  button(rb, 'run report', async () => { out.textContent = 'rendering every sound + 8 s of every track ...'; const r = await runReport(audio); out.textContent = r.table; });
  button(rb, 'self-test', async () => { out.textContent = 'running ...'; out.textContent = JSON.stringify(await selfTest(ctx), null, 1); });

  let showing = 0;
  async function show(name) {
    const id = ++showing;
    const info = audio.info(name);
    title.textContent = name;
    desc.textContent = info.desc;
    const r = await audio.render(name);
    if (!r || id !== showing) return;
    const w = Math.max(200, cv.clientWidth), h = 240;
    cv.width = w; cv.height = h;
    const g = cv.getContext('2d');
    g.clearRect(0, 0, w, h);
    drawBuffer(g, r.buffer, 0, 0, w, h);
    const m = measure(r.buffer);
    meta.textContent = `${r.buffer.duration.toFixed(2)} s (audible ${m.eff.toFixed(2)} s) · ${r.buffer.numberOfChannels === 2 ? 'stereo' : 'mono'} · peak ${m.peak.toFixed(2)} · loud ${m.loud.toFixed(1)} dB\n` +
      `attack ${m.attack} ms · centroid ${Math.round(m.centroid)} Hz · low ${Math.round(m.low * 100)} % · role ${info.role} · bus ${info.bus} · reverb ${info.verb}`;
  }

  // live state
  ctx.onUpdate(() => {
    const s = audio.state, st = audio.stats();
    chip.classList.toggle('on', s === 'running');
    chip.querySelector('b').textContent = s + (s === 'running' ? ` · ${st.voices} voices · ${(st.bytes / 1048576).toFixed(1)} MB` : '');
    for (const [t, b] of Object.entries(trackBtns)) b.classList.toggle('live', st.music.base === t || st.music.overlay === t);
  }, ctx.ORDER.UI);
  for (const el of root.querySelectorAll('[data-vol]')) el.oninput = () => audio.setVolume({ [el.dataset.vol]: +el.value });
  show('hit_crit');
}

/** Full-screen grid of every sound's waveform + spectrogram (for captures). */
async function drawSheet(ctx, audio, names = audio.list()) {
  let cv = document.querySelector('canvas.al-sheet');
  if (!cv) { cv = document.createElement('canvas'); cv.className = 'al-sheet'; document.getElementById('ui').appendChild(cv); }
  const n = names.length, cols = n <= 4 ? n : n <= 9 ? 3 : 6, rowsN = Math.ceil(n / cols);
  const W = Math.max(640, window.innerWidth), H = Math.max(480, window.innerHeight);
  cv.width = W; cv.height = H;
  cv.style.width = W + 'px'; cv.style.height = H + 'px';
  const g = cv.getContext('2d');
  g.fillStyle = '#06060a';
  g.fillRect(0, 0, W, H);
  const cw = W / cols, ch = (H - 24) / rowsN;
  g.font = '12px ui-monospace,Menlo,monospace';
  g.fillStyle = '#d8b46a';
  g.fillText('ECLIPSE DUEL audio — waveform (gold) + log-frequency spectrogram 40 Hz-20 kHz, each cell spans its own duration', 8, 16);
  for (let i = 0; i < names.length; i++) {
    const r = await audio.render(names[i]);
    if (!r) continue;
    const x = (i % cols) * cw + 4, y = 24 + Math.floor(i / cols) * ch + 2;
    drawBuffer(g, r.buffer, x, y + 14, cw - 8, ch - 18);
    const m = measure(r.buffer);
    g.fillStyle = '#efe6d2';
    g.fillText(`${names[i]}  ${r.buffer.duration.toFixed(2)}s  ${m.loud.toFixed(0)}dB`, x, y + 10);
  }
  return names.length;
}

/** Full-screen rows of 8 s music renders (through the mix chain) at several intensities (for captures). */
async function drawMusicSheet(ctx, audio) {
  let cv = document.querySelector('canvas.al-sheet');
  if (!cv) { cv = document.createElement('canvas'); cv.className = 'al-sheet'; document.getElementById('ui').appendChild(cv); }
  const W = Math.max(640, window.innerWidth), H = Math.max(480, window.innerHeight);
  cv.width = W; cv.height = H;
  cv.style.width = W + 'px'; cv.style.height = H + 'px';
  const g = cv.getContext('2d');
  g.fillStyle = '#06060a';
  g.fillRect(0, 0, W, H);
  const scenes = [['title', 'title', 0.5], ['battle  intensity 0', 'battle', 0], ['battle  intensity 0.5', 'battle', 0.5], ['battle  intensity 1', 'battle', 1],
    ['ultimate (alone)', 'ultimate', 1], ['battle + ultimate overlay', ['battle', 'ultimate'], 1], ['victory', 'victory', 1]];
  const rh = (H - 24) / scenes.length;
  g.font = '12px ui-monospace,Menlo,monospace';
  g.fillStyle = '#d8b46a';
  g.fillText('ECLIPSE DUEL music — first 8 s of each track through the mix chain: waveform + log-frequency spectrogram 40 Hz-20 kHz', 8, 16);
  for (let i = 0; i < scenes.length; i++) {
    const [label, tracks, I] = scenes[i];
    const b = await audio.renderScene({ seconds: 8, music: tracks, intensity: I });
    const y = 24 + i * rh;
    drawBuffer(g, b, 4, y + 14, W - 8, rh - 18);
    const m = measure(b);
    g.fillStyle = '#efe6d2';
    g.fillText(`${label}   loud ${m.loud.toFixed(1)} dB   centroid ${Math.round(m.centroid)} Hz   low ${Math.round(m.low * 100)} %`, 8, y + 10);
  }
  return scenes.length;
}

createLab({
  stage: false,
  setup(ctx) {
    const audio = createAudio(ctx);
    buildPanel(ctx, audio);
  },
  scenarios: {
    report: (ctx) => runReport(ctx.audio),
    selftest: (ctx) => selfTest(ctx),
    sheet: (ctx, lab, names) => drawSheet(ctx, ctx.audio, names),
    musicSheet: (ctx) => drawMusicSheet(ctx, ctx.audio),
    play: (ctx, lab, name = 'hit_crit') => { ctx.audio.unlock(); return ctx.audio.play(name) ? name : null; },
  },
});
