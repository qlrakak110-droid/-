// DOM UI of 「흑일무림 黑日武林」: menus, HUD and touch controls inside #ui, in the ink-wash idiom. See README.md.
//
//   const ui = createUI(ctx);                 // ctx.ui
//   ui.on('pick', ({ p1, cpu, difficulty }) => ...);
//   ui.show('select', { roster });
//   ui.hud.set({ time, p1: {...}, p2: {...} });    // every frame, cheap
//
// Animations run on ctx.time real seconds through a small tween runner (deterministic in test captures); CSS only
// handles hover / press micro-transitions, which are switched off in test mode.

import css from './ui.css';
import { Emitter } from '../core/util.js';
import { clamp } from '../core/math.js';
import { createAnimator, h } from './anim.js';
import { createHud } from './hud.js';
import { createTouch } from './touch.js';
import { createScreens } from './screens.js';
import { DEFAULT_ROSTER } from './roster.js';
import { paperTexture, washTexture, bandClip, swath, dash, divider, cssUrl } from './ink.js';

const SCREENS = ['title', 'select', 'vs', 'hud', 'pause', 'result', 'movelist', 'none'];

/**
 * Procedural ink set once on the root as CSS custom properties: paper grain and ink wash textures, brushed band
 * clip-paths (HP bars, announcer bands, tags) and brush shapes as mask images. All generated from fixed seeds.
 */
function inkTokens(root) {
  const set = (k, v) => root.style.setProperty(k, v);
  set('--noise', paperTexture());
  set('--wash', washTexture());
  set('--clip-hp-l', bandClip({ seed: 11, n: 18, amp: 20, left: 'fray', right: 'blunt' }));
  set('--clip-hp-r', bandClip({ seed: 11, n: 18, amp: 20, left: 'fray', right: 'blunt', flip: true }));
  set('--clip-bar-l', bandClip({ seed: 14, n: 10, amp: 26, left: 'blunt', right: 'taper' }));
  set('--clip-bar-r', bandClip({ seed: 14, n: 10, amp: 26, left: 'blunt', right: 'taper', flip: true }));
  set('--clip-band', bandClip({ seed: 21, n: 26, amp: 13, left: 'fray', right: 'fray' }));
  set('--clip-band-b', bandClip({ seed: 27, n: 20, amp: 16, left: 'taper', right: 'fray' }));
  set('--clip-tag', bandClip({ seed: 33, n: 6, amp: 12, left: 'blunt', right: 'blunt' }));
  set('--clip-scroll', bandClip({ seed: 41, n: 22, amp: 9, left: 'blunt', right: 'fray', vertical: true }));
  set('--m-swath', cssUrl(swath({ seed: 9, dry: 0.9 })));
  set('--m-swath-b', cssUrl(swath({ seed: 15, dry: 0.5 })));
  set('--m-dash', cssUrl(dash({ seed: 5 })));
  set('--m-div', cssUrl(divider({ seed: 3 })));
}

/**
 * Create the UI and store it on ctx.ui.
 * @param {object} ctx app context
 * @param {{ touch?: boolean }} [opts] touch: force the touch pad on / off (default: coarse pointer)
 */
export function createUI(ctx, opts = {}) {
  if (!document.getElementById('ed-ui-css')) {
    const st = document.createElement('style');
    st.id = 'ed-ui-css';
    st.textContent = css;
    document.head.appendChild(st);
  }
  const host = document.getElementById('ui') || document.body;
  const root = h('div.ed-ui');
  host.appendChild(root);
  inkTokens(root);
  root.classList.toggle('is-test', !!ctx.test);
  const html = document.documentElement;

  const events = new Emitter();
  const anim = createAnimator();
  const safeProbe = h('div.ed-safe-probe');
  root.appendChild(safeProbe);

  const ui = {
    ctx, root, anim,
    screen: 'none',
    data: {},
    roster: DEFAULT_ROSTER,
    /** Subscribe to a UI event; returns an unsubscribe function. */
    on: (name, fn) => events.on(name, fn),
    emit: (name, ...args) => events.emit(name, ...args),
    /** Play a UI sound if the audio module exists. */
    sound(name) { if (ctx.audio && ctx.audio.play) { try { ctx.audio.play(name, { volume: 0.7 }); } catch (e) { /* optional peer */ } } },
    /** Last input device: 'keyboard' | 'gamepad' | 'touch' (touch when the pad is on and nothing else was used). */
    get device() {
      const d = ctx.input ? ctx.input.device : 'keyboard';
      if (d === 'keyboard' && touchOn && !usedKeys) return 'touch';
      return d;
    },
    /** Key hint for an action, for the current device; '' on touch and for the CPU side (P2 outside versus mode). */
    keyLabel(action, player = 0) {
      if (!ctx.input) return '';
      const d = ui.device;
      if (d === 'touch' || (player === 1 && ctx.input.mode !== 'versus')) return '';
      return ctx.input.keyLabel(action, player, d);
    },
  };
  ctx.ui = ui;

  // ---------------------------------------------------------------------------------------------------------------
  // focus / navigation shared by every menu screen

  const nav = { items: [], cur: null };
  /** Make `el` a focusable menu item. act(): confirm; lr(dir): left/right adjusts a value instead of moving focus. */
  ui.item = (el, { act, lr, sound = 'ui_select' } = {}) => {
    el.classList.add('item');
    el._act = act;
    el._lr = lr;
    el._snd = sound;
    el.addEventListener('pointerenter', (e) => { if (e.pointerType === 'mouse' && nav.items.includes(el)) ui.focus(el, true); });
    el.addEventListener('click', (e) => {
      e.stopPropagation();
      if (!nav.items.includes(el) || el.classList.contains('is-disabled')) return;
      ui.focus(el, false);
      if (act) { ui.sound(sound); act(e); }
    });
    return el;
  };
  /** Set the focusable items of the active screen (order = tab order) and focus one. */
  ui.setItems = (items, initial) => {
    nav.items = items.filter(Boolean);
    ui.focus(initial && nav.items.includes(initial) ? initial : nav.items[0], false, true);
  };
  ui.focus = (el, sound = true, silent = false) => {
    if (!el || el === nav.cur) return;
    if (nav.cur) nav.cur.classList.remove('is-focus');
    nav.cur = el;
    el.classList.add('is-focus');
    if (sound && !silent) ui.sound('ui_move');
    if (el._onFocus) el._onFocus();
  };
  ui.focused = () => nav.cur;
  /** Spatial navigation: nearest item in the pressed direction (reads rects only on key presses). */
  function move(dir) {
    const cur = nav.cur;
    if (!cur) return ui.focus(nav.items[0]);
    const a = cur.getBoundingClientRect();
    const ax = a.left + a.width / 2, ay = a.top + a.height / 2;
    let best = null, bestScore = Infinity;
    for (const el of nav.items) {
      if (el === cur || el.classList.contains('is-disabled') || el.offsetParent === null) continue;
      const b = el.getBoundingClientRect();
      const bx = b.left + b.width / 2, by = b.top + b.height / 2;
      const dx = bx - ax, dy = by - ay;
      let along, across;
      if (dir === 'left') { along = -dx; across = dy; } else if (dir === 'right') { along = dx; across = dy; } else if (dir === 'up') { along = -dy; across = dx; } else { along = dy; across = dx; }
      if (along < 4) continue;
      const score = along + Math.abs(across) * 2.2;
      if (score < bestScore) { bestScore = score; best = el; }
    }
    if (best) ui.focus(best);
  }

  function onAction(action, down, player, info) {
    if (action === 'device') {
      if (info && info.device !== 'touch') usedKeys = true;
      hud.refreshDevice();
      syncDeviceClass();
      return;
    }
    if (!down) return;
    unlockAudio();
    // one key can carry two actions (Esc = pause + back): after a screen change, the rest of that frame is ignored
    if (navLock) return;
    const scr = screens[ui.screen];
    if (ui.screen === 'hud') {
      if (action === 'pause' && player === 0 && !(info && info.repeat)) ui.emit('pause');
      return;
    }
    if (!scr) return;
    if (scr.onAction && scr.onAction(action, info) === true) return;
    const cur = nav.cur;
    if (action === 'left' || action === 'right') {
      if (cur && cur._lr) { cur._lr(action === 'left' ? -1 : 1); ui.sound('ui_move'); } else move(action);
    } else if (action === 'up' || action === 'down') move(action);
    else if (action === 'confirm' && !(info && info.repeat)) {
      if (cur && cur._act && !cur.classList.contains('is-disabled')) { ui.sound(cur._snd || 'ui_select'); cur._act(); }
    } else if (action === 'back' && !(info && info.repeat)) {
      if (scr.back) { ui.sound('ui_back'); scr.back(); }
    }
  }
  let usedKeys = false;
  let navLock = false;
  let audioUnlocked = false;
  function unlockAudio() {
    if (audioUnlocked || !ctx.audio || !ctx.audio.unlock) return;
    audioUnlocked = true;
    try { ctx.audio.unlock(); } catch (e) { /* optional peer */ }
  }
  root.addEventListener('pointerdown', unlockAudio);

  // ---------------------------------------------------------------------------------------------------------------
  // layout: scale unit, portrait stage rectangle, safe areas

  let touchOn = opts.touch !== undefined ? !!opts.touch : (typeof matchMedia !== 'undefined' && matchMedia('(pointer: coarse)').matches) || !!(ctx.quality && ctx.quality.mobile);
  const layoutState = { W: 0, H: 0, portrait: false, padPortrait: false, safe: { t: 0, r: 0, b: 0, l: 0 }, padTop: 0, k: 1 };
  function readSafe() {
    const cs = getComputedStyle(safeProbe);
    return { t: parseFloat(cs.paddingTop) || 0, r: parseFloat(cs.paddingRight) || 0, b: parseFloat(cs.paddingBottom) || 0, l: parseFloat(cs.paddingLeft) || 0 };
  }
  /** The fight is on screen (HUD, or a pause / move list over it). */
  const fightShown = () => ui.screen === 'hud' || ui.screen === 'pause' || (ui.screen === 'movelist' && !!ui.data.fromPause);
  function layout() {
    const W = window.innerWidth, H = window.innerHeight;
    const portrait = H > W * 1.08;
    // the stage becomes a 16:10 strip above the pad only while the fight is on screen; menus keep the full backdrop
    const padPortrait = portrait && touchOn && fightShown();
    const safe = readSafe();
    const L = layoutState;
    L.W = W; L.H = H; L.portrait = portrait; L.padPortrait = padPortrait; L.safe = safe;
    // stage: full screen, or a 16:10 strip at the top with the pad below it
    const stageH = padPortrait ? Math.round(Math.min(W * 0.625, H * 0.5)) : H;
    html.classList.toggle('ed-pad-portrait', padPortrait);
    root.style.setProperty('--stage-h', stageH + 'px');
    html.style.setProperty('--ed-stage-h', stageH + 'px');
    root.classList.toggle('is-touch', touchOn);
    root.classList.toggle('is-portrait', portrait);
    root.classList.toggle('is-pad-portrait', padPortrait);
    root.classList.toggle('is-short', !portrait && H < 520);
    root.classList.toggle('is-narrow', W < 600);
    // design unit (1 "px" of the 1280x720 design): phones get a boost because they are held close
    let k;
    if (padPortrait) k = clamp(W / 600, 0.6, 1.05);
    else if (touchOn) k = clamp(Math.min(W / 1080, H / 540), 0.66, 1.25);
    else k = clamp(Math.min(W / 1280, H / 720), 0.62, 1.7);
    root.style.setProperty('--k', k.toFixed(4) + 'px');
    L.k = ui.k = k;
    hud.setLayout({ portrait: padPortrait });
    // portrait: the bars and meters form a deck under the stage; the pad's stick zone starts below it
    L.padTop = padPortrait ? Math.round(hud.topBottom()) + 8 : 0;
    root.style.setProperty('--pad-deck', L.padTop + 'px');
    if (touchOn) touch.layout(L);
    for (const n in screens) if (screens[n].layout) screens[n].layout(L);
  }
  function syncDeviceClass() {
    const d = ui.device;
    root.classList.toggle('dev-touch', d === 'touch');
    root.classList.toggle('dev-gamepad', d === 'gamepad');
  }

  // ---------------------------------------------------------------------------------------------------------------
  // modules

  const hud = createHud(ui);
  const touch = createTouch(ui);
  ui.hud = hud;
  root.appendChild(hud.el);
  root.appendChild(touch.el);
  const screenLayer = h('div.ed-screens');
  root.appendChild(screenLayer);
  const screens = createScreens(ui);
  for (const n in screens) { screens[n].el.classList.add('scr', 'scr-' + n); screens[n].el.style.display = 'none'; screenLayer.appendChild(screens[n].el); }

  const hudSet = hud.set, hudSkills = hud.skills, hudSetup = hud.setup;
  let p1Skills = null;
  hud.setup = (o) => {
    hudSetup(o);
    touch.setUltIcon(hud.ultIcon(0));
  };
  // the touch pad mirrors P1's meters and skills
  hud.set = (o) => {
    hudSet(o);
    const p = o && o.p1;
    if (touchOn && p && (p.ult !== undefined || p.fp !== undefined)) {
      touch.meter(p.ult !== undefined ? clamp(p.ult / (p.ultMax || 100)) : touch._ult, p.fp !== undefined ? p.fp : touch._fp);
    }
  };
  hud.skills = (side, list) => {
    hudSkills(side, list);
    if (side === 0) p1Skills = list;
    if (side === 0 && touchOn) touch.skills(list, touch._fp < 0 ? 100 : touch._fp);
  };

  ui.touch = {
    /** Show the virtual stick + buttons (they appear while the HUD is up). */
    setVisible(b) {
      const on = !!b;
      if (on === touchOn) return;
      touchOn = on;
      if (!on) { touch.releaseAll(); if (ctx.input) ctx.input.clearVirtual(0); }
      if (on && p1Skills) touch.skills(p1Skills, touch._fp < 0 ? 100 : touch._fp);
      syncDeviceClass();
      layout();
      syncVisibility();
    },
    get visible() { return touchOn; },
    el: touch.el,
  };

  function syncVisibility() {
    const s = ui.screen;
    const hudOn = fightShown();
    if (layoutState.portrait && touchOn && hudOn !== layoutState.padPortrait) layout();
    root.classList.toggle('show-hud', hudOn);
    root.classList.toggle('show-pad', touchOn && s === 'hud');
    root.classList.toggle('hud-dim', hudOn && s !== 'hud');
    if (s !== 'hud') touch.releaseAll();
  }

  // ---------------------------------------------------------------------------------------------------------------
  // screens

  let shown = null;
  /**
   * Show a screen: 'title' | 'select' | 'vs' | 'hud' | 'pause' | 'result' | 'movelist' | 'none'. data is screen specific
   * (see README). Returns the ui.
   */
  ui.show = (screen, data = {}) => {
    if (!SCREENS.includes(screen)) throw new Error('ui.show: unknown screen ' + screen);
    const prev = ui.screen;
    ui.screen = screen;
    navLock = true;
    ui.data = data || {};
    if (shown && shown !== screens[screen]) {
      const old = shown;
      if (old.exit) old.exit(screen);
      const el = old.el;
      // a screen that is fading out never takes a tap meant for the HUD / pad underneath
      el.style.pointerEvents = 'none';
      anim.add(0.16, (k) => { el.style.opacity = (1 - k).toFixed(3); }, { key: el, ease: 'linear', done: () => { el.style.display = 'none'; } });
      shown = null;
    }
    // screens keep their elements between visits: drop the old focus mark so a return visit shows one focus only
    if (nav.cur) nav.cur.classList.remove('is-focus');
    nav.items = []; nav.cur = null;
    const scr = screens[screen];
    if (scr) {
      anim.kill(scr.el);
      scr.el.style.display = '';
      scr.el.style.opacity = '1';
      scr.el.style.pointerEvents = '';
      scr.enter(ui.data, prev);
      shown = scr;
    }
    if (screen === 'hud' && prev !== 'pause' && prev !== 'movelist') hud.reset();
    if (screen === 'hud' && data && (data.p1 || data.p2)) hud.setup(data);
    syncVisibility();
    ui.emit('screen', screen, prev);
    return ui;
  };

  // ---------------------------------------------------------------------------------------------------------------

  if (ctx.input) ctx.input.on(onAction);
  window.addEventListener('resize', layout);
  window.addEventListener('orientationchange', layout);
  layout();
  syncDeviceClass();
  syncVisibility();

  ctx.onUpdate((dtGame, dtReal) => {
    navLock = false;
    anim.update(dtReal);
    hud.update(dtReal);
    if (touchOn) touch.update(dtReal, hud.cine);
    if (shown && shown.update) shown.update(dtReal);
  }, ctx.ORDER.UI);

  /** Re-run layout (after an external change to the page size). */
  ui.layout = layout;
  /** Remove the UI from the page. */
  ui.dispose = () => {
    window.removeEventListener('resize', layout);
    window.removeEventListener('orientationchange', layout);
    root.remove();
    html.classList.remove('ed-pad-portrait');
  };
  return ui;
}
