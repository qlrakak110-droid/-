// In-fight HUD in the ink-wash idiom: 기혈 (HP) as brushed ink bands with a delayed-damage ghost and an element-lit
// leading edge, the round timer as an eclipse dial over a burning incense stick, won rounds as small seals, 내공 /
// 오의 meters (the 오의 orb ignites as an event), skill slots with cooldown sweeps, combo counters, the announcer
// (brush-written cards with seals) and cinematic mode. Every per-frame write is cached: a DOM property is only
// touched when its value changes, and bars / sweeps move through transforms (no layout).

import { h, esc } from './anim.js';
import { icon, corona, eclipseMark, weaponArt } from './icons.js';
import { seal, divider, splash, inkEclipse } from './ink.js';
import { brushText } from './brush.js';
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

// the timer dial: the ink black sun (brushed ring, no streamers); the numerals sit in its disc
const TIMER_DISC = inkEclipse({ streamers: false, seed: 6 });
// brush fills of the 오의 banner per element: [top, bottom]
const BRUSH_FILL = { ember: ['#fff7ea', '#ffb27c'], frost: ['#ffffff', '#a8dcff'], volt: ['#ffffff', '#cdb2ff'] };
const HANJA_NUM = ['零', '一', '二', '三', '四', '五', '六', '七', '八', '九'];

// ---------------------------------------------------------------------------------------------------------------
// announcer presets (Korean main line, short English sub)

// Korean first (written with the brush), Hanja as the accent (carved on the seal), a short English sub
const PRESETS = {
  round: (o) => { const n = o.round || 1; return { text: `제 ${n} 합`, seal: `第${HANJA_NUM[n] || n}合`, sub: `ROUND ${n}`, style: 'round' }; },
  final: () => ({ text: '마지막 합', seal: '決勝', sub: 'FINAL ROUND', style: 'round', final: true }),
  fight: () => ({ text: '겨뤄라!', seal: '比武', sub: 'FIGHT', style: 'fight' }),
  ko: () => ({ text: '결', seal: '決', sub: 'K.O.', style: 'ko' }),
  perfect: () => ({ text: '무결', seal: '無缺', sub: 'PERFECT', style: 'perfect' }),
  timeup: () => ({ text: '향이 다 탔다', seal: '香盡', sub: 'TIME UP', style: 'timeup' }),
  draw: () => ({ text: '무승부', seal: '和', sub: 'DRAW', style: 'timeup' }),
  win: (o) => ({ text: '승', seal: '勝', sub: o.sub || 'VICTORY', style: 'verdict' }),
  lose: (o) => ({ text: '패', seal: '敗', sub: o.sub || 'DEFEAT', style: 'verdict', lose: true }),
};
const DURATION = { round: 1.6, fight: 1.0, ko: 2.3, perfect: 2.1, timeup: 1.8, banner: 1.6, ult: 1.7, win: 2.4, verdict: 2.4 };
const IN_T = { round: 0.34, fight: 0.16, ko: 0.16, perfect: 0.3, timeup: 0.4, banner: 0.3, ult: 0.3, win: 0.34, verdict: 0.18 };
// brush height of the main line per style (design px, x --k)
const MAIN_H = { round: 92, fight: 168, ko: 236, perfect: 160, timeup: 100, banner: 84, win: 124, verdict: 220 };
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
  const tmRays = h('div.tm-rays', { html: corona({ n: 48, r0: 38, len: 9, w: 1.1 }) });
  const tmNum = h('b.tm-num', { text: '99' });
  // the incense stick under the dial: the unburnt part shrinks toward the right, the ember rides its end
  const tmStick = h('i.tm-stick');
  const tmEmber = h('i.tm-ember', null, h('i.tm-smoke'));
  const tmIncense = h('div.tm-incense', null, h('i.tm-ash'), tmStick, tmEmber);
  const tm = h('div.hud-timer', null, h('i.tm-glow'), tmRays, h('div.tm-disc', { html: TIMER_DISC }), tmNum, tmIncense);
  const annLayer = h('div.hud-ann');
  const hints = h('div.hud-hints');
  const pauseBtn = h('button.hud-pause', { type: 'button', 'aria-label': '숨 고르기 Pause', html: icon('pause') });
  pauseBtn.addEventListener('pointerdown', (e) => { e.preventDefault(); e.stopPropagation(); });
  pauseBtn.addEventListener('click', (e) => { e.stopPropagation(); ui.emit('pause'); });

  const S = [0, 1].map(makeSide);
  const deck = h('div.hud-deck');
  top.append(S[0].plate, tm, S[1].plate);
  // the announcer paints last: a card covers the pause button for its second or two (taps still reach it)
  root.append(top, S[0].dock, S[1].dock, S[0].combo, S[1].combo, hints, pauseBtn, annLayer);

  let roundsMax = 2;
  let timeShown = null, timeLow = false, timeMax = 0, burnR = -1;
  let cine = 0, cineTarget = 0;
  let clock = 0;
  let hintsOn = false;

  function makeSide(i) {
    const s = SIDES[i];
    const name = h('span.hud-name');                 // the hero's name, written with the brush
    const nameKo = h('span.hud-name-ko');            // its Hanja
    const title = h('span.hud-title');               // 별호 · 문파
    const emblem = h('i.hud-emb');
    const id = h('div.hud-id', null, emblem, name, nameKo, title);
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
    const miniUltLabel = h('span.mini-ult-label', { text: '奧義' });
    const mini = h(`div.hud-mini.${s}`, null, h('div.mini-fp', null, h('b', { text: '내공' }), h('div.mini-bar', null, miniFp)), h('div.mini-ult', null, h('b', { text: '오의' }), h('div.mini-bar', null, miniUlt), miniUltLabel));
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
    const orbLabel = h('div.orb-label', { html: `<b>${brushText('오의', { weight: 1.3, gap: 4 })}</b><i class="orb-seal">${seal('奧義', { seed: 19 })}</i><span>READY</span>` });
    const skills = h('div.dock-skills');
    const fpFill = h('i.fp-fill');
    const fpNum = h('span.fp-val', { text: '0' });
    const fp = h('div.dock-fp', null, h('span.fp-label', { html: '내공<i class="hj">內功</i>' }), h('div.fp-bar', null, fpFill, h('i.fp-ticks')), fpNum);
    const dock = h(`div.hud-dock.${s}`, null, orb, h('div.dock-main', null, orbLabel, skills, fp));

    // combo
    const cbNum = h('b.cb-num', { text: '0' });
    const cbHot = h('b.cb-num.cb-hot', { text: '0' });
    const cbDmg = h('b', { text: '0' });
    const cbInner = h('div.cb-inner', null,
      h('div.cb-row', null, h('div.cb-nums', null, cbNum, cbHot), h('div.cb-hits', { html: '<span>연환</span><em>HITS</em>' })),
      h('div.cb-dmg', null, h('span', { text: '피해' }), cbDmg, h('em', { text: 'DMG' })),
      h('i.cb-line'));
    const combo = h(`div.hud-combo.${s}`, null, cbInner);
    combo.style.opacity = '0';

    return {
      i, s, plate, dock, combo, mini, under, name, nameKo, title, emblem, hp, track, fill, fillHot, ghost, ghostHot, sheen, edge, pips, miniFp, miniUlt,
      ring, orb, orbAura, orbGlow, orbRays, orbCore, orbFlash, orbBurst, orbBurst2, orbFlare, orbKey, orbLabel, skills, fpFill, fpNum,
      cbNum, cbHot, cbDmg, cbInner,
      slots: [],
      // state
      hpR: 1, ghostR: 1, ghostWait: 0, hpMax: 1000, fpR: 0, fpVal: 0, fpMax: 100, ultR: 0, ultFull: false, raysS: 1, glowK: 1,
      rounds: -1, element: null, weapon: null, fighter: null, nameStr: '', low: false, shake: 0, shakeAmp: 0,
      comboHits: 0, comboAge: 99, comboShown: false,
    };
  }

  function buildPips() {
    for (const sd of S) {
      sd.pips.innerHTML = '';
      for (let k = 0; k < roundsMax; k++) sd.pips.appendChild(h('i.pip', { html: seal('勝', { seed: 23 + k }) }));
      sd.rounds = -1;
    }
  }
  buildPips();

  // ---------------------------------------------------------------------------------------------------------------
  // static info

  /** The name plate: brush-written name, Hanja, 별호 · 문파 and the sect emblem. */
  function setName(sd, name, hanja) {
    if (name === sd.nameStr && sd.name.childElementCount) return;
    sd.nameStr = name;
    sd.name.innerHTML = name ? brushText(name, { weight: 1.3, gap: 4 }) : '';
    putText(sd.nameKo, hanja || '');
  }
  function setIdentity(sd, f) {
    if (!f) return;
    sd.fighter = f;
    setName(sd, f.name || f.nameEn || '', f.hanja || '');
    putText(sd.title, [f.title, f.sect].filter(Boolean).join(' · '));
    sd.emblem.innerHTML = icon(f.emblem || f.element || '') || '';
    if (f.element) setElement(sd, f.element);
    sd.weapon = f.weaponArt || null;
    const u = (f.moves || []).find((m) => m.slot === 'ult');
    sd.ult = u || null;
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
        anim.add(0.42, (e) => put(p, 'transform', e < 1 ? `scale(${(2.2 - 1.2 * e).toFixed(3)}) rotate(${(-12 * (1 - e)).toFixed(1)}deg)` : ''), { key: p, ease: 'outQuart' });
      }
      putClass(pips[k], 'on', on);
    }
    sd.rounds = n;
  }

  /** The incense stick: `r` = fraction left. The stick shrinks toward its foot, the ember rides the burning end. */
  function setBurn(r) {
    const q = Math.round(clamp(r) * 400) / 400;
    if (q === burnR) return;
    burnR = q;
    put(tmStick, 'transform', `scaleX(${q.toFixed(4)})`);
    put(tmEmber, 'transform', `translateX(${(-100 * q).toFixed(2)}%)`);
  }

  function setTime(t) {
    if (t === undefined) return;
    if (t === null || !isFinite(t)) setBurn(1);
    else { if (t > timeMax) timeMax = t; setBurn(timeMax > 0 ? t / timeMax : 1); }
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
  // announcer: one card per call, built from layers (ink band, splash, eclipse, the brush-written line, its seal, a
  // dry-brush rule, the English sub ...) and driven by a single tween (entrance, hold, exit). Every layer moves by
  // transform / opacity.

  let annSeq = 0;
  const brushMain = (text, fill, cls = '') => h('div.an-main' + cls, { html: brushText(text, { weight: 1.15, gap: 5, fill }) });

  function announce(text, o = {}) {
    const p = presetOf(text);
    let spec;
    if (p) spec = { ...PRESETS[p[0]]({ ...p[1], ...o }), ...(o.sub !== undefined ? { sub: o.sub } : null), ...(o.style ? { style: o.style } : null) };
    else spec = { text: String(text || ''), sub: o.sub || '', style: o.style || 'banner', seal: o.style === 'win' ? '勝' : '' };
    if (o.seal !== undefined) spec.seal = o.seal;
    const style = DURATION[spec.style] ? spec.style : 'banner';
    const dur = o.duration || DURATION[style];
    const side = o.side === 1 ? 1 : o.side === 0 ? 0 : -1;
    const sd = side >= 0 ? S[side] : null;
    const elem = o.element || (sd && sd.element) || '';
    if (!o.keep) clearAnnounce(style === 'ult');

    const node = h(`div.ann.st-${style}` + (elem ? `.el-${elem}` : '') + (side >= 0 ? `.side-${SIDES[side]}` : '') + (spec.final ? '.is-final' : '') + (spec.lose ? '.is-lose' : ''));
    const fit = h('div.an-fit');
    node.appendChild(fit);
    node.style.setProperty('--mh', String(MAIN_H[style] || 84));
    const L = {};
    const add = (k, el) => { L[k] = el; fit.appendChild(el); return el; };

    if (style === 'ult') {
      // 오의: a hanging banner on the user's side of the screen (the hero shot in the middle stays clear). The name is
      // written down it glyph by glyph, the Hanja runs beside it, the hero's seal closes it. With a `side` the banner
      // shows that fighter's own 오의 from the roster; `text` / `sub` / `o.hanja` are for a custom banner.
      const f = sd && sd.fighter, u = sd && sd.ult;
      const custom = o.hanja !== undefined || !u;
      const name = custom ? spec.text : u.name, hanja = custom ? o.hanja || '' : u.hanja || '', gloss = custom ? spec.sub : u.nameEn || spec.sub;
      const fill = BRUSH_FILL[elem] || ['#ffffff', '#e9dcc0'];
      const scroll = add('scroll', h('div.an-scroll'));
      L.bg = scroll.appendChild(h('i.an-scroll-bg'));
      L.edge = scroll.appendChild(h('i.an-scroll-edge'));
      if (sd && sd.weapon) L.art = scroll.appendChild(h('div.an-art', { html: weaponArt(sd.weapon) }));
      const kicker = o.kicker !== undefined ? o.kicker : '오의';
      L.kick = scroll.appendChild(h('div.an-kick', null, h('b', { text: kicker }), o.kicker === undefined ? h('i.hj', { text: '奧義' }) : null, f ? h('span', { text: f.name }) : null));
      const col = scroll.appendChild(h('div.an-glyphs'));
      const chars = Array.from(name).filter((c) => c.trim());
      col.style.setProperty('--n', String(Math.max(4, chars.length)));
      L.glyphs = chars.map((c, i) => col.appendChild(h('div.an-glyph', { html: brushText(c, { weight: 1.2, fill, seed: i }) })));
      L.hanja = scroll.appendChild(h('span.an-hanja', { text: hanja }));
      if (f && f.seal) L.seal = scroll.appendChild(h('i.an-seal', { html: seal(f.seal, { seed: 5 }) }));
      L.sub = scroll.appendChild(h('div.an-sub', { text: gloss || '' }));
      node.setAttribute('aria-label', `${name} ${hanja}`);
    } else {
      const slam = style === 'fight' || style === 'ko' || style === 'verdict';
      add('band', h('i.an-band'));
      if (slam || style === 'perfect') add('blot', h('i.an-blot', { html: splash({ seed: style === 'ko' ? 27 : 21 }) }));
      if (style === 'round' || style === 'perfect') add('emblem', h('div.an-emblem', { html: eclipseMark() }));
      if (slam || style === 'round' || style === 'perfect') { add('ring', h('i.an-ring')); add('flare', h('i.an-flare')); }
      const fill = style === 'ko' || spec.lose ? ['#fff3ee', '#f2a392'] : style === 'timeup' ? ['#ffffff', '#c6d0e2'] : style === 'perfect' ? ['#fffdf2', '#ecd28e'] : ['#fffaf0', '#dfd3b8'];
      const row = add('row', h('div.an-row'));
      if (style === 'fight' || style === 'ko') L.echo = fit.appendChild(h('div.an-row.an-echo-row', null, brushMain(spec.text, fill, '.an-echo')));
      if (style === 'ko') {
        // two copies of the mark clipped above / below the cut line; they slide apart along it
        L.split = row.appendChild(h('div.an-split'));
        L.top = L.split.appendChild(h('div.an-half.top', null, brushMain(spec.text, fill)));
        L.bot = L.split.appendChild(h('div.an-half.bot', null, brushMain(spec.text, fill)));
        L.slash = L.split.appendChild(h('i.an-slash'));
      } else L.main = row.appendChild(brushMain(spec.text, fill));
      if (spec.seal) L.seal = row.appendChild(h('i.an-seal', { html: seal(spec.seal, { seed: 7 }) }));
      if (style === 'perfect') add('shine', h('i.an-shine'));
      add('rule', h('i.an-rule', { html: divider({ seed: 9 }) }));
      add('sub', h('div.an-sub', { text: spec.sub || '' }));
      node.setAttribute('aria-label', spec.text);
    }
    if (!spec.sub && style !== 'ult') L.sub.style.display = 'none';
    annLayer.appendChild(node);

    const inT = IN_T[style];
    const outT = style === 'fight' ? 0.24 : 0.4;
    const k = ui.k || 1;
    const after = (T, t0, d) => clamp((T - t0) / d);
    // shared impact layers: an ink ring thrown outward and a thin flare
    const impact = (T, t0, ringMax = 2.6) => {
      if (L.ring) {
        const r = after(T, t0, 0.6);
        put(L.ring, 'transform', `scale(${(0.25 + ringMax * Ease.outQuart(r)).toFixed(3)})`);
        put(L.ring, 'opacity', (T < t0 ? 0 : 0.85 * (1 - r)).toFixed(3));
      }
      if (L.flare) {
        put(L.flare, 'transform', `scaleX(${Ease.outExpo(after(T, t0 - 0.04, 0.3)).toFixed(3)})`);
        put(L.flare, 'opacity', (T < t0 - 0.04 ? 0 : 1 - after(T, t0 + 0.12, 0.6)).toFixed(3));
      }
      if (L.blot) {
        const b = after(T, t0 - 0.03, 0.3);
        put(L.blot, 'transform', `scale(${(0.3 + 0.7 * Ease.outQuart(b)).toFixed(3)})`);
        put(L.blot, 'opacity', (T < t0 - 0.03 ? 0 : Math.min(1, b * 4)).toFixed(3));
      }
    };
    // the seal is pressed on after the line has landed
    const stamp = (el, T, t0) => {
      const m = after(T, t0, 0.24);
      put(el, 'opacity', (T < t0 ? 0 : Math.min(1, m * 3)).toFixed(3));
      put(el, 'transform', m < 1 ? `scale(${(1.9 - 0.9 * Ease.outQuart(m)).toFixed(3)}) rotate(${(-11 + 7 * m).toFixed(2)}deg)` : 'rotate(-4deg)');
    };
    const sealAt = { round: 0.5, fight: inT + 0.1, ko: inT + 0.4, perfect: 0.55, verdict: inT + 0.3 }[style] || inT + 0.18;
    const frame = (T) => {
      const a = clamp(T / inT), e = Ease.outCubic(a);
      const o2 = clamp((dur - T) / outT);
      put(node, 'opacity', (o2 < 1 ? Ease.inQuad(o2) : 1).toFixed(3));
      // the ink band is dragged across like one stroke of a loaded brush
      if (L.band) put(L.band, 'transform', `scaleX(${Ease.outExpo(after(T, 0, style === 'ko' ? 0.2 : 0.34)).toFixed(3)})`);
      if (L.rule) put(L.rule, 'transform', `scaleX(${Ease.outExpo(after(T, 0.14, 0.6)).toFixed(3)})`);
      if (L.seal && style !== 'ult') stamp(L.seal, T, sealAt);
      if (L.sub && style !== 'ult') {
        const s = after(T, style === 'ko' ? 0.42 : 0.22, 0.32);
        put(L.sub, 'opacity', s.toFixed(3));
        put(L.sub, 'transform', `translateY(${(10 * (1 - Ease.outCubic(s))).toFixed(1)}px)`);
      }
      switch (style) {
        case 'round': {
          const em = after(T, 0, 0.7);
          put(L.emblem, 'transform', `rotate(${(-24 + 24 * Ease.outCubic(em) + T * 5).toFixed(2)}deg) scale(${(0.55 + 0.45 * Ease.outBack(em)).toFixed(3)})`);
          put(L.emblem, 'opacity', Math.min(1, T / 0.22).toFixed(3));
          impact(T, 0.22, 2.2);
          const m = after(T, 0.14, 0.32);
          put(L.main, 'opacity', Math.min(1, m * 1.8).toFixed(3));
          put(L.main, 'transform', m < 1 ? `translateY(${(16 * k * (1 - Ease.outCubic(m))).toFixed(1)}px) scale(${(1.22 - 0.22 * Ease.outQuart(m)).toFixed(3)})` : '');
          break;
        }
        case 'fight':
        case 'verdict': {
          const s = 2.6 - 1.6 * Ease.outQuart(a);
          const j = T > inT && T < inT + 0.16 ? Math.sin((T - inT) * 110) * 5 * k * (1 - (T - inT) / 0.16) : 0;
          put(L.main, 'transform', `translate(${j.toFixed(1)}px,0) scale(${(s * (o2 < 1 && style === 'fight' ? 1 + (1 - o2) * 0.2 : 1)).toFixed(3)})`);
          put(L.main, 'opacity', Math.min(1, a * 2.2).toFixed(3));
          if (L.echo) {
            const ec = after(T, inT, 0.32);
            put(L.echo, 'transform', `scale(${(1 + 0.32 * Ease.outCubic(ec)).toFixed(3)})`);
            put(L.echo, 'opacity', (T < inT ? 0 : 0.4 * (1 - Ease.outQuad(ec))).toFixed(3));
          }
          impact(T, inT, 3.2);
          break;
        }
        case 'ko': {
          const s = 3 - 2 * Ease.outQuart(a);
          const j = T > inT && T < inT + 0.2 ? Math.sin((T - inT) * 120) * 7 * k * (1 - (T - inT) / 0.2) : 0;
          put(L.split, 'transform', `translate(${j.toFixed(1)}px,0) scale(${s.toFixed(3)})`);
          put(L.split, 'opacity', Math.min(1, a * 2).toFixed(3));
          // the cut: the slash draws across, then the halves part along it and stay parted
          const c = after(T, inT + 0.1, 0.2);
          put(L.slash, 'transform', `rotate(${-KO_DEG}deg) scaleX(${Ease.outExpo(c).toFixed(3)})`);
          put(L.slash, 'opacity', (T < inT + 0.1 ? 0 : 1 - 0.55 * after(T, inT + 0.45, 0.6)).toFixed(3));
          const d = 20 * k * Ease.outExpo(after(T, inT + 0.16, 0.35));
          put(L.top, 'transform', `translate(${(-d * KO_COS).toFixed(1)}px,${(d * KO_SIN - d * 0.4).toFixed(1)}px)`);
          put(L.bot, 'transform', `translate(${(d * KO_COS).toFixed(1)}px,${(-d * KO_SIN + d * 0.4).toFixed(1)}px)`);
          const ec = after(T, inT, 0.45);
          put(L.echo, 'transform', `scale(${(1 + 0.55 * Ease.outCubic(ec)).toFixed(3)})`);
          put(L.echo, 'opacity', (T < inT ? 0 : 0.4 * (1 - Ease.outQuad(ec))).toFixed(3));
          impact(T, inT, 3.4);
          break;
        }
        case 'perfect': {
          const em = after(T, 0, 0.9);
          put(L.emblem, 'transform', `rotate(${(T * 5).toFixed(2)}deg) scale(${(0.7 + 0.3 * Ease.outCubic(em)).toFixed(3)})`);
          put(L.emblem, 'opacity', (0.6 * Math.min(1, T / 0.3)).toFixed(3));
          put(L.main, 'transform', a < 1 ? `scale(${(1.3 - 0.3 * e).toFixed(4)})` : '');
          put(L.main, 'opacity', e.toFixed(3));
          impact(T, 0.2, 2.6);
          const sh = after(T, 0.34, 0.75);
          put(L.shine, 'transform', `translateX(${(-300 + 600 * Ease.inOutCubic(sh)).toFixed(1)}%) skewX(-20deg)`);
          put(L.shine, 'opacity', (sh > 0 && sh < 1 ? 1 : 0).toFixed(2));
          break;
        }
        case 'ult': {
          const ex = o2 < 1 ? 1 - o2 : 0;
          put(L.bg, 'transform', `scaleY(${Ease.outExpo(after(T, 0, 0.36)).toFixed(3)})`);
          put(L.edge, 'transform', `scaleY(${Ease.outExpo(after(T, 0.06, 0.5)).toFixed(3)})`);
          put(L.scroll, 'transform', ex ? `translateY(${(-22 * k * Ease.inCubic(ex)).toFixed(1)}px)` : '');
          if (L.art) {
            put(L.art, 'opacity', (0.55 * after(T, 0.1, 0.4)).toFixed(3));
            put(L.art, 'transform', `translateY(${(k * (24 - 18 * T)).toFixed(1)}px)`);
          }
          const kk = after(T, 0.04, 0.26);
          put(L.kick, 'opacity', kk.toFixed(3));
          put(L.kick, 'transform', kk < 1 ? `translateY(${(-12 * k * (1 - Ease.outCubic(kk))).toFixed(1)}px)` : '');
          for (let i = 0; i < L.glyphs.length; i++) {
            const m = after(T, 0.12 + i * 0.075, 0.2);
            put(L.glyphs[i], 'opacity', Math.min(1, m * 2.4).toFixed(3));
            put(L.glyphs[i], 'transform', m < 1 ? `scale(${(1.9 - 0.9 * Ease.outQuart(m)).toFixed(3)})` : '');
          }
          put(L.hanja, 'opacity', after(T, 0.32, 0.35).toFixed(3));
          if (L.seal) stamp(L.seal, T, 0.22 + L.glyphs.length * 0.075);
          put(L.sub, 'opacity', after(T, 0.42, 0.3).toFixed(3));
          break;
        }
        default: {
          // timeup / draw / banner / win: the line drops in and lands
          const d = Ease.outBack(a);
          put(L.main, 'transform', a < 1 ? `translateY(${(-34 * k * (1 - d)).toFixed(1)}px) scale(${(1.08 - 0.08 * e).toFixed(4)})` : '');
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
      item(K('light'), '경초', 'LIGHT'),
      item(K('heavy'), '중초', 'HEAVY'),
      item(K('skill1') + K('skill2') + K('skill3'), '절기', 'SKILLS'),
      item(K('ult'), '오의', 'ULT'),
      item(K('guard'), '호신', 'GUARD'),
      item(K('dodge'), '경공', 'DODGE'),
      item(K('pause'), '숨 고르기', 'PAUSE'),
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
      timeMax = 0;
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
          // a name that setup() already shows (Korean, Hanja or romanised) keeps the plate as it is
          const f = sd.fighter;
          if (!(f && (d.name === f.name || d.name === f.hanja || d.name === f.nameEn))) setName(sd, d.name, '');
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
     * Announcer. text = free text or a preset key ('round', 'final', 'fight', 'ko', 'perfect', 'timeup', 'draw', 'win',
     * 'lose'; 'ROUND 2', 'K.O.', 'TIME UP' ... are recognised too). opts: { sub, style, duration, round, side, element,
     * keep, kicker, seal, hanja }. style: 'round' | 'fight' | 'ko' | 'perfect' | 'timeup' | 'banner' | 'ult' | 'win'.
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
