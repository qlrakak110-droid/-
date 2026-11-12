// Touch controls: a floating virtual stick (left) and a fan-shaped action cluster (right). Pointer events with capture,
// so every finger owns the control it landed on (multi-touch safe). Everything feeds ctx.input.setVirtual(action, down, 0).
// Layout is computed in CSS pixels on resize only; per-frame work is limited to cached transform / opacity writes.

import { h } from './anim.js';
import { icon } from './icons.js';
import { makePie, setPie, put, putText, putClass } from './hud.js';

// Buttons: action, icon, label, diameter (design px). Positions are offsets of each centre from the light button's
// centre, per layout (y down). Values were tuned on captures at 844x390 (landscape) and 390x844 (portrait).
const BUTTONS = [
  { a: 'light', ico: 'light', ko: '약공', d: 88 },
  { a: 'heavy', ico: 'heavy', ko: '강공', d: 68 },
  { a: 'skill1', ico: '', ko: '', d: 60, skill: 0 },   // skill icons arrive with ui.hud.skills(0, ...)
  { a: 'skill2', ico: '', ko: '', d: 60, skill: 1 },
  { a: 'skill3', ico: '', ko: '', d: 60, skill: 2 },
  { a: 'ult', ico: 'ult', ko: '궁극기', d: 70 },
  { a: 'guard', ico: 'guard', ko: '막기', d: 58 },
  { a: 'dodge', ico: 'dodge', ko: '회피', d: 58 },
];
/** Offset at radius r and angle deg (0 = right, 90 = up), in screen space (y down). */
const polar = (r, deg) => [Math.cos((deg * Math.PI) / 180) * r, -Math.sin((deg * Math.PI) / 180) * r];
const LAYOUT = {
  landscape: {
    light: [0, 0], heavy: polar(126, 180), skill1: polar(126, 146), skill2: polar(126, 112), skill3: polar(126, 78),
    ult: [-152, -152], guard: [-212, -80], dodge: [-226, 12],
  },
  portrait: {
    light: [0, 0], heavy: polar(118, 206), skill1: polar(120, 164), skill2: polar(120, 126), skill3: polar(120, 88),
    ult: polar(214, 97), dodge: polar(214, 125), guard: polar(218, 152),
  },
};
const STICK_R = 54;     // knob travel (design px)

/**
 * @param {object} ui the ui object (createUI)
 */
export function createTouch(ui) {
  const { ctx, anim } = ui;
  const root = h('div.ed-pad');
  const zone = h('div.pad-zone');
  const knob = h('div.stick-knob');
  const arrows = ['l', 'r', 'u', 'd'].map((d) => h('i.stick-arrow.' + d));
  const base = h('div.stick-base', null, h('i.stick-ring'), h('i.stick-ring.inner'), ...arrows, knob);
  zone.appendChild(base);
  root.appendChild(zone);
  const cluster = h('div.pad-cluster');
  root.appendChild(cluster);

  const btns = BUTTONS.map((def) => {
    const ico = h('span.pb-ico', { html: icon(def.ico) });
    const label = h('span.pb-label', { text: def.ko });
    const el = h(`button.pad-btn.pb-${def.a}`, { type: 'button', 'aria-label': def.a }, h('i.pb-bg'), ico, label);
    const b = { def, el, ico, label, ptrs: new Set(), down: false };
    if (def.skill !== undefined) {
      b.pie = makePie('pb-pie');
      b.cost = h('span.pb-cost');
      b.glow = h('i.pb-glow');
      el.append(b.pie, b.glow, b.cost);
      b.state = { iconName: def.ico, cd: -1, ready: null, cost: -1 };
    }
    if (def.a === 'ult') {
      // back to front: rays, glow, gauge ring, then the button face (covers the ring's centre), icon, label
      b.ring = makePie('pb-ring');
      b.glow = h('i.pb-glow');
      b.rays = h('i.pb-rays', { html: '<svg viewBox="0 0 100 100" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><path d="M50 2v9M50 89v9M2 50h9M89 50h9M16 16l6 6M78 78l6 6M16 84l6-6M78 22l6-6"/></svg>' });
      el.prepend(b.rays, b.glow, b.ring);
      b.full = false;
    }
    if (!def.ko) label.remove();
    const press = (on) => {
      if (on === b.down) return;
      b.down = on;
      el.classList.toggle('is-down', on);
      if (ctx.input) ctx.input.setVirtual(def.a, on, 0);
      if (on && ctx.input) { ctx.input.noteDevice('touch'); ctx.input.rumble(0, 0.2, 0.2, 18); }
    };
    b.press = press;
    el.addEventListener('pointerdown', (e) => {
      e.preventDefault();
      e.stopPropagation();
      try { el.setPointerCapture(e.pointerId); } catch (err) { /* synthetic pointer */ }
      b.ptrs.add(e.pointerId);
      press(true);
    });
    const end = (e) => {
      if (!b.ptrs.delete(e.pointerId)) return;
      if (!b.ptrs.size) press(false);
    };
    el.addEventListener('pointerup', end);
    el.addEventListener('pointercancel', end);
    el.addEventListener('lostpointercapture', end);
    el.addEventListener('contextmenu', (e) => e.preventDefault());
    cluster.appendChild(el);
    return b;
  });
  const byAction = Object.fromEntries(btns.map((b) => [b.def.a, b]));

  // --- stick ----------------------------------------------------------------------------------------------------
  const stick = { id: null, ox: 0, oy: 0, homeX: 0, homeY: 0, zoneRect: null, dirs: { left: false, right: false, up: false, down: false }, r: STICK_R, s: 1 };
  const setDir = (name, on) => {
    if (stick.dirs[name] === on) return;
    stick.dirs[name] = on;
    if (ctx.input) ctx.input.setVirtual(name, on, 0);
    putClass(arrows[{ left: 0, right: 1, up: 2, down: 3 }[name]], 'on', on);
  };
  const moveStick = (cx, cy) => {
    const R = stick.r * stick.s;
    let dx = cx - stick.ox, dy = cy - stick.oy;
    const len = Math.hypot(dx, dy);
    if (len > R) { dx *= R / len; dy *= R / len; }
    put(knob, 'transform', `translate(${dx.toFixed(1)}px,${dy.toFixed(1)}px)`);
    const n = len / R;
    const c = len > 0 ? dx / Math.hypot(dx, dy) : 0, s = len > 0 ? dy / Math.hypot(dx, dy) : 0;
    const live = n > 0.28;
    // 8-way with a stricter vertical sector (accidental up/down is worse than a late diagonal in a fighter)
    setDir('right', live && c > 0.38);
    setDir('left', live && c < -0.38);
    setDir('up', live && s < -0.62);
    setDir('down', live && s > 0.62);
  };
  const placeBase = (x, y) => put(base, 'transform', `translate(${x.toFixed(1)}px,${y.toFixed(1)}px)`);
  zone.addEventListener('pointerdown', (e) => {
    if (stick.id !== null) return;
    e.preventDefault();
    try { zone.setPointerCapture(e.pointerId); } catch (err) { /* synthetic pointer */ }
    stick.id = e.pointerId;
    const r = zone.getBoundingClientRect();
    stick.zoneRect = r;
    // float the base under the thumb, kept inside the zone
    const R = stick.r * stick.s, m = R + 8;
    const x = Math.min(Math.max(e.clientX - r.left, m), r.width - m), y = Math.min(Math.max(e.clientY - r.top, m), r.height - m);
    stick.ox = r.left + x; stick.oy = r.top + y;
    anim.kill(base);
    placeBase(x, y);
    root.classList.add('stick-on');
    moveStick(e.clientX, e.clientY);
    if (ctx.input) ctx.input.noteDevice('touch');
  });
  zone.addEventListener('pointermove', (e) => { if (e.pointerId === stick.id) moveStick(e.clientX, e.clientY); });
  const stickEnd = (e) => {
    if (e && e.pointerId !== stick.id) return;
    stick.id = null;
    root.classList.remove('stick-on');
    for (const d in stick.dirs) setDir(d, false);
    put(knob, 'transform', '');
    const r = stick.zoneRect;
    if (r) {
      const fx = stick.ox - r.left, fy = stick.oy - r.top;
      anim.add(0.22, (k) => placeBase(fx + (stick.homeX - fx) * k, fy + (stick.homeY - fy) * k), { key: base, ease: 'outCubic' });
    }
  };
  zone.addEventListener('pointerup', stickEnd);
  zone.addEventListener('pointercancel', stickEnd);
  zone.addEventListener('lostpointercapture', stickEnd);

  const releaseAll = () => {
    for (const b of btns) { b.ptrs.clear(); b.press(false); }
    if (stick.id !== null) stickEnd({ pointerId: stick.id });
  };
  window.addEventListener('blur', releaseAll);

  // --- layout ---------------------------------------------------------------------------------------------------
  /**
   * @param {{ W:number, H:number, portrait:boolean, safe:{t,r,b,l}, padTop:number }} L
   */
  function layout(L) {
    const { W, H, safe } = L;
    const portrait = L.portrait;
    const pos = portrait ? LAYOUT.portrait : LAYOUT.landscape;
    // scale: fit the cluster's reach into the available height / width
    const s = portrait ? Math.min(1.25, Math.max(0.82, (W - safe.l - safe.r) / 390)) : Math.min(1.3, Math.max(0.78, (H - safe.t - safe.b) / 390));
    stick.s = s;
    const ax = W - safe.r - (portrait ? 80 : 82) * s;
    const ay = H - safe.b - (portrait ? 156 : 80) * s;
    for (const b of btns) {
      const p = pos[b.def.a];
      const d = b.def.d * s;
      b.el.style.cssText = `left:${(ax + p[0] * s - d / 2).toFixed(1)}px;top:${(ay + p[1] * s - d / 2).toFixed(1)}px;width:${d.toFixed(1)}px;height:${d.toFixed(1)}px`;
    }
    // stick zone: left part of the pad area; base rests at a comfortable thumb spot
    const zTop = portrait ? L.padTop : Math.round(H * 0.3);
    const zW = portrait ? Math.round(W * 0.46) : Math.round(W * 0.42);
    zone.style.cssText = `left:0;top:${zTop}px;width:${zW}px;height:${H - zTop}px`;
    const bs = (STICK_R * 2 + 36) * s;
    base.style.width = base.style.height = bs.toFixed(1) + 'px';
    base.style.marginLeft = base.style.marginTop = (-bs / 2).toFixed(1) + 'px';
    knob.style.width = knob.style.height = (58 * s).toFixed(1) + 'px';
    knob.style.marginLeft = knob.style.marginTop = (-29 * s).toFixed(1) + 'px';
    stick.homeX = safe.l + (portrait ? 88 : 112) * s;
    stick.homeY = H - zTop - safe.b - (portrait ? 118 : 104) * s;
    if (stick.id === null) placeBase(stick.homeX, stick.homeY);
  }

  // --- data from the HUD ----------------------------------------------------------------------------------------
  function skills(list, fp) {
    for (let j = 0; j < 3; j++) {
      const b = byAction['skill' + (j + 1)], d = list && list[j], st = b.state;
      putClass(b.el, 'is-off', !d);
      if (!d) continue;
      const ic = d.icon || d.id;
      if (ic && ic !== st.iconName) { st.iconName = ic; b.ico.innerHTML = icon(ic) || icon('light'); }
      const cd = Math.max(0, Math.min(1, d.cd || 0));
      if (cd !== st.cd) { st.cd = cd; setPie(b.pie, cd); putClass(b.el, 'is-cd', cd > 0); }
      const cost = d.cost || 0;
      if (cost !== st.cost) { st.cost = cost; putText(b.cost, cost || ''); }
      putClass(b.el, 'no-fp', cost > 0 && fp < cost);
      const ready = d.ready !== undefined ? !!d.ready : cd <= 0 && fp >= cost;
      if (ready !== st.ready) {
        if (ready && st.ready === false) anim.add(0.5, (k) => put(b.glow, 'transform', `scale(${(1 + 0.4 * (1 - k)).toFixed(3)})`), { key: b.glow, ease: 'outCubic' });
        st.ready = ready;
        putClass(b.el, 'is-ready', ready);
        if (!ready) put(b.glow, 'opacity', '');
      }
    }
  }
  function meter(ultR, fp) {
    const b = byAction.ult;
    touch._ult = ultR;
    setPie(b.ring, ultR);
    const full = ultR >= 0.999;
    if (full !== b.full) {
      b.full = full;
      putClass(b.el, 'is-full', full);
      if (!full) { put(b.glow, 'opacity', ''); put(b.rays, 'transform', ''); }
    }
    if (fp !== touch._fp) {
      touch._fp = fp;
      for (let j = 0; j < 3; j++) { const sb = byAction['skill' + (j + 1)]; putClass(sb.el, 'no-fp', sb.state.cost > 0 && fp < sb.state.cost); }
    }
  }

  let clock = 0, lastCine = 0;
  const touch = {
    el: root,
    _fp: -1,
    _ult: 0,
    layout,
    skills,
    meter,
    releaseAll,
    update(dt, cine) {
      clock += dt;
      const b = byAction.ult;
      if (b.full) {
        put(b.glow, 'opacity', (0.55 + 0.45 * Math.sin(clock * 5.2)).toFixed(3));
        put(b.rays, 'transform', `rotate(${((clock * 30) % 360).toFixed(1)}deg)`);
      }
      for (let j = 1; j <= 3; j++) {
        const sb = byAction['skill' + j];
        if (sb.state.ready) put(sb.glow, 'opacity', (0.5 + 0.35 * Math.sin(clock * 4.2 + j * 1.7)).toFixed(2));
      }
      if (cine !== lastCine) { lastCine = cine; put(root, 'opacity', (1 - 0.75 * cine).toFixed(3)); }
    },
  };
  return touch;
}
