// In-fight HUD: health bars with a delayed-damage ghost, centre timer, round pips, FP / ULT meters, skill slots with
// cooldown sweeps, combo counters, announcer and cinematic mode. Every per-frame write is cached: a DOM property is
// only touched when its value changes, and bars / sweeps move through transforms (no layout).

import { h, esc } from './anim.js';
import { icon } from './icons.js';
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

const TIMER_FRAME = `<svg class="tm-frame" viewBox="0 0 120 100" fill="none" aria-hidden="true">
  <path d="M60 3L106 20V80L60 97L14 80V20Z" fill="rgba(6,7,11,.86)" stroke="rgba(216,180,106,.85)" stroke-width="1.4"/>
  <path d="M60 9L100 24V76L60 91L20 76V24Z" stroke="rgba(216,180,106,.35)" stroke-width="1"/>
  <path d="M2 50h10M108 50h10" stroke="rgba(216,180,106,.7)" stroke-width="1.2"/>
  <circle cx="60" cy="3" r="2.6" fill="#f3dca0"/><circle cx="60" cy="97" r="2" fill="rgba(216,180,106,.8)"/>
</svg>`;

// ---------------------------------------------------------------------------------------------------------------
// announcer presets (Korean main line, short English sub)

const PRESETS = {
  round: (o) => ({ text: `${o.round || 1}라운드`, sub: `ROUND ${o.round || 1}`, style: 'round' }),
  final: () => ({ text: '최종 라운드', sub: 'FINAL ROUND', style: 'round' }),
  fight: () => ({ text: '결투', sub: 'FIGHT', style: 'fight' }),
  ko: () => ({ text: 'K.O.', sub: '격 파', style: 'ko' }),
  perfect: () => ({ text: '완벽', sub: 'PERFECT', style: 'perfect' }),
  timeup: () => ({ text: '시간 종료', sub: 'TIME UP', style: 'timeup' }),
  draw: () => ({ text: '무승부', sub: 'DRAW', style: 'timeup' }),
};
const DURATION = { round: 1.5, fight: 0.95, ko: 2.2, perfect: 2.0, timeup: 1.8, banner: 1.6, ult: 1.7, win: 2.4 };

/** Map free text like 'ROUND 2' / 'K.O.' / 'TIME UP' onto a preset key (or null). */
function presetOf(text) {
  const t = String(text || '').trim();
  const low = t.toLowerCase();
  if (PRESETS[low]) return [low, {}];
  let m = /^round\s*(\d+)$/i.exec(t);
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
  const { ctx, anim } = ui;
  const root = h('div.ed-hud');
  const top = h('div.hud-top');
  const tm = h('div.hud-timer', { html: TIMER_FRAME });
  const tmNum = h('b.tm-num', { text: '99' });
  tm.appendChild(tmNum);
  const annLayer = h('div.hud-ann');
  const hints = h('div.hud-hints');
  const pauseBtn = h('button.hud-pause', { type: 'button', 'aria-label': '일시정지 Pause', html: icon('pause') });
  pauseBtn.addEventListener('pointerdown', (e) => { e.preventDefault(); e.stopPropagation(); });
  pauseBtn.addEventListener('click', (e) => { e.stopPropagation(); ui.emit('pause'); });

  const S = [0, 1].map(makeSide);
  const deck = h('div.hud-deck');
  top.append(S[0].plate, tm, S[1].plate);
  root.append(top, deck, S[0].dock, S[1].dock, S[0].combo, S[1].combo, annLayer, hints, pauseBtn);

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
    const fillHot = h('div.hp-fill-hot');
    const fill = h('div.hp-fill', null, fillHot);
    const sheen = h('div.hp-sheen');
    const track = h('div.hp-track', null, ghost, ghostHot, fill, h('div.hp-notch'), sheen);
    const hp = h('div.hud-hp', null, h('div.hp-frame', null, track), h('i.hp-cap'));
    const pips = h('div.hud-pips');
    const miniFp = h('i');
    const miniUlt = h('i');
    const miniUltLabel = h('span.mini-ult-label', { text: '궁극기' });
    const mini = h(`div.hud-mini.${s}`, null, h('div.mini-fp', null, h('b', { text: 'FP' }), h('div.mini-bar', null, miniFp)), h('div.mini-ult', null, h('b', { text: 'ULT' }), h('div.mini-bar', null, miniUlt), miniUltLabel));
    const under = h('div.hud-under', null, pips, mini);
    const plate = h(`div.hud-plate.${s}`, null, id, hp, under);

    // dock: ULT orb + skills + FP bar
    const ring = makePie('orb-ring');
    const orbGlow = h('div.orb-glow');
    const orbRays = h('div.orb-rays', { html: raysSvg() });
    const orbBurst = h('div.orb-burst');
    const orbKey = h('span.keycap.orb-key');
    const orb = h('div.ult-orb', null, orbGlow, orbRays, h('div.orb-base'), ring, h('div.orb-core', { html: icon('ult') }), orbBurst, orbKey);
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
      i, s, plate, dock, combo, mini, under, name, nameKo, title, hp, track, fill, fillHot, ghost, ghostHot, sheen, pips, miniFp, miniUlt,
      ring, orb, orbGlow, orbRays, orbBurst, orbKey, orbLabel, skills, fpFill, fpNum, cbNum, cbHot, cbDmg, cbInner,
      slots: [],
      // state
      hpR: 1, ghostR: 1, ghostWait: 0, hpMax: 1000, hpVal: 1000, fpR: 0, fpVal: 0, fpMax: 100, ultR: 0, ultFull: false,
      rounds: -1, element: null, low: false, shake: 0, shakeAmp: 0,
      comboHits: 0, comboAge: 99, comboShown: false,
    };
  }

  function raysSvg() {
    let d = '';
    for (let k = 0; k < 24; k++) {
      const a = (k / 24) * Math.PI * 2, r0 = 37, r1 = k % 2 ? 44 : 49;
      d += `M${(50 + Math.cos(a) * r0).toFixed(1)} ${(50 + Math.sin(a) * r0).toFixed(1)}L${(50 + Math.cos(a) * r1).toFixed(1)} ${(50 + Math.sin(a) * r1).toFixed(1)}`;
    }
    return `<svg viewBox="0 0 100 100" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><path d="${d}"/></svg>`;
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
      if (full) {
        anim.add(0.7, (k) => {
          put(sd.orbBurst, 'transform', `scale(${(0.7 + k * 1.5).toFixed(3)})`);
          put(sd.orbBurst, 'opacity', (1 - k).toFixed(3));
        }, { key: sd.orbBurst, ease: 'outQuart' });
        anim.add(0.5, (k) => put(sd.orbLabel, 'transform', `translateX(${((sd.i ? 1 : -1) * 18 * (1 - k)).toFixed(1)}px)`), { key: sd.orbLabel, ease: 'outBack' });
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
    let shown;
    if (t === undefined) return;
    if (t === null || !isFinite(t)) shown = '∞';
    else shown = String(Math.max(0, Math.ceil(t - 1e-6)));
    if (shown === timeShown) return;
    timeShown = shown;
    putText(tmNum, shown);
    const low = shown !== '∞' && Number(shown) <= 10;
    putClass(tm, 'is-low', low);
    if (low && timeLow) anim.add(0.4, (k) => put(tmNum, 'transform', `scale(${(1.28 - 0.28 * k).toFixed(3)})`), { key: tmNum, ease: 'outCubic' });
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
    return { el, face, pie, hand, glow, flash, ic, cost, key, id: null, iconName: null, ready: null, cd: -1, costV: -1, noFp: null };
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
  // announcer

  let annSeq = 0;
  function announce(text, o = {}) {
    let p = presetOf(text);
    let spec;
    if (p) spec = { ...PRESETS[p[0]]({ ...p[1], ...o }), ...(o.sub !== undefined ? { sub: o.sub } : null), ...(o.style ? { style: o.style } : null) };
    else spec = { text: String(text || ''), sub: o.sub || '', style: o.style || 'banner' };
    const style = spec.style;
    const dur = o.duration || DURATION[style] || 1.6;
    const side = o.side === 1 ? 1 : o.side === 0 ? 0 : -1;
    const elem = o.element || (side >= 0 && S[side].element) || '';
    const id = ++annSeq;
    if (!o.keep) clearAnnounce(style === 'ult');

    const main = h('div.an-main', null, h('span', { text: spec.text }));
    const echo = h('div.an-main.an-echo', null, h('span', { text: spec.text }));
    const sub = h('div.an-sub', { text: spec.sub || '' });
    const band = h('div.an-band');
    const lineA = h('i.an-line.a');
    const lineB = h('i.an-line.b');
    const slash = h('i.an-slash');
    const shine = h('i.an-shine');
    const node = h(`div.ann.st-${style}` + (elem ? `.el-${elem}` : '') + (side >= 0 ? `.side-${SIDES[side]}` : ''), null, band, lineA, lineB, echo, main, slash, shine, sub);
    if (!spec.sub) sub.style.display = 'none';
    annLayer.appendChild(node);
    node._id = id;

    const inT = { round: 0.32, fight: 0.14, ko: 0.16, perfect: 0.3, timeup: 0.26, banner: 0.28, ult: 0.22, win: 0.3 }[style] || 0.28;
    const outT = style === 'fight' ? 0.22 : 0.38;
    const dir = side === 1 ? 1 : -1;
    // entrance
    anim.add(dur, (k, t) => {
      const T = t * dur;
      const a = clamp(T / inT), e = Ease.outCubic(a), b = Ease.outBack(a);
      const o2 = clamp((dur - T) / outT);
      const fade = o2 < 1 ? Ease.inQuad(o2) : 1;
      switch (style) {
        case 'fight': {
          const s = 2.5 - 1.5 * Ease.outQuart(a);
          put(main, 'transform', `scale(${(s * (o2 < 1 ? 1 + (1 - o2) * 0.18 : 1)).toFixed(3)})`);
          put(main, 'opacity', (Math.min(1, a * 2.2) * fade).toFixed(3));
          put(echo, 'transform', `scale(${(1 + 0.9 * clamp((T - inT) / 0.5)).toFixed(3)})`);
          put(echo, 'opacity', (T < inT ? 0 : 0.55 * (1 - clamp((T - inT) / 0.5))).toFixed(3));
          put(band, 'transform', `scaleY(${e.toFixed(3)})`);
          put(band, 'opacity', fade.toFixed(3));
          put(lineA, 'transform', `scaleX(${Ease.outExpo(clamp((T - 0.05) / 0.35)).toFixed(3)})`);
          put(lineB, 'transform', `scaleX(${Ease.outExpo(clamp((T - 0.08) / 0.35)).toFixed(3)})`);
          put(lineA, 'opacity', fade.toFixed(3)); put(lineB, 'opacity', fade.toFixed(3));
          put(sub, 'opacity', (clamp((T - 0.1) / 0.2) * fade).toFixed(3));
          put(sub, 'transform', `translateY(${(8 * (1 - clamp((T - 0.1) / 0.2))).toFixed(1)}px)`);
          break;
        }
        case 'ko': {
          const s = 3 - 2 * Ease.outQuart(a);
          const jolt = T > inT && T < inT + 0.18 ? Math.sin((T - inT) * 120) * 6 * (1 - (T - inT) / 0.18) : 0;
          put(main, 'transform', `translateX(${jolt.toFixed(1)}px) scale(${s.toFixed(3)})`);
          put(main, 'opacity', (Math.min(1, a * 2) * fade).toFixed(3));
          put(echo, 'transform', `scale(${(1 + 1.4 * clamp((T - inT) / 0.7)).toFixed(3)})`);
          put(echo, 'opacity', (T < inT ? 0 : 0.6 * (1 - clamp((T - inT) / 0.7))).toFixed(3));
          put(band, 'transform', `scaleY(${Ease.outExpo(clamp(T / 0.25)).toFixed(3)})`);
          put(band, 'opacity', fade.toFixed(3));
          put(slash, 'transform', `rotate(-14deg) scaleX(${Ease.outExpo(clamp((T - inT) / 0.22)).toFixed(3)})`);
          put(slash, 'opacity', (T < inT ? 0 : (1 - clamp((T - inT - 0.25) / 0.6) * 0.65) * fade).toFixed(3));
          put(lineA, 'transform', `scaleX(${Ease.outExpo(clamp((T - 0.1) / 0.5)).toFixed(3)})`);
          put(lineB, 'transform', `scaleX(${Ease.outExpo(clamp((T - 0.14) / 0.5)).toFixed(3)})`);
          put(lineA, 'opacity', fade.toFixed(3)); put(lineB, 'opacity', fade.toFixed(3));
          put(sub, 'opacity', (clamp((T - 0.35) / 0.3) * fade).toFixed(3));
          put(sub, 'transform', `translateY(${(10 * (1 - Ease.outCubic(clamp((T - 0.35) / 0.3)))).toFixed(1)}px)`);
          break;
        }
        case 'ult': {
          const x = dir * 120 * (1 - e);
          put(node, 'transform', `translateX(${x.toFixed(1)}px)`);
          put(node, 'opacity', (Math.min(1, a * 1.6) * fade).toFixed(3));
          put(band, 'transform', `scaleX(${Ease.outExpo(clamp(T / 0.4)).toFixed(3)})`);
          put(main, 'transform', `translateX(${(dir * 40 * (1 - e)).toFixed(1)}px)`);
          put(main, 'opacity', '1');
          put(sub, 'opacity', clamp((T - 0.12) / 0.25).toFixed(3));
          put(lineA, 'transform', `scaleX(${Ease.outExpo(clamp((T - 0.05) / 0.5)).toFixed(3)})`);
          put(echo, 'opacity', '0');
          break;
        }
        default: {
          // round / perfect / timeup / banner / win: measured, ceremonial
          const s = 1.22 - 0.22 * e;
          put(main, 'transform', `scale(${(s * (o2 < 1 ? 1 + (1 - o2) * 0.06 : 1)).toFixed(4)})`);
          put(main, 'opacity', (e * fade).toFixed(3));
          put(echo, 'transform', `scale(${(1 + 0.35 * clamp((T - inT * 0.6) / 0.8)).toFixed(3)})`);
          put(echo, 'opacity', (T < inT * 0.6 ? 0 : 0.35 * (1 - clamp((T - inT * 0.6) / 0.8)) * fade).toFixed(3));
          put(band, 'transform', `scaleY(${Ease.outExpo(clamp(T / 0.35)).toFixed(3)})`);
          put(band, 'opacity', fade.toFixed(3));
          put(lineA, 'transform', `scaleX(${Ease.outExpo(clamp((T - 0.06) / 0.7)).toFixed(3)})`);
          put(lineB, 'transform', `scaleX(${Ease.outExpo(clamp((T - 0.12) / 0.7)).toFixed(3)})`);
          put(lineA, 'opacity', fade.toFixed(3)); put(lineB, 'opacity', fade.toFixed(3));
          put(sub, 'opacity', (clamp((T - 0.18) / 0.3) * fade).toFixed(3));
          put(sub, 'transform', `translateY(${(8 * (1 - Ease.outCubic(clamp((T - 0.18) / 0.3)))).toFixed(1)}px)`);
          if (style === 'perfect') {
            const sh = clamp((T - 0.3) / 0.7);
            put(shine, 'transform', `translateX(${(-260 + 520 * Ease.inOutCubic(sh)).toFixed(1)}%) skewX(-20deg)`);
            put(shine, 'opacity', (sh > 0 && sh < 1 ? 1 : 0).toFixed(2));
          }
        }
      }
    }, { ease: 'linear', key: node, done: () => node.remove() });
    return id;
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
     * 'ROUND 2', 'K.O.', 'TIME UP' ... are recognised too). opts: { sub, style, duration, round, side, element, keep }.
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
    /** Layout hook from the UI: in portrait-with-pad the FP / ULT meters move to a deck under the stage. */
    setLayout({ portrait }) {
      for (const sd of S) (portrait ? deck : sd.under).appendChild(sd.mini);
    },

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
        // ULT ignition: breathing glow + slow corona spin (deterministic: driven by real time)
        if (sd.ultFull) {
          put(sd.orbGlow, 'opacity', (0.62 + 0.38 * Math.sin(clock * 5.2 + sd.i)).toFixed(3));
          put(sd.orbRays, 'transform', `rotate(${((clock * 24) % 360).toFixed(1)}deg)`);
        }
        // combo auto-fade
        if (sd.comboShown) {
          sd.comboAge += dt;
          if (sd.comboAge > 2.6) fadeCombo(sd);
        }
        // low-health throb
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
