// Application context: renderer, scene, camera, clock, frame loop, quality tier, post pipeline, test API.
//
//   const ctx = createApp();
//   ctx.onUpdate((dtGame, dtReal) => { ... }, ORDER.GAME);
//   ctx.ready(); ctx.start();
//
// Test mode (`#test`): no requestAnimationFrame loop. The harness drives time through window.__ED:
//   __ED.advance(seconds)   run fixed 1/60 s frames without rendering
//   __ED.render()           render one frame

import * as THREE from 'three';
import { Time } from './time.js';
import { Emitter, parseFlags, pickQuality } from './util.js';
import { makeRng, clamp } from './math.js';
import { createPost } from '../post/index.js';

/** Update order of per-frame callbacks (lower runs first). */
export const ORDER = { INPUT: 0, GAME: 10, CHAR: 20, VFX: 30, CAM: 40, ENV: 50, UI: 60, POST: 70 };

function showError(msg) {
  try {
    let el = document.getElementById('ed-error');
    if (!el) {
      el = document.createElement('div');
      el.id = 'ed-error';
      (document.getElementById('app') || document.body).appendChild(el);
    }
    if (el.textContent.length < 4000) el.textContent += (el.textContent ? '\n' : '') + msg;
  } catch (e) { /* ignore */ }
}

export function createApp(opts = {}) {
  const flags = parseFlags();
  const test = !!flags.test;
  const canvas = opts.canvas || document.getElementById('gl');
  const quality = pickQuality(flags);

  window.addEventListener('error', (ev) => showError(String(ev.message || ev.error) + (ev.filename ? ' @' + String(ev.filename).split('/').pop() + ':' + ev.lineno : '')));
  window.addEventListener('unhandledrejection', (ev) => showError('promise: ' + String((ev.reason && ev.reason.stack) || ev.reason)));

  const renderer = new THREE.WebGLRenderer({ canvas, antialias: false, alpha: false, depth: false, stencil: false, powerPreference: 'high-performance', preserveDrawingBuffer: test });
  renderer.toneMapping = THREE.NoToneMapping;
  renderer.outputColorSpace = THREE.LinearSRGBColorSpace; // the post composite pass does tone mapping + sRGB encoding
  renderer.shadowMap.enabled = !!quality.shadows;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  renderer.setPixelRatio(1);
  renderer.info.autoReset = false;

  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0x020308);
  const camera = new THREE.PerspectiveCamera(40, 16 / 9, 0.1, 800);
  camera.position.set(0, 1.6, 9);
  camera.lookAt(0, 1.2, 0);

  const time = new Time();
  const events = new Emitter();
  const updaters = [];
  const ctx = {
    flags, test, canvas, renderer, scene, camera, quality, time, events,
    rng: makeRng(Number(flags.seed) || 20261112),
    viewport: { w: 1, h: 1, cssW: 1, cssH: 1, pr: 1, aspect: 1 },
    post: null,
    // set by the modules that own them (see CONTRACT.md)
    vfx: null, audio: null, cam: null, env: null, ui: null, input: null, game: null,
    ORDER,

    /** Register a per-frame callback fn(dtGame, dtReal). Returns an unsubscribe function. */
    onUpdate(fn, order = ORDER.GAME) {
      const u = { fn, order };
      updaters.push(u);
      updaters.sort((a, b) => a.order - b.order);
      return () => { const i = updaters.indexOf(u); if (i >= 0) updaters.splice(i, 1); };
    },

    /** Run one frame of `dtReal` seconds. */
    frame(dtReal, render = true) {
      time.tick(dtReal);
      const dg = time.dtGame, dr = time.dtReal;
      for (let i = 0; i < updaters.length; i++) updaters[i].fn(dg, dr);
      if (render) { renderer.info.reset(); ctx.post.render(scene, camera); }
    },

    resize() {
      const cssW = Math.max(1, canvas.clientWidth | 0), cssH = Math.max(1, canvas.clientHeight | 0);
      let pr = quality.pixelRatio;
      // cap the drawing buffer at ~2.6 MP
      const px = cssW * cssH * pr * pr;
      if (px > 2.6e6) pr *= Math.sqrt(2.6e6 / px);
      const w = Math.max(2, Math.round(cssW * pr)), h = Math.max(2, Math.round(cssH * pr));
      const v = ctx.viewport;
      if (v.w === w && v.h === h) return;
      v.w = w; v.h = h; v.cssW = cssW; v.cssH = cssH; v.pr = pr; v.aspect = w / h;
      renderer.setSize(w, h, false);
      camera.aspect = v.aspect;
      camera.updateProjectionMatrix();
      ctx.post.setSize(w, h);
      events.emit('resize', v);
    },

    /** Frame-rate target (60 by default; `#fps=120` / `#fps=30` override, `#fps=0` uncapped). */
    targetFps: flags.fps === undefined || flags.fps === true ? 60 : Number(flags.fps) || 0,
    /** Live frame statistics (real time): fps (smoothed), ms (smoothed frame time), scale (dynamic resolution). */
    stats: { fps: 60, ms: 16.7, scale: 1 },

    _running: false,
    start() {
      if (test || ctx._running) return;
      ctx._running = true;
      let last = performance.now();
      let slowAcc = 0, fastAcc = 0;
      const st = ctx.stats;
      const loop = (now) => {
        if (!ctx._running) return;
        requestAnimationFrame(loop);
        // 60 fps cap: on 90/120/144 Hz displays skip vsyncs so the game runs at a steady 60 (tolerance keeps a 60 Hz
        // display from ever skipping a frame).
        const tf = ctx.targetFps;
        if (tf > 0 && now - last < 1000 / tf - 2.5) return;
        const dt = clamp((now - last) / 1000, 0.001, 1 / 15);
        last = now;
        st.ms += (dt * 1000 - st.ms) * 0.08;
        st.fps = 1000 / st.ms;
        // dynamic resolution keeps 60 fps: drop the scene scale when frames run long, raise it again when there is headroom
        if (!flags.nodrs && tf > 0) {
          const budget = 1 / tf;
          if (dt > budget * 1.12) { slowAcc += dt; fastAcc = 0; } else if (dt < budget * 1.04) { fastAcc += dt; slowAcc = Math.max(0, slowAcc - dt * 0.5); } else { fastAcc = 0; }
          if (slowAcc > 0.75) { ctx.post.setRenderScale(ctx.post.renderScale * 0.88); slowAcc = 0; }
          if (fastAcc > 4) { ctx.post.setRenderScale(ctx.post.renderScale / 0.94); fastAcc = 0; }
          st.scale = ctx.post.renderScale;
        }
        ctx.frame(dt, true);
      };
      requestAnimationFrame(loop);
      if (flags.fpsmeter) {
        const el = document.createElement('div');
        el.style.cssText = 'position:absolute;right:8px;top:8px;z-index:50;font:12px/1.3 ui-monospace,Menlo,monospace;color:#9fe;background:rgba(0,0,0,.55);padding:4px 6px;border-radius:4px;pointer-events:none';
        (document.getElementById('app') || document.body).appendChild(el);
        setInterval(() => {
          const i = renderer.info.render;
          el.textContent = `${st.fps.toFixed(0)} fps  ${st.ms.toFixed(1)} ms  res ${(st.scale * 100).toFixed(0)}%  ${i.calls} dc  ${(i.triangles / 1000).toFixed(0)}k tri`;
        }, 250);
      }
    },
    stop() { ctx._running = false; },

    /** Call once everything is loaded: tells the test harness the page is ready. */
    ready() { window.__ED.ready = true; events.emit('ready'); },
  };

  ctx.post = createPost(ctx);
  ctx.onUpdate((dg, dr) => ctx.post.update(dr), ORDER.POST);
  ctx.resize();
  if (typeof ResizeObserver !== 'undefined') new ResizeObserver(() => ctx.resize()).observe(canvas);
  window.addEventListener('resize', () => ctx.resize());

  window.__ED = {
    ctx, THREE, ready: false,
    /** advance the simulation by `sec` seconds in fixed steps (no rendering) */
    advance(sec, step = 1 / 60) {
      const n = Math.max(0, Math.round(sec / step));
      for (let i = 0; i < n; i++) ctx.frame(step, false);
      return time.game;
    },
    render() { ctx.resize(); renderer.info.reset(); ctx.post.render(scene, camera); return { calls: renderer.info.render.calls, tris: renderer.info.render.triangles }; },
    info() { return { calls: renderer.info.render.calls, tris: renderer.info.render.triangles, geometries: renderer.info.memory.geometries, textures: renderer.info.memory.textures, programs: (renderer.info.programs || []).length, tier: quality.tier, scale: ctx.post.renderScale }; },
  };
  return ctx;
}
