// In-fight HUD: forged health bars with a delayed-damage ghost and a lit leading edge, the eclipse timer medallion,
// round pips, FP / ULT meters (the ULT orb ignites as an event), skill slots with cooldown sweeps, combo counters,
// the announcer and cinematic mode. Every per-frame write is cached: a DOM property is only touched when its value
// changes, and bars / sweeps move through transforms (no layout).

import { h, esc } from './anim.js';
import { icon, corona, eclipseMark, weaponArt } from './icons.js';
import { clamp, Ease } from '../core/math.js';

const SIDES = ['p1', 'p2'];

// ---------------------------------------------------------------------------------------------------------------
// shared parts (also used by the touch pad)

/** Radial sweep made of two rotating half-planes (transform only). frac 0..1 = covered fraction, clockwise from 12. */
export function makePie(cls = '') {
  const el = h('div.pie' + (cls ? '.' + cls : ''), null, h('div.pie-r', null, h('div.pie-rr')), h('div.pie-l', null, h('div.pie-ll')));
  el._r = el.firstChild.firstChild;
  el._l = el.lastChild.firstChild;
  el._v = -1;
  return el;
}
export function setPie(el, frac) {
  const q = Math.round(clamp(frac) * 720) / 720;
  if (q === el._v) return;
  el._v = q;
  el._r.style.transform = 'rotate(' + (Math.min(q, 0.5) * 360).toFixed(2) + 'deg)';
  el._l.style.transform = 'rotate(' + (Math.max(q - 0.5, 0) * 360).toFixed(2) + 'deg)';
}
/** Write a style property only if it changed. */
export function put(el, prop, v) {
  const k = '_' + prop;
  if (el[k] === v) return;
  el[k] = v;
  el.style[prop] = v;
}
export function putText(el, v) {
  const s = String(v);
  if (el._txt === s) return;
  el._txt = s;
  el.textContent = s;
}
export function putClass(el, cls, on) {
  const k = '_c_' + cls;
  if (el[k] === on) return;
  el[k] = on;
  el.classList.toggle(cls, on);
}

// the timer medallion: a black sun (engraved rims, hour ticks) inside a slowly turning corona
const TIMER_DISC = (() => {
  let ticks = '';
  for (let i = 0; i < 12; i++) {
    const a = (i / 12) * Math.PI * 2, r0 = i % 3 ? 33.2 : 31.6, r1 = 35;
    ticks += `M${(50 + Math.cos(a) * r0).toFixed(2)} ${(50 + Math.sin(a) * r0).toFixed(2)}L${(50 + Math.cos(a) * r1).toFixed(2)} ${(50 + Math.sin(a) * r1).toFixed(2)}`;
  }
  return `<svg viewBox="0 0 100 100" fill="none" aria-hidden="true">
    <circle cx="50" cy="50" r="37.5" fill="#030306" stroke="currentColor" stroke-width="1.8"/>
    <circle cx="50" cy="50" r="35" stroke="currentColor" stroke-opacity=".3" stroke-width=".6"/>
    <path d="${ticks}" stroke="currentColor" stroke-opacity=".55" stroke-width=".9"/>
    <circle cx="50" cy="50" r="45.5" stroke="currentColor" stroke-opacity=".35" stroke-width=".6" stroke-dasharray=".8 2.6"/>
    <path d="M4 50h5M91 50h5" stroke="currentColor" stroke-opacity=".75" stroke-width="1.2"/>
  </svg>`;
})();

// ---------------------------------------------------------------------------------------------------------------
// announcer presets (Korean main line, short English sub)

const PRESETS = {
  round: (o) => ({ text: '라운드', sub: `ROUND ${o.round || 1}`, num: String(o.round || 1), style: 'round' }),
  final: (o) => ({ text: '최종 라운드', sub: 'FINAL ROUND', num: o.round ? String(o.round) : '', style: 'round', final: true }),
  fight: () => ({ text: '결투', sub: 'FIGHT', style: 'fight' }),
  ko: () => ({ text: 'K.O.', sub: '격파', style: 'ko' }),
  perfect: () => ({ text: '완벽', sub: 'PERFECT', style: 'perfect' }),
  timeup: () => ({ text: '시간 종료', sub: 'TIME UP', style: 'timeup' }),
  draw: () => ({ text: '무승부', sub: 'DRAW', style: 'timeup' }),
};
const DURATION = { round: 1.6, fight: 1.0, ko: 2.3, perfect: 2.1, timeup: 1.8, banner: 1.6, ult: 1.9, win: 2.4 };
const IN_T = { round: 0.34, fight: 0.16, ko: 0.16, perfect: 0.3, timeup: 0.4, banner: 0.3, ult: 0.3, win: 0.34 };
// the K.O. cut: the line rises to the right at this angle; the two halves slide apart along it
const KO_DEG = 12, KO_COS = Math.cos((KO_DEG * Math.PI) / 180), KO_SIN = Math.sin((KO_DEG * Math.PI) / 180);

/** Map free text like 'ROUND 2' / 'K.O.' / 'TIME UP' onto a preset key (or null). */
function presetOf(text) {
  const t = String(text || '').trim();
  const low = t.toLowerCase();
  if (PRESETS[low]) return [low, {}];
  const m = /^round\s*(\d+)$/i.exec(t);
  if (m) return ['round', { round: Number(m[1]) }];
  if (/^final\s*round$/i.test(t)) return ['final', {}];
  if (/^fight!?$/i.test(t)) return ['fight', {}];
  if (/^k\.?\s*o\.?!?$/i.test(t)) return ['ko', {}];
  if (/^perfect!?$/i.test(t)) return ['perfect', {}];
  if (/^time\s*up!?$/i.test(t)) return ['timeup', {}];
  if (/^draw!?$/i.test(t)) return ['draw', {}];
  return null;
}

// ---------------------------------------------------------------------------------------------------------------

export function createHud(ui) {
  const { anim } = ui;
  const root = h('div.ed-hud');
  const top = h('div.hud-top');
  const tmRays = h('div.tm-rays', { html: corona({ n: 60, r0: 39, len: 8, w: 1.1 }) });
  const tmNum = h('b.tm-num', { text: '99' });
  const tm = h('div.hud-timer', null, h('i.tm-glow'), tmRays, h('div.tm-disc', { html: TIMER_DISC }), h('i.tm-bead'), tmNum);
  const annLayer = h('div.hud-ann');
  const hints = h('div.hud-hints');
  const pauseBtn = h('button.hud-pause', { type: 'button', 'aria-label': '일시정지 Pause', html: icon('pause') });
  pauseBtn.addEventListener('pointerdown', (e) => { e.preventDefault(); e.stopPropagation(); });
  pauseBtn.addEventListener('click', (e) => { e.stopPropagation(); ui.emit('pause'); });

  const S = [0, 1].map(makeSide);
  const deck = h('div.hud-deck');
  top.append(S[0].plate, tm, S[1].plate);
  // the announcer paints last: a card covers the pause button for its second or two (taps still reach it)
  root.append(top, S[0].dock, S[1].dock, S[0].combo, S[1].combo, hints, pauseBtn, annLayer);

  let roundsMax = 2;
  let timeShown = null, timeLow = false;
  let cine = 0, cineTarget = 0;
  let clock = 0;
  let hintsOn = false;

  function makeSide(i) {
    const s = SIDES[i];
    const name = h('span.hud-name');
    const nameKo = h('span.hud-name-ko');
    const title = h('span.hud-title');
    const id = h('div.hud-id', null, name, nameKo, title);
    const ghost = h('div.hp-ghost');
    const ghostHot = h('div.hp-ghost-hot');
    const sheen = h('div.hp-sheen');
    const fillHot = h('div.hp-fill-hot');
    const fill = h('div.hp-fill', null, sheen, fillHot);
    const edge = h('div.hp-edge');
    const track = h('div.hp-track', null, ghost, ghostHot, fill, edge, h('div.hp-notch'));
    const hp = h('div.hud-hp', null, h('div.hp-frame', null, track), h('i.hp-cap'));
    const pips = h('div.hud-pips');
    const miniFp = h('i');
    const miniUlt = h('i');
    const miniUltLabel = h('span.mini-ult-label', { text: '궁극기' });
    const mini = h(`div.hud-mini.${s}`, null, h('div.mini-fp', null, h('b', { text: 'FP' }), h('div.mini-bar', null, miniFp)), h('div.mini-ult', null, h('b', { text: 'ULT' }), h('div.mini-bar', null, miniUlt), miniUltLabel));
    const under = h('div.hud-under', null, pips, mini);
    const plate = h(`div.hud-plate.${s}`, null, id, hp, under);

    // dock: ULT orb (aura, glow, corona, gauge ring, core, ignition burst / flash / flare) + skills + FP bar
    const ring = makePie('orb-ring');
    const orbAura = h('i.orb-aura');
    const orbGlow = h('i.orb-glow');
    const orbRays = h('i.orb-rays', { html: corona({ n: 48, r0: 35, len: 13, w: 1.5 }) });
    const orbCore = h('i.orb-core', { html: icon('ult') });
    const orbFlash = h('i.orb-flash');
    const orbBurst = h('i.orb-burst');
    const orbBurst2 = h('i.orb-burst');
    const orbFlare = h('i.orb-flare');
    const orbKey = h('span.keycap.orb-key');
    const orb = h('div.ult-orb', null, orbAura, orbGlow, orbRays, h('i.orb-base'), ring, orbCore, orbFlash, orbBurst, orbBurst2, orbFlare, orbKey);
    const orbLabel = h('div.orb-label', { html: '<b>궁극기</b><span>ULT READY</span>' });
    const skills = h('div.dock-skills');
    const fpFill = h('i.fp-fill');
    const fpNum = h('span.fp-val', { text: '0' });
    const fp = h('div.dock-fp', null, h('span.fp-label', { text: 'FP' }), h('div.fp-bar', null, fpFill, h('i.fp-ticks')), fpNum);
    const dock = h(`div.hud-dock.${s}`, null, orb, h('div.dock-main', null, orbLabel, skills, fp));

    // combo
    const cbNum = h('b.cb-num', { text: '0' });
    const cbHot = h('b.cb-num.cb-hot', { text: '0' });
    const cbDmg = h('b', { text: '0' });
    const cbInner = h('div.cb-inner', null,
      h('div.cb-row', null, h('div.cb-nums', null, cbNum, cbHot), h('div.cb-hits', { html: '<span>연타</span><em>HITS</em>' })),
      h('div.cb-dmg', null, h('span', { text: '피해' }), cbDmg, h('em', { text: 'DMG' })),
      h('i.cb-line'));
    const combo = h(`div.hud-combo.${s}`, null, cbInner);
    combo.style.opacity = '0';

    return {
      i, s, plate, dock, combo, mini, under, name, nameKo, title, hp, track, fill, fillHot, ghost, ghostHot, sheen, edge, pips, miniFp, miniUlt,
      ring, orb, orbAura, orbGlow, orbRays, orbCore, orbFlash, orbBurst, orbBurst2, orbFlare, orbKey, orbLabel, skills, fpFill, fpNum,
      cbNum, cbHot, cbDmg, cbInner,
      slots: [],
      // state
      hpR: 1, ghostR: 1, ghostWait: 0, hpMax: 1000, fpR: 0, fpVal: 0, fpMax: 100, ultR: 0, ultFull: false, raysS: 1, glowK: 1,
      rounds: -1, element: null, weapon: null, low: false, shake: 0, shakeAmp: 0,
      comboHits: 0, comboAge: 99, comboShown: false,
    };
  }

  function buildPips() {
    for (const sd of S) {
      sd.pips.innerHTML = '';
      for (let k = 0; k < roundsMax; k++) sd.pips.appendChild(h('i.pip'));
      sd.rounds = -1;
    }
  }
  buildPips();

  // ---------------------------------------------------------------------------------------------------------------
  // static info

  function setIdentity(sd, f) {
    if (!f) return;
    const en = f.nameEn || '';
    putText(sd.name, en || f.name || '');
    putText(sd.nameKo, en ? f.name || '' : '');
    putText(sd.title, f.title ? f.title + (f.titleEn ? ' · ' + f.titleEn : '') : '');
    if (f.element) setElement(sd, f.element);
    sd.weapon = f.weaponArt || null;
    const u = (f.moves || []).find((m) => m.slot === 'ult');
    sd.ultIcon = (u && u.icon) || 'ult';
    sd.orbCore.innerHTML = icon(sd.ultIcon) || icon('ult');
  }
  function setElement(sd, el) {
    if (sd.element === el) return;
    const nodes = [sd.plate, sd.dock, sd.combo, sd.mini];
    if (sd.i === 0 && ui.touch) nodes.push(ui.touch.el);
    for (const node of nodes) {
      if (sd.element) node.classList.remove('el-' + sd.element);
      node.classList.add('el-' + el);
    }
    sd.element = el;
  }

  // ---------------------------------------------------------------------------------------------------------------
  // per-frame values

  function setHp(sd, hpVal, hpMax) {
    const r = clamp(hpMax > 0 ? hpVal / hpMax : 0);
    if (r === sd.hpR) return;
    if (r < sd.hpR) {
      const dmg = sd.hpR - r;
      sd.ghostR = Math.max(sd.ghostR, sd.hpR);
      sd.ghostWait = 0.55;
      // white-hot flash on the lost segment and on the bar, jolt proportional to the hit
      anim.add(0.32, (k) => put(sd.ghostHot, 'opacity', (1 - k).toFixed(3)), { key: sd.ghostHot, ease: 'outQuad' });
      anim.add(0.22, (k) => put(sd.fillHot, 'opacity', (0.75 * (1 - k)).toFixed(3)), { key: sd.fillHot, ease: 'outQuad' });
      sd.shake = 0.22;
      sd.shakeAmp = Math.min(1, 0.25 + dmg * 6);
      put(sd.ghostHot, 'transform', `scaleX(${sd.ghostR.toFixed(4)})`);
    } else {
      sd.ghostR = r;
    }
    sd.hpR = r;
    put(sd.fill, 'transform', `scaleX(${r.toFixed(4)})`);
    put(sd.ghost, 'transform', `scaleX(${sd.ghostR.toFixed(4)})`);
    // the lit leading edge rides the boundary between fill and empty (a full-width layer moved by translateX)
    put(sd.edge, 'transform', `translateX(${((sd.i ? -1 : 1) * (1 - r) * 100).toFixed(2)}%)`);
    put(sd.edge, 'opacity', r > 0.002 && r < 0.998 ? '1' : '0');
    sd.low = r < 0.25 && r > 0;
    putClass(sd.plate, 'is-low', sd.low);
    if (!sd.low) put(sd.sheen, 'opacity', '');
  }

  function setFp(sd, fp, fpMax) {
    const r = clamp(fpMax > 0 ? fp / fpMax : 0);
    if (r !== sd.fpR) {
      sd.fpR = r;
      const t = `scaleX(${r.toFixed(4)})`;
      put(sd.fpFill, 'transform', t);
      put(sd.miniFp, 'transform', t);
    }
    const v = Math.floor(fp);
    if (v !== sd.fpVal) { sd.fpVal = v; putText(sd.fpNum, v); refreshAfford(sd); }
  }

  /** ULT ignition: white core flash, two shock rings, a horizontal flare, the corona snapping open, the label slam. */
  function ignite(sd) {
    const dir = sd.i ? 1 : -1;
    anim.add(1.0, (k, t) => {
      const T = t * 1.0;
      put(sd.orbFlash, 'opacity', (1 - Ease.outQuad(clamp(T / 0.5))).toFixed(3));
      const t1 = clamp(T / 0.65);
      put(sd.orbBurst, 'transform', `scale(${(0.85 + 1.9 * Ease.outQuart(t1)).toFixed(3)})`);
      put(sd.orbBurst, 'opacity', (1 - t1).toFixed(3));
      const t2 = clamp((T - 0.12) / 0.85);
      put(sd.orbBurst2, 'transform', `scale(${(0.85 + 3.4 * Ease.outQuart(t2)).toFixed(3)})`);
      put(sd.orbBurst2, 'opacity', (T < 0.12 ? 0 : 0.7 * (1 - t2)).toFixed(3));
      put(sd.orbFlare, 'transform', `scaleX(${Ease.outExpo(clamp(T / 0.32)).toFixed(3)})`);
      put(sd.orbFlare, 'opacity', (1 - clamp((T - 0.18) / 0.7)).toFixed(3));
      sd.raysS = 0.45 + 0.55 * Ease.outBack(clamp(T / 0.6));
      sd.glowK = 1 + 1.4 * (1 - Ease.outCubic(t));
      const l = clamp(T / 0.38);
      put(sd.orbLabel, 'opacity', clamp(T / 0.12).toFixed(3));
      put(sd.orbLabel, 'transform', `translateX(${(dir * 22 * (1 - Ease.outCubic(l))).toFixed(1)}px) scale(${(1.45 - 0.45 * Ease.outBack(l)).toFixed(3)})`);
    }, { key: sd.orbFlash, ease: 'linear' });
  }

  function setUlt(sd, ult, ultMax) {
    const r = clamp(ultMax > 0 ? ult / ultMax : 0);
    if (r === sd.ultR) return;
    sd.ultR = r;
    setPie(sd.ring, r);
    put(sd.miniUlt, 'transform', `scaleX(${r.toFixed(4)})`);
    const full = r >= 0.999;
    if (full !== sd.ultFull) {
      sd.ultFull = full;
      putClass(sd.dock, 'is-ult', full);
      putClass(sd.plate, 'is-ult', full);
      putClass(sd.mini, 'is-ult', full);
      if (full) ignite(sd);
      else {
        // spent: hand every ignition layer back to the stylesheet (hidden)
        anim.kill(sd.orbFlash);
        for (const el of [sd.orbGlow, sd.orbAura, sd.orbFlash, sd.orbBurst, sd.orbBurst2, sd.orbFlare, sd.orbLabel]) put(el, 'opacity', '');
        put(sd.orbRays, 'transform', '');
        put(sd.orbLabel, 'transform', '');
      }
      ui.emit('hud:ultReady', sd.i, full);
    }
  }

  function setRounds(sd, n) {
    if (n === sd.rounds) return;
    const pips = sd.pips.children;
    for (let k = 0; k < pips.length; k++) {
      const on = k < n;
      if (on && !(k < sd.rounds) && sd.rounds >= 0) {
        const p = pips[k];
        anim.add(0.5, (e) => put(p, 'transform', `rotate(45deg) scale(${(1 + 1.2 * (1 - e)).toFixed(3)})`), { key: p, ease: 'outBack' });
      }
      putClass(pips[k], 'on', on);
    }
    sd.rounds = n;
  }

  function setTime(t) {
    if (t === undefined) return;
    // compare the whole seconds first: no string work on the frames where the clock does not tick
    const n = t === null || !isFinite(t) ? -1 : Math.max(0, Math.ceil(t - 1e-6));
    if (n === timeShown) return;
    timeShown = n;
    putText(tmNum, n < 0 ? '∞' : n);
    const low = n >= 0 && n <= 10;
    putClass(tm, 'is-low', low);
    if (low && timeLow) anim.add(0.45, (k) => put(tmNum, 'transform', `scale(${(1.32 - 0.32 * k).toFixed(3)})`), { key: tmNum, ease: 'outCubic' });
    timeLow = low;
  }

  /** Key hints that follow the device: ULT orb keycap and the skill slots. */
  function refreshKeys() {
    for (const sd of S) {
      const k = ui.keyLabel('ult', sd.i);
      putText(sd.orbKey, k);
      putClass(sd.orbKey, 'is-empty', !k);
      sd.slots.forEach((sl, j) => {
        if (sl.keyFixed) return;
        const kk = ui.keyLabel('skill' + (j + 1), sd.i);
        putText(sl.key, kk);
        putClass(sl.key, 'is-empty', !kk);
      });
    }
  }

  // ---------------------------------------------------------------------------------------------------------------
  // skills

  function makeSlot(sd) {
    const pie = makePie('sk-pie');
    const hand = h('i.sk-hand');
    const glow = h('i.sk-glow');
    const flash = h('i.sk-flash');
    const ic = h('div.sk-ico');
    const face = h('div.sk-face', null, ic, pie, hand, glow);
    const cost = h('span.sk-cost');
    const key = h('span.keycap.sk-key');
    const el = h('div.sk', null, face, flash, cost, key);
    el._phase0 = sd.slots.length * 1.7; // the three ready pulses do not breathe in lockstep
    sd.skills.appendChild(el);
    return { el, pie, hand, glow, flash, ic, cost, key, iconName: null, ready: null, cd: -1, costV: -1, need: 0 };
  }

  function setSkills(side, list) {
    const sd = S[side];
    if (!sd || !list) return;
    while (sd.slots.length < list.length) sd.slots.push(makeSlot(sd));
    for (let j = 0; j < sd.slots.length; j++) {
      const sl = sd.slots[j], d = list[j];
      put(sl.el, 'display', d ? '' : 'none');
      if (!d) continue;
      const ic = d.icon || d.id;
      if (ic !== sl.iconName) { sl.iconName = ic; sl.ic.innerHTML = icon(ic) || icon('light'); }
      if (d.name !== sl.name) { sl.name = d.name; sl.el.title = d.name || ''; }
      sl.keyFixed = d.key !== undefined;
      const key = sl.keyFixed ? d.key : ui.keyLabel('skill' + (j + 1), side);
      putText(sl.key, key || '');
      putClass(sl.key, 'is-empty', !key);
      const cost = d.cost || 0;
      if (cost !== sl.costV) { sl.costV = cost; putText(sl.cost, cost ? cost : ''); }
      const cd = clamp(d.cd || 0);
      if (cd !== sl.cd) {
        sl.cd = cd;
        setPie(sl.pie, cd);
        put(sl.hand, 'transform', `rotate(${((1 - cd) * 360).toFixed(1)}deg)`);
        putClass(sl.el, 'is-cd', cd > 0);
      }
      const ready = d.ready !== undefined ? !!d.ready : cd <= 0 && sd.fpVal >= cost;
      if (ready !== sl.ready) {
        if (ready && sl.ready === false) {
          anim.add(0.55, (k) => {
            put(sl.flash, 'opacity', (1 - k).toFixed(3));
            put(sl.flash, 'transform', `scale(${(1 + 0.55 * k).toFixed(3)})`);
          }, { key: sl.flash, ease: 'outCubic' });
        }
        sl.ready = ready;
        putClass(sl.el, 'is-ready', ready);
        if (!ready) put(sl.glow, 'opacity', '');
      }
      sl.need = cost;
    }
    refreshAfford(sd);
    ui.emit('hud:skills', side, list);
  }
  function refreshAfford(sd) {
    for (const sl of sd.slots) putClass(sl.el, 'no-fp', sl.need > 0 && sd.fpVal < sl.need);
  }

  // ---------------------------------------------------------------------------------------------------------------
  // combo

  function setCombo(side, hits, damage) {
    const sd = S[side];
    if (!sd) return;
    if (!hits || hits < 2) {
      if (sd.comboShown) fadeCombo(sd);
      sd.comboHits = hits || 0;
      return;
    }
    putText(sd.cbNum, hits);
    putText(sd.cbHot, hits);
    putText(sd.cbDmg, Math.round(damage || 0));
    const dir = sd.i ? 1 : -1;
    if (!sd.comboShown) {
      sd.comboShown = true;
      anim.add(0.18, (k) => {
        put(sd.combo, 'opacity', k.toFixed(3));
        put(sd.combo, 'transform', `translateX(${(dir * 40 * (1 - k)).toFixed(1)}px)`);
      }, { key: sd.combo, ease: 'outCubic' });
    }
    if (hits > sd.comboHits) {
      const big = Math.min(1, 0.55 + hits * 0.03);
      anim.add(0.2, (k) => {
        const s = 1 + 0.5 * big * (1 - k);
        put(sd.cbInner, 'transform', `scale(${s.toFixed(3)}) rotate(${(dir * 5 * (1 - k)).toFixed(2)}deg)`);
        put(sd.cbHot, 'opacity', (1 - k).toFixed(3));
      }, { key: sd.cbInner, ease: 'outBack' });
    }
    sd.comboHits = hits;
    sd.comboAge = 0;
  }
  function fadeCombo(sd) {
    sd.comboShown = false;
    const dir = sd.i ? 1 : -1;
    anim.add(0.45, (k) => {
      put(sd.combo, 'opacity', (1 - k).toFixed(3));
      put(sd.combo, 'transform', `translateX(${(dir * 24 * k).toFixed(1)}px)`);
    }, { key: sd.combo, ease: 'inQuad' });
  }

  // ---------------------------------------------------------------------------------------------------------------
  // announcer: one card per call, built from layers (band, hairlines, emblem, shock ring, flare, text, echo ...)
  // and driven by a single tween (entrance, hold, exit). Every layer moves by transform / opacity.

  let annSeq = 0;
  const main = (text, cls = '') => h('div.an-main' + cls, null, h('span', { text }));

  function announce(text, o = {}) {
    const p = presetOf(text);
    let spec;
    if (p) spec = { ...PRESETS[p[0]]({ ...p[1], ...o }), ...(o.sub !== undefined ? { sub: o.sub } : null), ...(o.style ? { style: o.style } : null) };
    else spec = { text: String(text || ''), sub: o.sub || '', style: o.style || 'banner' };
    const style = DURATION[spec.style] ? spec.style : 'banner';
    const dur = o.duration || DURATION[style];
    const side = o.side === 1 ? 1 : o.side === 0 ? 0 : -1;
    const sd = side >= 0 ? S[side] : null;
    const elem = o.element || (sd && sd.element) || '';
    if (!o.keep) clearAnnounce(style === 'ult');

    const node = h(`div.ann.st-${style}` + (elem ? `.el-${elem}` : '') + (side >= 0 ? `.side-${SIDES[side]}` : '') + (spec.final ? '.is-final' : ''));
    const fit = h('div.an-fit');
    node.appendChild(fit);
    const L = {};
    const add = (k, el) => { L[k] = el; fit.appendChild(el); return el; };

    if (style === 'ult') {
      // cut-in: an element-lit band sweeps across with the fighter's weapon, the ultimate's name slams in
      const cut = add('cut', h('div.an-cut', null, h('div.an-cut-in', null, h('i.an-cut-glow'), h('i.an-cut-edge.a'), h('i.an-cut-edge.b'))));
      if (sd && sd.weapon) L.art = cut.firstChild.appendChild(h('div.an-art', null, h('div.an-art-in', { html: weaponArt(sd.weapon) })));
      add('flare', h('i.an-flare'));
      const who = sd ? sd.name.textContent : '';
      const kicker = o.kicker !== undefined ? o.kicker : '궁극기 · ULTIMATE';
      add('kick', h('div.an-kick', null, h('i'), h('span', { text: kicker }), who ? h('b', { text: who }) : null));
      add('main', main(spec.text));
      add('sub', h('div.an-sub', { text: spec.sub || '' }));
    } else {
      add('band', h('i.an-band'));
      add('lineA', h('i.an-line.a'));
      add('lineB', h('i.an-line.b'));
      if (style === 'round' || style === 'perfect') add('emblem', h('div.an-emblem', { html: eclipseMark() }));
      if (style === 'round' || style === 'fight' || style === 'ko' || style === 'perfect') { add('ring', h('i.an-ring')); add('flare', h('i.an-flare')); }
      if (style === 'fight' || style === 'ko') { add('blast', h('i.an-blast')); add('echo', main(spec.text, '.an-echo')); }
      if (style === 'round' && spec.num) add('num', h('div.an-num', { text: spec.num }));
      if (style === 'ko') {
        // two copies of the mark clipped above / below the cut line; they slide apart along it
        const split = add('split', h('div.an-split'));
        L.top = split.appendChild(h('div.an-half.top', null, main(spec.text)));
        L.bot = split.appendChild(h('div.an-half.bot', null, main(spec.text)));
        add('slash', h('i.an-slash'));
      } else add('main', main(spec.text));
      if (style === 'perfect') add('shine', h('i.an-shine'));
      add('sub', h('div.an-sub', { text: spec.sub || '' }));
    }
    if (!spec.sub) L.sub.style.display = 'none';
    annLayer.appendChild(node);

    const inT = IN_T[style];
    const outT = style === 'fight' ? 0.24 : 0.4;
    const dir = side === 1 ? 1 : -1;
    const k = ui.k || 1;
    const after = (T, t0, d) => clamp((T - t0) / d);
    // shared impact layers: shock ring, horizontal flare, white blast
    const impact = (T, t0, ringMax = 2.6) => {
      if (L.ring) {
        const r = after(T, t0, 0.6);
        put(L.ring, 'transform', `scale(${(0.25 + ringMax * Ease.outQuart(r)).toFixed(3)})`);
        put(L.ring, 'opacity', (T < t0 ? 0 : 0.9 * (1 - r)).toFixed(3));
      }
      if (L.flare) {
        put(L.flare, 'transform', `scaleX(${Ease.outExpo(after(T, t0 - 0.04, 0.3)).toFixed(3)})`);
        put(L.flare, 'opacity', (T < t0 - 0.04 ? 0 : 1 - after(T, t0 + 0.12, 0.6)).toFixed(3));
      }
      if (L.blast) put(L.blast, 'opacity', (T < t0 ? 0 : 0.85 * (1 - Ease.outQuad(after(T, t0, 0.28)))).toFixed(3));
    };
    const frame = (T) => {
      const a = clamp(T / inT), e = Ease.outCubic(a);
      const o2 = clamp((dur - T) / outT);
      put(node, 'opacity', (o2 < 1 ? Ease.inQuad(o2) : 1).toFixed(3));
      if (L.band) put(L.band, 'transform', `scaleY(${Ease.outExpo(after(T, 0, style === 'ko' ? 0.2 : 0.32)).toFixed(3)})`);
      if (L.lineA) {
        put(L.lineA, 'transform', `scaleX(${Ease.outExpo(after(T, 0.05, 0.6)).toFixed(3)})`);
        put(L.lineB, 'transform', `scaleX(${Ease.outExpo(after(T, 0.1, 0.6)).toFixed(3)})`);
      }
      if (L.sub && style !== 'ult') {
        const s = after(T, style === 'ko' ? 0.42 : 0.2, 0.32);
        put(L.sub, 'opacity', s.toFixed(3));
        put(L.sub, 'transform', `translateY(${(10 * (1 - Ease.outCubic(s))).toFixed(1)}px)`);
      }
      switch (style) {
        case 'round': {
          const em = after(T, 0, 0.7);
          put(L.emblem, 'transform', `rotate(${(-24 + 24 * Ease.outCubic(em) + T * 6).toFixed(2)}deg) scale(${(0.55 + 0.45 * Ease.outBack(em)).toFixed(3)})`);
          put(L.emblem, 'opacity', Math.min(1, T / 0.22).toFixed(3));
          impact(T, 0.22, 2.2);
          if (L.num) {
            const n = after(T, 0.12, 0.3);
            put(L.num, 'transform', `scale(${(1.9 - 0.9 * Ease.outQuart(n)).toFixed(3)})`);
            put(L.num, 'opacity', (T < 0.12 ? 0 : Math.min(1, n * 1.6)).toFixed(3));
          }
          const m = after(T, 0.18, 0.35);
          put(L.main, 'opacity', m.toFixed(3));
          put(L.main, 'transform', `translateY(${(12 * (1 - Ease.outCubic(m))).toFixed(1)}px)`);
          break;
        }
        case 'fight': {
          const s = 2.6 - 1.6 * Ease.outQuart(a);
          const j = T > inT && T < inT + 0.16 ? Math.sin((T - inT) * 110) * 5 * k * (1 - (T - inT) / 0.16) : 0;
          put(L.main, 'transform', `translate(${j.toFixed(1)}px,0) scale(${(s * (o2 < 1 ? 1 + (1 - o2) * 0.2 : 1)).toFixed(3)})`);
          put(L.main, 'opacity', Math.min(1, a * 2.2).toFixed(3));
          const ec = after(T, inT, 0.32);
          put(L.echo, 'transform', `scale(${(1 + 0.32 * Ease.outCubic(ec)).toFixed(3)})`);
          put(L.echo, 'opacity', (T < inT ? 0 : 0.5 * (1 - Ease.outQuad(ec))).toFixed(3));
          impact(T, inT, 3.2);
          break;
        }
        case 'ko': {
          const s = 3 - 2 * Ease.outQuart(a);
          const j = T > inT && T < inT + 0.2 ? Math.sin((T - inT) * 120) * 7 * k * (1 - (T - inT) / 0.2) : 0;
          put(L.split, 'transform', `translate(${j.toFixed(1)}px,0) scale(${s.toFixed(3)})`);
          put(L.split, 'opacity', Math.min(1, a * 2).toFixed(3));
          // the cut: slash draws across, then the halves part along it and stay parted
          const c = after(T, inT + 0.1, 0.2);
          put(L.slash, 'transform', `rotate(${-KO_DEG}deg) scaleX(${Ease.outExpo(c).toFixed(3)})`);
          put(L.slash, 'opacity', (T < inT + 0.1 ? 0 : 1 - 0.55 * after(T, inT + 0.45, 0.6)).toFixed(3));
          const d = 26 * k * Ease.outExpo(after(T, inT + 0.16, 0.35));
          put(L.top, 'transform', `translate(${(-d * KO_COS).toFixed(1)}px,${(d * KO_SIN - d * 0.4).toFixed(1)}px)`);
          put(L.bot, 'transform', `translate(${(d * KO_COS).toFixed(1)}px,${(-d * KO_SIN + d * 0.4).toFixed(1)}px)`);
          const ec = after(T, inT, 0.45);
          put(L.echo, 'transform', `scale(${(1 + 0.55 * Ease.outCubic(ec)).toFixed(3)})`);
          put(L.echo, 'opacity', (T < inT ? 0 : 0.5 * (1 - Ease.outQuad(ec))).toFixed(3));
          impact(T, inT, 3.4);
          const sb = after(T, 0.42, 0.32);
          put(L.sub, 'transform', `scale(${(1.35 - 0.35 * Ease.outQuart(sb)).toFixed(3)})`);
          break;
        }
        case 'perfect': {
          const em = after(T, 0, 0.9);
          put(L.emblem, 'transform', `rotate(${(T * 5).toFixed(2)}deg) scale(${(0.7 + 0.3 * Ease.outCubic(em)).toFixed(3)})`);
          put(L.emblem, 'opacity', (0.5 * Math.min(1, T / 0.3)).toFixed(3));
          put(L.main, 'transform', `scale(${(1.3 - 0.3 * e).toFixed(4)})`);
          put(L.main, 'opacity', e.toFixed(3));
          impact(T, 0.2, 2.6);
          const sh = after(T, 0.34, 0.75);
          put(L.shine, 'transform', `translateX(${(-300 + 600 * Ease.inOutCubic(sh)).toFixed(1)}%) skewX(-20deg)`);
          put(L.shine, 'opacity', (sh > 0 && sh < 1 ? 1 : 0).toFixed(2));
          break;
        }
        case 'ult': {
          const c = Ease.outExpo(after(T, 0, 0.42));
          const ex = o2 < 1 ? 1 - o2 : 0;
          put(L.cut, 'transform', `translateX(${(dir * (110 * (1 - c) - 25 * Ease.inCubic(ex))).toFixed(2)}%)`);
          if (L.art) put(L.art, 'transform', `translateX(${(dir * k * (90 - 60 * T)).toFixed(1)}px)`);
          impact(T, 0.14);
          const m = after(T, 0.1, 0.36);
          put(L.main, 'transform', `translateX(${(dir * 70 * k * (1 - Ease.outCubic(m))).toFixed(1)}px) scale(${(1.18 - 0.18 * Ease.outCubic(m)).toFixed(3)})`);
          put(L.main, 'opacity', Math.min(1, m * 1.8).toFixed(3));
          const kk = after(T, 0.04, 0.3);
          put(L.kick, 'opacity', kk.toFixed(3));
          put(L.kick, 'transform', `translateX(${(dir * 40 * k * (1 - Ease.outCubic(kk))).toFixed(1)}px)`);
          const sb = after(T, 0.22, 0.3);
          put(L.sub, 'opacity', sb.toFixed(3));
          put(L.sub, 'transform', `translateX(${(dir * 30 * k * (1 - Ease.outCubic(sb))).toFixed(1)}px)`);
          break;
        }
        default: {
          // timeup / draw / banner / win: the line drops in and lands
          const d = Ease.outBack(a);
          put(L.main, 'transform', `translateY(${(-34 * k * (1 - d)).toFixed(1)}px) scale(${(1.08 - 0.08 * e).toFixed(4)})`);
          put(L.main, 'opacity', Math.min(1, a * 1.8).toFixed(3));
        }
      }
    };
    anim.add(dur, (kk, t) => frame(t * dur), { ease: 'linear', key: node, done: () => node.remove() });
    return ++annSeq;
  }
  function clearAnnounce(keepUlt) {
    for (const n of Array.from(annLayer.children)) {
      if (keepUlt && n.classList.contains('st-ult')) continue;
      anim.kill(n);
      n.remove();
    }
  }

  // ---------------------------------------------------------------------------------------------------------------
  // hints

  function renderHints() {
    const dev = ui.device;
    const K = (a) => {
      const k = ui.keyLabel(a, 0);
      return k ? `<span class="keycap${dev === 'gamepad' ? ' pad' : ''}">${esc(k)}</span>` : '';
    };
    const item = (keys, ko, en) => `<span class="hint">${keys}<b>${ko}</b><em>${en}</em></span>`;
    hints.innerHTML = [
      item(K('left') + K('right'), '이동', 'MOVE'),
      item(K('light'), '약공', 'LIGHT'),
      item(K('heavy'), '강공', 'HEAVY'),
      item(K('skill1') + K('skill2') + K('skill3'), '스킬', 'SKILLS'),
      item(K('ult'), '궁극기', 'ULT'),
      item(K('guard'), '막기', 'GUARD'),
      item(K('dodge'), '회피', 'DODGE'),
      item(K('pause'), '일시정지', 'PAUSE'),
    ].join('');
  }

  // ---------------------------------------------------------------------------------------------------------------

  const hud = {
    el: root,
    /** Static info once per match: hud.setup({ p1: fighter, p2: fighter, roundsToWin }). Fighter = roster entry. */
    setup(o = {}) {
      if (o.roundsToWin && o.roundsToWin !== roundsMax) { roundsMax = o.roundsToWin; buildPips(); }
      setIdentity(S[0], o.p1);
      setIdentity(S[1], o.p2);
      for (const sd of S) { sd.hpR = -1; sd.ultR = -1; sd.fpR = -1; sd.ghostR = 1; }
      if (o.p1 && o.p1.moves) hud.skills(0, skillsOf(o.p1));
      if (o.p2 && o.p2.moves) hud.skills(1, skillsOf(o.p2));
      // the first real update decides readiness without a "just became ready" burst
      for (const sd of S) for (const sl of sd.slots) { sl.ready = null; putClass(sl.el, 'is-ready', false); }
      refreshKeys();
    },
    /** Every frame: { time, roundsToWin?, p1: { name, hp, hpMax, fp, fpMax, ult, ultMax?, rounds, element, title? }, p2 } */
    set(o) {
      if (!o) return;
      if (o.roundsToWin && o.roundsToWin !== roundsMax) { roundsMax = o.roundsToWin; buildPips(); }
      setTime(o.time);
      for (let i = 0; i < 2; i++) {
        const d = i ? o.p2 : o.p1;
        if (!d) continue;
        const sd = S[i];
        if (d.element !== undefined) setElement(sd, d.element);
        if (d.name !== undefined && d.name !== sd._nm) {
          sd._nm = d.name;
          // a name that setup() already shows (English or Korean) keeps the two-line lockup
          if (d.name !== sd.name.textContent && d.name !== sd.nameKo.textContent) { putText(sd.name, d.name); putText(sd.nameKo, ''); }
        }
        if (d.title !== undefined) putText(sd.title, d.title);
        if (d.hp !== undefined) setHp(sd, d.hp, d.hpMax || sd.hpMax);
        if (d.hpMax) sd.hpMax = d.hpMax;
        if (d.fp !== undefined) setFp(sd, d.fp, d.fpMax || sd.fpMax);
        if (d.fpMax) sd.fpMax = d.fpMax;
        if (d.ult !== undefined) setUlt(sd, d.ult, d.ultMax || 100);
        if (d.rounds !== undefined) setRounds(sd, d.rounds);
      }
    },
    /** Skill slots: hud.skills(side, [{ id, name, key, cd: 0..1, ready, cost, icon }]). Cheap when unchanged. */
    skills: setSkills,
    /** Combo counter for the attacking side: hud.combo(side, hits, damage). hits < 2 hides it. */
    combo: setCombo,
    /**
     * Announcer. text = free text or a preset key ('round', 'final', 'fight', 'ko', 'perfect', 'timeup', 'draw';
     * 'ROUND 2', 'K.O.', 'TIME UP' ... are recognised too). opts: { sub, style, duration, round, side, element, keep, kicker }.
     * style: 'round' | 'fight' | 'ko' | 'perfect' | 'timeup' | 'banner' | 'ult' | 'win'.
     */
    announce,
    clearAnnounce: () => clearAnnounce(false),
    /** Slide the HUD away for a cinematic (true) and back (false). */
    cinematic(on) {
      cineTarget = on ? 1 : 0;
      root.classList.toggle('is-cine', !!on);
      ui.emit('hud:cinematic', !!on);
    },
    get cine() { return cine; },
    /** Show / hide the control hints strip (keyboard / gamepad labels follow the last device). */
    hints(on = true) {
      hintsOn = !!on;
      if (hintsOn) renderHints();
      root.classList.toggle('show-hints', hintsOn);
    },
    /** Reset transient state between rounds (combo, ghosts, announcements). */
    reset() {
      for (const sd of S) {
        sd.ghostR = sd.hpR; sd.ghostWait = 0; put(sd.ghost, 'transform', `scaleX(${Math.max(0, sd.hpR).toFixed(4)})`);
        sd.comboHits = 0; if (sd.comboShown) fadeCombo(sd);
      }
      clearAnnounce(false);
    },
    refreshDevice() {
      if (hintsOn) renderHints();
      refreshKeys();
    },
    /** Layout hook from the UI: in portrait-with-pad the bars move under the stage and the FP / ULT meters form a deck row. */
    setLayout({ portrait }) {
      if (portrait) { top.appendChild(deck); for (const sd of S) deck.appendChild(sd.mini); } else { deck.remove(); for (const sd of S) sd.under.appendChild(sd.mini); }
    },
    /** Bottom edge (CSS px from the top of #ui) of the top bar block, ignoring the cinematic slide; in portrait the
     *  touch pad starts below it. */
    topBottom: () => root.offsetTop + top.offsetTop + top.offsetHeight,
    /** The ULT icon name of a side (from setup). */
    ultIcon: (side) => S[side].ultIcon || 'ult',

    update(dt) {
      clock += dt;
      // cinematic slide (transform / opacity on three containers)
      if (cine !== cineTarget) {
        const step = dt / 0.38;
        cine = cineTarget > cine ? Math.min(cineTarget, cine + step) : Math.max(cineTarget, cine - step);
        const e = Ease.inOutCubic(cine);
        put(top, 'transform', e ? `translateY(${(-130 * e).toFixed(1)}%)` : '');
        put(top, 'opacity', (1 - e).toFixed(3));
        for (const sd of S) {
          put(sd.dock, 'transform', e ? `translateY(${(140 * e).toFixed(1)}%)` : '');
          put(sd.dock, 'opacity', (1 - e).toFixed(3));
        }
        put(hints, 'opacity', (1 - e).toFixed(3));
        put(pauseBtn, 'opacity', (1 - e).toFixed(3));
      }
      // the timer's corona turns slowly; under 10 s it burns red and quickens
      put(tmRays, 'transform', `rotate(${((clock * (timeLow ? 14 : 3)) % 360).toFixed(1)}deg)`);
      for (const sd of S) {
        // ghost bar: hold, then drain with a quick ease
        if (sd.ghostR > sd.hpR) {
          if (sd.ghostWait > 0) sd.ghostWait -= dt;
          else {
            sd.ghostR = Math.max(sd.hpR, sd.ghostR - Math.max(0.18, (sd.ghostR - sd.hpR) * 3.2) * dt);
            put(sd.ghost, 'transform', `scaleX(${sd.ghostR.toFixed(4)})`);
          }
        }
        // hit jolt
        if (sd.shake > 0) {
          sd.shake = Math.max(0, sd.shake - dt);
          const a = sd.shakeAmp * (sd.shake / 0.22) * 5;
          const x = Math.sin(clock * 90 + sd.i) * a, y = Math.cos(clock * 77) * a * 0.4;
          put(sd.hp, 'transform', sd.shake > 0 ? `translate(${x.toFixed(1)}px,${y.toFixed(1)}px)` : '');
        }
        // ULT ignited: breathing glow and aura, turning corona (deterministic: driven by real time)
        if (sd.ultFull) {
          const b = 0.5 + 0.5 * Math.sin(clock * 4.6 + sd.i * 1.3);
          put(sd.orbGlow, 'opacity', Math.min(1, (0.55 + 0.35 * b) * sd.glowK).toFixed(3));
          put(sd.orbAura, 'opacity', Math.min(1, (0.45 + 0.3 * b) * sd.glowK).toFixed(3));
          put(sd.orbRays, 'transform', `rotate(${((clock * 20) % 360).toFixed(1)}deg) scale(${sd.raysS.toFixed(3)})`);
        }
        // combo auto-fade
        if (sd.comboShown) {
          sd.comboAge += dt;
          if (sd.comboAge > 2.6) fadeCombo(sd);
        }
        // low-health throb (on the fill only)
        if (sd.low) put(sd.sheen, 'opacity', (0.5 + 0.5 * Math.sin(clock * 9)).toFixed(2));
        // ready pulse on skill slots
        for (const sl of sd.slots) if (sl.ready) put(sl.glow, 'opacity', (0.45 + 0.4 * Math.sin(clock * 4.2 + sl.el._phase0)).toFixed(2));
      }
    },
  };

  /** Build hud.skills() data from a roster entry (no cooldown). */
  function skillsOf(f) {
    return [1, 2, 3].map((n) => {
      const m = f.moves.find((x) => x.slot === 'skill' + n) || {};
      return { id: m.icon || 'skill' + n, name: m.name, cost: m.cost || 0, cd: 0, icon: m.icon };
    });
  }
  hud.skillsOf = skillsOf;

  return hud;
}
