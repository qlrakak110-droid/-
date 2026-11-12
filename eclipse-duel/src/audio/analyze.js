// Measurement and self-test for the audio engine (used by src/labs/audio.js; not imported by the game).
//
//   measure(buffer)          -> { dur, eff, peak, rms, loud, attack, centroid, low, high, dc, nan, endDb }
//   runReport(audio)         -> every one-shot + 8 s of every music track measured and flagged, a stress mix, a table
//   selfTest(ctx)            -> createAudio in test mode / without WebAudio / before and after unlock, voice limits
//   spectrogram(buffer, o)   -> log-frequency dB image data for drawing

import { loudness } from './kit.js';
import { createAudio } from './index.js';

/** Expected effective length (s) per role, plus attack (ms) / low-end share minimums for impacts. */
export const ROLES = {
  ui: { eff: [0.03, 0.6] },
  whoosh: { eff: [0.18, 1.2], centroidMin: 900 },
  hit: { eff: [0.2, 2.0], attack: 10, low: 0.08 },
  big: { eff: [1.0, 5.0], attack: 15, low: 0.15 },
  foley: { eff: [0.06, 1.3] },
  element: { eff: [0.25, 3.0] },
  riser: { eff: [0.7, 3.0] },
  magic: { eff: [0.4, 2.5] },
  loop: { eff: [2.0, 8.0], loop: true },
  stinger: { eff: [1.2, 5.0] },
  transition: { eff: [0.5, 2.0] },
};

function fft(re, im) {
  const n = re.length;
  for (let i = 1, j = 0; i < n; i++) {
    let bit = n >> 1;
    for (; j & bit; bit >>= 1) j ^= bit;
    j ^= bit;
    if (i < j) { let t = re[i]; re[i] = re[j]; re[j] = t; t = im[i]; im[i] = im[j]; im[j] = t; }
  }
  for (let len = 2; len <= n; len <<= 1) {
    const ang = (-2 * Math.PI) / len, wr = Math.cos(ang), wi = Math.sin(ang), h = len >> 1;
    for (let i = 0; i < n; i += len) {
      let cr = 1, ci = 0;
      for (let j = 0; j < h; j++) {
        const a = i + j, b = a + h;
        const xr = re[b] * cr - im[b] * ci, xi = re[b] * ci + im[b] * cr;
        re[b] = re[a] - xr; im[b] = im[a] - xi; re[a] += xr; im[a] += xi;
        const t = cr * wr - ci * wi; ci = cr * wi + ci * wr; cr = t;
      }
    }
  }
}

function monoOf(buf) {
  const n = buf.length, C = buf.numberOfChannels, m = new Float32Array(n);
  for (let c = 0; c < C; c++) { const d = buf.getChannelData(c); for (let i = 0; i < n; i++) m[i] += d[i] / C; }
  return m;
}

/**
 * Measure a buffer. dur / eff (s; eff = until the last sample above -60 dB re peak), peak (abs), rms (dBFS over the
 * effective part, channel powers summed), loud (K-weighted 100 ms max, dB), attack (ms from onset to 90 % of peak),
 * centroid (Hz, energy-weighted), low / high (energy share below 150 Hz / above 4 kHz), dc (mean), nan (count),
 * endDb (last 10 ms level re peak, dB).
 */
export function measure(buf) {
  const sr = buf.sampleRate, n = buf.length, C = buf.numberOfChannels;
  let peak = 0, nan = 0;
  const B = Math.max(1, Math.round(sr * 0.001)), nb = Math.ceil(n / B), blk = new Float32Array(nb);
  for (let c = 0; c < C; c++) {
    const d = buf.getChannelData(c);
    for (let i = 0; i < n; i++) {
      const x = d[i];
      if (!Number.isFinite(x)) { nan++; continue; }
      const a = Math.abs(x), b = (i / B) | 0;
      if (a > blk[b]) blk[b] = a;
      if (a > peak) peak = a;
    }
  }
  const mono = monoOf(buf);
  let dc = 0;
  for (let i = 0; i < n; i++) dc += Number.isFinite(mono[i]) ? mono[i] : 0;
  dc /= n || 1;
  let onset = 0, top = 0, last = 0;
  while (onset < nb && blk[onset] < peak * 0.05) onset++;
  while (top < nb && blk[top] < peak * 0.9) top++;
  for (let i = nb - 1; i >= 0; i--) if (blk[i] > peak * 1e-3) { last = i; break; }
  const eff = ((last + 1) * B) / sr;
  let endMax = 0;
  for (let i = Math.max(0, nb - 10); i < nb; i++) endMax = Math.max(endMax, blk[i]);
  let sq = 0;
  const ne = Math.min(n, (last + 1) * B);
  for (let c = 0; c < C; c++) { const d = buf.getChannelData(c); for (let i = 0; i < ne; i++) if (Number.isFinite(d[i])) sq += d[i] * d[i]; }
  // spectrum: Hann frames over the active part, energy-weighted
  const N = 2048, hop = 1024, re = new Float64Array(N), im = new Float64Array(N);
  let eSum = 0, cSum = 0, eLow = 0, eHigh = 0;
  for (let s = 0; s + N <= Math.max(N, ne); s += hop) {
    for (let i = 0; i < N; i++) { const x = s + i < n ? mono[s + i] : 0; re[i] = (Number.isFinite(x) ? x : 0) * (0.5 - 0.5 * Math.cos((2 * Math.PI * i) / (N - 1))); im[i] = 0; }
    fft(re, im);
    for (let k = 1; k < N / 2; k++) {
      const e = re[k] * re[k] + im[k] * im[k], f = (k * sr) / N;
      eSum += e; cSum += e * f;
      if (f < 150) eLow += e; else if (f > 4000) eHigh += e;
    }
  }
  return {
    dur: n / sr, eff, peak, rms: 10 * Math.log10(sq / Math.max(1, ne) + 1e-12), loud: loudness(buf).max,
    attack: Math.max(0, top - onset), centroid: eSum > 0 ? cSum / eSum : 0, low: eSum > 0 ? eLow / eSum : 0, high: eSum > 0 ? eHigh / eSum : 0,
    dc, nan, endDb: 20 * Math.log10((endMax + 1e-12) / (peak + 1e-12)),
  };
}

/**
 * Loop seam: the jump from the last sample back to the first, relative to the mean sample-to-sample step.
 * ~1 = invisible seam; a click would be >> 4.
 */
export function seamOf(buf) {
  let worst = 0;
  for (let c = 0; c < buf.numberOfChannels; c++) {
    const d = buf.getChannelData(c), n = d.length;
    let step = 0;
    for (let i = 1; i < n; i++) step += Math.abs(d[i] - d[i - 1]);
    worst = Math.max(worst, Math.abs(d[0] - d[n - 1]) / (step / (n - 1) + 1e-9));
  }
  return worst;
}

/** Problems of a measured sound for its role. */
export function flagsOf(m, role) {
  const f = [];
  if (m.nan) f.push('NAN');
  if (m.peak < 0.02) f.push('SILENT');
  if (m.peak > 0.99) f.push('CLIP');
  if (Math.abs(m.dc) > 0.005) f.push('DC');
  const r = ROLES[role];
  if (r) {
    if (m.eff < r.eff[0]) f.push('SHORT');
    if (m.eff > r.eff[1]) f.push('LONG');
    if (r.attack && m.attack > r.attack) f.push('SLOW-ATTACK');
    if (r.low && m.low < r.low) f.push('THIN');
    if (r.centroidMin && m.centroid < r.centroidMin) f.push('DULL');
    if (!r.loop && m.endDb > -50) f.push('CUT');
    if (r.loop && m.seam > 4) f.push('SEAM');
  }
  return f;
}

const r1 = (x, d = 1) => Math.round(x * Math.pow(10, d)) / Math.pow(10, d);

function tableOf(rows, cols) {
  const head = cols.map((c) => c[0]);
  const lines = rows.map((r) => cols.map(([, f]) => String(f(r))));
  const w = head.map((h, i) => Math.max(h.length, ...lines.map((l) => l[i].length)));
  const fmt = (cells) => cells.map((c, i) => (i === 0 ? c.padEnd(w[i]) : c.padStart(w[i]))).join('  ');
  return [fmt(head), ...lines.map(fmt)].join('\n');
}

const SFX_COLS = [
  ['sound', (r) => r.name], ['role', (r) => r.role], ['dur', (r) => r.dur.toFixed(2)], ['eff', (r) => r.eff.toFixed(2)], ['peak', (r) => r.peak.toFixed(3)],
  ['rms dB', (r) => r.rms.toFixed(1)], ['loud', (r) => r.loud.toFixed(1)], ['atk ms', (r) => r.attack], ['centroid', (r) => Math.round(r.centroid)],
  ['low%', (r) => Math.round(r.low * 100)], ['hi%', (r) => Math.round(r.high * 100)], ['norm dB', (r) => r.norm.toFixed(1)], ['ch', (r) => r.channels],
  ['flags', (r) => r.flags.join(',') + (r.seam != null ? ' seam ' + r.seam.toFixed(1) : '') || 'ok'],
];
const MUS_COLS = [
  ['music (8 s)', (r) => r.name], ['peak', (r) => r.peak.toFixed(3)], ['rms dB', (r) => r.rms.toFixed(1)], ['loud', (r) => r.loud.toFixed(1)],
  ['centroid', (r) => Math.round(r.centroid)], ['low%', (r) => Math.round(r.low * 100)], ['hi%', (r) => Math.round(r.high * 100)], ['dc', (r) => r.dc.toFixed(4)], ['flags', (r) => r.flags.join(',') || 'ok'],
];

/**
 * Render every sound and 8 s of every music track offline and measure them.
 * @param {object} audio  engine from createAudio (works in test mode)
 */
export async function runReport(audio) {
  const sounds = [];
  for (const name of audio.list()) {
    const r = await audio.render(name);
    const info = audio.info(name);
    if (!r) { sounds.push({ name, role: info.role, error: 'no render' }); continue; }
    const m = measure(r.buffer);
    if (info.loop) m.seam = seamOf(r.buffer);
    sounds.push({ name, role: info.role, ...m, norm: r.gain, rawPeak: r.rawPeak, channels: r.buffer.numberOfChannels, flags: flagsOf(m, info.role) });
  }
  const avg = (roles) => { const a = sounds.filter((s) => roles.includes(s.role) && s.loud != null); return a.reduce((t, s) => t + s.loud, 0) / Math.max(1, a.length); };
  const groups = { impacts: avg(['hit', 'big']), whooshes: avg(['whoosh']), ui: avg(['ui']) };

  const music = [];
  const scenes = [['title', 'title', 0.5], ['battle i=0', 'battle', 0], ['battle i=0.5', 'battle', 0.5], ['battle i=1', 'battle', 1],
    ['ultimate', 'ultimate', 1], ['battle+ultimate', ['battle', 'ultimate'], 1], ['victory', 'victory', 1]];
  for (const [label, tracks, I] of scenes) {
    const b = await audio.renderScene({ seconds: 8, music: tracks, intensity: I });
    const m = measure(b);
    music.push({ name: label, ...m, flags: flagsOf(m, null) });
  }

  // worst case for the output stage: 30 heavy one-shots inside 120 ms over full-intensity battle music, no voice limit
  const heavy = ['hit_crit', 'explosion', 'ult_impact', 'hit_slash_heavy', 'guard_break', 'volt_strike', 'fire_burst', 'shockwave', 'ice_shatter', 'hit_blunt'];
  const events = Array.from({ length: 30 }, (_, i) => [0.5 + (i % 10) * 0.012 + Math.floor(i / 10) * 0.004, heavy[i % heavy.length]]);
  const sb = await audio.renderScene({ seconds: 4, music: 'battle', intensity: 1, events });
  const sm = measure(sb);
  const stress = { peak: r1(sm.peak, 3), loud: r1(sm.loud), nan: sm.nan, clipped: sm.peak > 0.99 };

  // the same mix chain the game hears: one-shots alone vs. full battle music
  const heard = {};
  for (const [label, o] of [['battle i=1 (music)', { music: 'battle', intensity: 1, seconds: 8 }], ['hit_slash_heavy', { events: [[0.05, 'hit_slash_heavy']] }],
    ['hit_slash_light', { events: [[0.05, 'hit_slash_light']] }], ['swing_heavy', { events: [[0.05, 'swing_heavy']] }], ['step', { events: [[0.05, 'step']] }], ['ui_select', { events: [[0.05, 'ui_select']] }]]) {
    heard[label] = r1(loudness(await audio.renderScene({ seconds: 1.5, ...o })).max);
  }

  const flagged = sounds.filter((s) => s.flags && s.flags.length).map((s) => s.name + ':' + s.flags.join(','));
  await audio.prewarm();  // every variant and instrument: the memory the game holds at this tier
  const stats = audio.stats();
  const table = tableOf(sounds.filter((s) => !s.error), SFX_COLS) + '\n\n' + tableOf(music, MUS_COLS) +
    `\n\nloudness (mean K-weighted 100 ms max): impacts ${groups.impacts.toFixed(1)} dB > whooshes ${groups.whooshes.toFixed(1)} dB > ui ${groups.ui.toFixed(1)} dB : ${groups.impacts > groups.whooshes && groups.whooshes > groups.ui ? 'OK' : 'WRONG ORDER'}` +
    `\nas heard through the mix chain (K-weighted 100 ms max): ${Object.entries(heard).map(([k, v]) => k + ' ' + v.toFixed(1)).join(' | ')}` +
    `\nstress (30 heavy hits in 120 ms over battle i=1, no voice limit): peak ${stress.peak} loud ${stress.loud} dB ${stress.clipped ? 'CLIPPED' : 'no clip'}` +
    `\nall assets at this tier (every variant + instrument): ${stats.buffers} buffers, ${(stats.bytes / 1048576).toFixed(1)} MB (music ${(stats.musicBytes / 1048576).toFixed(1)} MB)`;
  return {
    sounds: sounds.map((s) => (s.error ? s : { name: s.name, role: s.role, dur: r1(s.dur, 3), eff: r1(s.eff, 3), peak: r1(s.peak, 3), rms: r1(s.rms), loud: r1(s.loud), attackMs: s.attack, centroid: Math.round(s.centroid), low: r1(s.low, 3), high: r1(s.high, 3), dc: r1(s.dc, 5), nan: s.nan, endDb: r1(s.endDb), norm: r1(s.norm), channels: s.channels, flags: s.flags })),
    music: music.map((m) => ({ name: m.name, peak: r1(m.peak, 3), rms: r1(m.rms), loud: r1(m.loud), centroid: Math.round(m.centroid), low: r1(m.low, 3), high: r1(m.high, 3), dc: r1(m.dc, 5), nan: m.nan, flags: m.flags })),
    groups: { impacts: r1(groups.impacts), whooshes: r1(groups.whooshes), ui: r1(groups.ui), ordered: groups.impacts > groups.whooshes && groups.whooshes > groups.ui },
    heard, stress, flagged, memoryMB: r1(stats.bytes / 1048576, 2), buffers: stats.buffers, table,
  };
}

/**
 * API safety checks: test mode, missing WebAudio, before unlock, throttling and voice limits on a live context.
 * @param {object} ctx  app context (copied; the lab's own ctx.audio is untouched)
 */
export async function selfTest(ctx) {
  const out = {};
  const base = { ...ctx, audio: null };
  const exercise = (a) => {
    const r = { unlock: a.unlock(), play: a.play('hit_crit', { volume: 1, pitch: 1.2, pan: -0.5, delay: 0.1 }), unknown: a.play('no_such_sound') };
    const h = a.loop('fire_loop', { volume: 0.5 });
    h.setVolume(0.2, 0.1); h.setPitch(1.1); h.setPan(0.3); h.stop(0.1);
    a.music('battle'); a.music('ultimate'); a.setIntensity(0.8); a.music(null);
    a.setVolume({ master: 0.5, sfx: 0.7, music: 0.2 }); a.duck(0.5, 0.3); a.stopAll();
    r.loopPlaying = h.playing;
    r.state = a.state;
    return r;
  };
  const guard = async (label, fn) => { try { out[label] = await fn(); } catch (e) { out[label] = { error: String((e && e.stack) || e) }; } };

  await guard('testMode', () => { const a = createAudio({ ...base, test: true }); const r = exercise(a); r.names = a.list().length; a.dispose(); return r; });

  await guard('noWebAudio', async () => {
    const keys = ['AudioContext', 'webkitAudioContext', 'OfflineAudioContext', 'webkitOfflineAudioContext'];
    const saved = keys.map((k) => window[k]);
    keys.forEach((k) => { window[k] = undefined; });
    try {
      const a = createAudio({ ...base, test: false });
      const r = exercise(a);
      r.render = await a.render('hit_crit');
      r.scene = await a.renderScene({ seconds: 1, music: 'battle' });
      a.dispose();
      return r;
    } finally { keys.forEach((k, i) => { window[k] = saved[i]; }); }
  });

  await guard('live', async () => {
    const a = createAudio({ ...base, test: false });
    const r = { stateBefore: a.state, playBeforeUnlock: a.play('hit_crit'), contextBeforeUnlock: !!a.context };
    r.unlock = a.unlock();
    for (let i = 0; i < 100 && a.state !== 'running'; i++) await new Promise((res) => setTimeout(res, 20));
    r.stateAfter = a.state;
    const names = ['hit_slash_heavy', 'hit_slash_light', 'hit_blunt', 'guard', 'swing_light', 'swing_heavy', 'step', 'dodge', 'volt_zap', 'ice_crack', 'fire_ignite', 'magic_cast'];
    for (const n of names) await a.render(n);
    let started = 0;
    for (let i = 0; i < 40; i++) if (a.play('hit_slash_heavy')) started++;
    r.spamSameTick = started;                         // throttle: only the first gets through
    started = 0;
    for (let i = 0; i < 40; i++) if (a.play('hit_slash_light', { delay: 0.2 + i * 0.05 })) started++;
    r.spamSpaced = started;                           // all pass the throttle ...
    await new Promise((res) => setTimeout(res, 30));
    r.lightAlive = a.stats().voices;                  // ... but per-name polyphony caps the live voices
    for (let i = 0; i < 120; i++) a.play(names[i % names.length], { delay: 0.3 + i * 0.041 });
    await new Promise((res) => setTimeout(res, 30));
    r.voicesAfterFlood = a.stats().voices;
    r.maxVoices = a.stats().maxVoices;
    const h = a.loop('rune', { volume: 0.3 });
    await new Promise((res) => setTimeout(res, 300));
    r.loopPlaying = h.playing;
    h.stop(0.05);
    a.music('battle');
    await new Promise((res) => setTimeout(res, 600));
    r.music = a.stats().music;
    a.dispose();
    r.stateDisposed = a.state;
    r.playAfterDispose = a.play('hit_crit');
    return r;
  });
  return out;
}

/**
 * Spectrogram on a log-frequency axis (40 Hz .. 20 kHz).
 * @returns {{cols: number, rows: number, db: Float32Array}}  db[row * cols + col], row 0 = highest frequency
 */
export function spectrogram(buf, { cols = 200, rows = 96, N = 1024 } = {}) {
  const sr = buf.sampleRate, mono = monoOf(buf), n = mono.length;
  const re = new Float64Array(N), im = new Float64Array(N), db = new Float32Array(cols * rows);
  const lo = Math.log(40), hi = Math.log(Math.min(20000, sr / 2));
  for (let c = 0; c < cols; c++) {
    const s = Math.round((c / cols) * Math.max(0, n - N));
    for (let i = 0; i < N; i++) { re[i] = (mono[s + i] || 0) * (0.5 - 0.5 * Math.cos((2 * Math.PI * i) / (N - 1))); im[i] = 0; }
    fft(re, im);
    for (let r = 0; r < rows; r++) {
      const f0 = Math.exp(lo + ((hi - lo) * (rows - 1 - r)) / rows), f1 = Math.exp(lo + ((hi - lo) * (rows - r)) / rows);
      const k0 = Math.max(1, Math.floor((f0 * N) / sr)), k1 = Math.max(k0, Math.ceil((f1 * N) / sr));
      let e = 0;
      for (let k = k0; k <= k1 && k < N / 2; k++) e = Math.max(e, re[k] * re[k] + im[k] * im[k]);
      db[r * cols + c] = 10 * Math.log10(e + 1e-12);
    }
  }
  return { cols, rows, db };
}
