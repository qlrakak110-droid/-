// Tiny tween runner for the DOM UI, driven by ctx.time real seconds (so captures in test mode are deterministic and
// the UI keeps animating through hit-stop / pause). Tweens only write transform / opacity.

import { Ease, clamp } from '../core/math.js';

/**
 * @returns {{ add: Function, kill: Function, update: Function, clear: Function }}
 */
export function createAnimator() {
  const list = [];
  const byKey = new Map();
  return {
    /**
     * Run fn(k, t) every frame for `dur` seconds; k is the eased progress 0..1, t the raw progress.
     * A tween with the same `key` replaces the previous one (its `done` is not called).
     * @param {number} dur seconds
     * @param {(k:number, t:number) => void} fn
     * @param {{ key?: any, delay?: number, ease?: string|Function, done?: Function }} [o]
     */
    add(dur, fn, o = {}) {
      const tw = { t: -(o.delay || 0), dur: Math.max(1e-4, dur), fn, ease: typeof o.ease === 'function' ? o.ease : Ease[o.ease || 'outCubic'], done: o.done, key: o.key, dead: false };
      if (o.key !== undefined) {
        const old = byKey.get(o.key);
        if (old) old.dead = true;
        byKey.set(o.key, tw);
      }
      list.push(tw);
      if (!o.delay) fn(tw.ease(0), 0);
      return tw;
    },
    /** Stop the tween registered under `key` (no final call). */
    kill(key) {
      const tw = byKey.get(key);
      if (tw) { tw.dead = true; byKey.delete(key); }
    },
    update(dt) {
      for (let i = 0; i < list.length; i++) {
        const tw = list[i];
        if (tw.dead) continue;
        tw.t += dt;
        if (tw.t < 0) continue;
        const t = clamp(tw.t / tw.dur);
        tw.fn(tw.ease(t), t);
        if (t >= 1) {
          tw.dead = true;
          if (tw.key !== undefined && byKey.get(tw.key) === tw) byKey.delete(tw.key);
          if (tw.done) tw.done();
        }
      }
      let j = 0;
      for (let i = 0; i < list.length; i++) if (!list[i].dead) list[j++] = list[i];
      list.length = j;
    },
    clear() { for (const tw of list) tw.dead = true; list.length = 0; byKey.clear(); },
  };
}

/** Create an element: h('div.a.b', { attrs }, children...) — children are nodes or HTML strings. */
export function h(sel, attrs, ...kids) {
  const [tag, ...cls] = sel.split('.');
  const el = document.createElement(tag || 'div');
  if (cls.length) el.className = cls.join(' ');
  if (attrs) {
    for (const k in attrs) {
      const v = attrs[k];
      if (v === undefined || v === null || v === false) continue;
      if (k === 'html') el.innerHTML = v;
      else if (k === 'text') el.textContent = v;
      else if (k === 'style') el.style.cssText = v;
      else el.setAttribute(k, v === true ? '' : v);
    }
  }
  for (const c of kids) {
    if (c === null || c === undefined || c === false) continue;
    if (typeof c === 'string') el.insertAdjacentHTML('beforeend', c);
    else el.appendChild(c);
  }
  return el;
}

/** Escape text for HTML templates. */
export const esc = (s) => String(s == null ? '' : s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
