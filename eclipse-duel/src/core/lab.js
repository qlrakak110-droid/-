// Lab scaffold: a small sandbox page per module (src/labs/<name>.js) used to develop and screenshot one subsystem in
// isolation. `node tools/build.mjs <name>` -> build/<name>.html, `node tools/shot.mjs <name> ...` -> PNG captures.
//
//   createLab({
//     stage: true,                        // default neutral stage: dark stone floor + key/rim/fill lights (false = empty scene)
//     view: { target: [0, 1.2, 0], dist: 7, yaw: 0, pitch: 8, fov: 40 },
//     setup(ctx, lab) { ... },            // build things once (may be async)
//     scenarios: { name(ctx, lab, ...args) { ... } },   // things the harness (or the on-page buttons) can trigger
//   })
//
// In the page: __ED.lab.play('name', ...args), __ED.lab.view({...}), __ED.lab.list()

import * as THREE from 'three';
import { createApp, ORDER } from './app.js';
import { DEG } from './math.js';

export async function createLab({ stage = true, view = {}, setup, scenarios = {} } = {}) {
  const ctx = createApp();
  const { scene, camera } = ctx;
  const lab = {
    ctx, scenarios,
    viewState: { target: [0, 1.2, 0], dist: 7, yaw: 0, pitch: 8, fov: 40, ...view },
    /** Orbit-style camera placement. yaw 0 = camera on +Z looking toward -Z (the fight camera side); degrees. */
    view(v = {}) {
      Object.assign(lab.viewState, v);
      const s = lab.viewState;
      const yaw = s.yaw * DEG, pitch = s.pitch * DEG;
      const t = new THREE.Vector3(...s.target);
      camera.position.set(t.x + Math.sin(yaw) * Math.cos(pitch) * s.dist, t.y + Math.sin(pitch) * s.dist, t.z + Math.cos(yaw) * Math.cos(pitch) * s.dist);
      camera.fov = s.fov;
      camera.updateProjectionMatrix();
      camera.lookAt(t);
    },
    play(name, ...args) {
      const fn = scenarios[name];
      if (!fn) throw new Error('no scenario: ' + name + ' (have: ' + Object.keys(scenarios).join(', ') + ')');
      return fn(ctx, lab, ...args);
    },
    list() { return Object.keys(scenarios); },
  };

  if (stage) {
    scene.background = new THREE.Color(0x05060a);
    scene.fog = new THREE.FogExp2(0x05060a, 0.018);
    const hemi = new THREE.HemisphereLight(0x8fa4c8, 0x1a1410, 0.55);
    const key = new THREE.DirectionalLight(0xfff0dc, 2.4);
    key.position.set(-4, 9, 6);
    key.castShadow = !!ctx.quality.shadows;
    if (key.castShadow) {
      key.shadow.mapSize.set(ctx.quality.shadowSize, ctx.quality.shadowSize);
      const c = key.shadow.camera;
      c.left = -9; c.right = 9; c.top = 8; c.bottom = -3; c.near = 1; c.far = 30;
      key.shadow.bias = -0.0004; key.shadow.normalBias = 0.02;
    }
    const rim = new THREE.DirectionalLight(0x6f9cff, 1.6);
    rim.position.set(5, 4, -7);
    const floor = new THREE.Mesh(new THREE.PlaneGeometry(80, 80), new THREE.MeshStandardMaterial({ color: 0x2a2c33, roughness: 0.62, metalness: 0.05 }));
    floor.rotation.x = -Math.PI / 2;
    floor.receiveShadow = true;
    const grid = new THREE.GridHelper(40, 40, 0x3a3e4a, 0x23262e);
    grid.position.y = 0.002;
    grid.material.transparent = true; grid.material.opacity = 0.35;
    scene.add(hemi, key, rim, floor, grid);
    lab.lights = { hemi, key, rim };
    lab.floor = floor;
  }
  lab.view();
  if (ctx.flags.view) {
    const p = String(ctx.flags.view).split(',').map(Number);
    lab.view({ target: [p[0], p[1], p[2]], dist: p[3], yaw: p[4], pitch: p[5], fov: p[6] || lab.viewState.fov });
  }
  window.__ED.lab = lab;

  if (setup) await setup(ctx, lab);

  if (!ctx.test) {
    // on-page scenario buttons + drag-to-orbit for manual viewing
    const bar = document.createElement('div');
    bar.style.cssText = 'position:absolute;left:8px;top:8px;display:flex;flex-wrap:wrap;gap:6px;max-width:70%;pointer-events:auto;z-index:5';
    for (const name of Object.keys(scenarios)) {
      const b = document.createElement('button');
      b.textContent = name;
      b.style.cssText = 'font:12px system-ui;padding:6px 10px;border-radius:6px;border:1px solid #444;background:#15171d;color:#ddd';
      b.onclick = () => lab.play(name);
      bar.appendChild(b);
    }
    document.getElementById('ui').appendChild(bar);
    let drag = null;
    ctx.canvas.addEventListener('pointerdown', (e) => { drag = { x: e.clientX, y: e.clientY, yaw: lab.viewState.yaw, pitch: lab.viewState.pitch }; });
    window.addEventListener('pointerup', () => { drag = null; });
    window.addEventListener('pointermove', (e) => { if (drag) lab.view({ yaw: drag.yaw - (e.clientX - drag.x) * 0.3, pitch: Math.max(-10, Math.min(85, drag.pitch + (e.clientY - drag.y) * 0.3)) }); });
    ctx.canvas.addEventListener('wheel', (e) => { lab.view({ dist: Math.max(1, lab.viewState.dist * (e.deltaY > 0 ? 1.1 : 0.9)) }); });
  }
  ctx.ready();
  ctx.start();
  return lab;
}

export { ORDER };
