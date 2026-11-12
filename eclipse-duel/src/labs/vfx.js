// VFX lab: one scenario per primitive plus composed demos. Every scenario takes an optional position [x, y, z].
//   node tools/shot.mjs vfx --do "__ED.lab.play('sparks')" --at 0.05,0.15,0.3,0.6 --sheet-only --out shots/vfx/sparks
import * as THREE from 'three';
import { createLab } from '../core/lab.js';
import { createVfx } from '../vfx/index.js';
import { LIB, PALETTE } from '../vfx/library.js';

const P = (p, d) => (p ? new THREE.Vector3(...p) : new THREE.Vector3(...d));

// primitive scenarios use the tuned library layers
const D = {
  sparks: LIB.sparks,
  embers: LIB.embers,
  smoke: { ...LIB.smoke, count: 10, delay: 0 },
  fire: LIB.fire,
  converge: LIB.chargeStreaks,
};

const V3 = (x, y, z) => new THREE.Vector3(x, y, z);

/** Composed demo presets: each is a layered effect built only from the public vfx API. */
function definePresets(ctx, lab, vfx) {
  const post = ctx.post;
  const rng = ctx.rng;
  const VOLT = PALETTE.volt;

  // ---- sword impact: flash, directional sparks, fine spray, embers, smoke, light, shock ring, ground dust ----------
  vfx.define('demo.swordImpact', (v, at) => {
    const p = at.pos, d = at.dir, s = at.scale;
    v.burst(LIB.flashCore, { pos: p, scale: s });
    v.flare({ kind: 'glow', pos: p, size: 0.8 * s, life: 0.07, attack: 0, color: [10, 7, 4] });
    v.flare({ kind: 'star', pos: p, size: 1.7 * s, life: 0.1, attack: 0, decay: 3, color: [7, 3.4, 1.1], rotation: rng() * 0.6 });
    v.flare({ kind: 'streak', pos: p, size: 0.3 * s, aspect: 12, life: 0.13, attack: 0, decay: 2.5, color: [6, 2.4, 0.5], dir: d });
    v.burst(LIB.splash, { pos: p, dir: d, scale: s });
    v.burst(LIB.sparks, { pos: p, dir: d, scale: s });
    v.burst(LIB.sparksFine, { pos: p, dir: d, scale: s });
    v.burst(LIB.glowPuff, { pos: p, scale: s });
    v.burst(LIB.embers, { pos: p, dir: d, scale: s });
    v.burst(LIB.smoke, { pos: p, dir: d, scale: s });
    v.light({ pos: p, color: PALETTE.ember.core, intensity: 140, range: 6, duration: 0.3 });
    v.schedule(0.05, (v2) => v2.distort({ kind: 'shock', pos: p, radius: [0.25, 1.7 * s], life: 0.38, strength: 0.05 }));
    v.schedule(0.034, (v2) => v2.burst(LIB.dustRing, { pos: [p.x, 0.02, p.z], scale: 0.55 * s, count: 9 }));
    post.pulse('chroma', 0.35, { release: 0.25 });
  });

  // ---- fire burst: flash, fireball body cooling to smoke, licks, sparks, embers, lingering smoke, ground glow -------
  vfx.define('demo.fireBurst', (v, at) => {
    const p = at.pos, s = at.scale;
    const g = V3(p.x, 0.02, p.z);
    v.burst(LIB.flashCore, { pos: p, scale: 1.7 * s });
    v.flare({ kind: 'flash', pos: p, size: 5 * s, life: 0.07, attack: 0, decay: 3, color: [3, 1.2, 0.3], intensity: 0.4 });
    v.flare({ kind: 'glow', pos: p, size: 1.6 * s, life: 0.06, attack: 0, color: [10, 6, 2.5] });
    v.light({ pos: [p.x, p.y + 0.4, p.z + 0.6], color: PALETTE.ember.core, intensity: 200, range: 10, duration: 0.9, flicker: 0.35, decay: 'outCubic' });
    v.burst({ ...LIB.fireball, count: 16, size: [0.9, 1.7, 1.3] }, { pos: p, dir: [0, 1, 0], scale: s });
    v.burst(LIB.fireLicks, { pos: p, dir: [0, 1, 0], scale: s });
    v.burst({ ...LIB.sparks, count: 70, spread: 180, emit: 'radial', speed: [4, 14, 1.4], life: [0.3, 1.1, 1.4] }, { pos: p, scale: s });
    v.burst({ ...LIB.embers, count: 46, life: [1.4, 3.2, 0.8], speed: [1, 5, 1.4], gravity: 1.3 }, { pos: p, scale: s });
    v.burst(LIB.smokeLinger, { pos: [p.x, p.y + 0.3, p.z], dir: [0, 1, 0], scale: s });
    v.burst({ ...LIB.dustRing, count: 16, speed: [3, 7] }, { pos: g, scale: s });
    v.burst({ tex: 'glow', blend: 'add', align: 'flat', count: 1, life: [1.6, 1.6], speed: 0, size: 3.4 * s, groundFade: 0, rotation: 0,
      color: [[0, 4, 1.2, 0.2, 1], [0.15, 2, 0.4, 0.04, 0.8], [1, 0.2, 0.02, 0, 0]] }, { pos: [g.x, 0.03, g.z], dir: [0, 1, 0] });
    v.burst(LIB.heatHaze, { pos: p, dir: [0, 1, 0], scale: s, count: 8, delay: 0.1 });
    v.schedule(0.06, (v2) => {
      v2.distort({ kind: 'shock', pos: p, radius: [0.5, 3.4 * s], life: 0.55, strength: 0.05 });
      v2.distort({ kind: 'shock', pos: g, normal: [0, 1, 0], radius: [0.6, 4.2 * s], life: 0.7, strength: 0.04 });
    });
    post.pulse('chroma', 0.5, { release: 0.3 });
    post.pulse('exposure', 0.25, { release: 0.35 });
  });

  // ---- charge-up that converges, then releases (volt palette: violet-white core, gold sparks) ---------------------
  vfx.define('demo.chargeRelease', (v, at, o) => {
    const p = at.pos, s = at.scale, T = o.charge != null ? o.charge : 1.2;
    const g = V3(p.x, 0.03, p.z);
    const streaks = v.emitter({ ...LIB.chargeStreaks, color: [[0, 0.3, 0.1, 0.8, 0], [0.25, 1.6, 0.8, 4, 1], [1, 7, 5, 12, 1]] }, { pos: p, scale: s });
    const motes = v.emitter({ ...LIB.chargeMotes, color: [[0, 0.5, 0.2, 1.2, 0], [0.3, 2, 1, 5, 1], [1, 6, 4, 10, 0.6]] }, { pos: p, scale: s });
    const sparkles = v.emitter({ ...LIB.chargeStreaks, rate: 40, size: [0.02, 0.04], shape: { type: 'sphere', radius: 0.9, inner: 0.5 }, color: [[0, 2, 1, 0.1, 0], [0.3, 8, 5, 1, 1], [1, 10, 7, 2, 1]] }, { pos: p, scale: s });
    v.flare({ kind: 'glow', pos: p, size: [0.15 * s, 1.1 * s], life: T + 0.04, attack: T * 0.92, decay: 6, color: [5, 3.5, 9] });
    v.flare({ kind: 'star', pos: p, size: 1.3 * s, life: T + 0.04, attack: T, decay: 6, color: [3, 2, 6], rotation: 0.3 });
    v.distort({ kind: 'lens', pos: p, radius: 1.0 * s, strength: -0.05, life: T + 0.05, attack: T * 0.85, decay: 6 });
    v.burst({ tex: 'rune3', blend: 'add', align: 'flat', count: 1, life: [T + 0.5, T + 0.5], speed: 0, size: 3.0 * s, spin: [0.9, 0.9], spinBoth: false, groundFade: 0,
      sizeOverLife: [[0, 0.6], [0.25, 1], [1, 1.05]], color: [[0, 0.4, 0.2, 1.6, 0], [0.2, 0.7, 0.4, 2.6, 0.85], [0.7, 1.2, 0.75, 4, 1], [0.78, 2.4, 1.6, 6, 1], [1, 0.3, 0.1, 1, 0]] }, { pos: g, dir: [0, 1, 0] });
    v.light({ pos: [p.x, p.y, p.z + 0.4], color: VOLT.core, intensity: 90, range: 6, duration: T, curve: [[0, 0], [0.85, 1], [1, 1]], flicker: 0.25 });
    v.schedule(T, (v2) => {
      streaks.stop(); motes.stop(); sparkles.stop();
      v2.burst({ ...LIB.flashCore, color: [[0, 10, 9, 14, 1], [0.3, 4, 2.6, 9, 0.75], [1, 0.4, 0.2, 1.4, 0]] }, { pos: p, scale: 1.1 * s });
      v2.flare({ kind: 'glow', pos: p, size: 1.0 * s, life: 0.07, attack: 0, color: [9, 7, 14] });
      v2.flare({ kind: 'streak', pos: p, size: 0.28 * s, aspect: 18, life: 0.16, attack: 0, decay: 3, color: [4, 2.8, 8] });
      v2.flare({ kind: 'ring', pos: p, size: [0.4, 2.6 * s], life: 0.17, attack: 0, decay: 2, color: [0.8, 0.55, 1.8] });
      v2.burst({ ...LIB.sparks, count: 90, spread: 180, emit: 'radial', speed: [5, 18, 1.4], color: [[0, 12, 10, 6, 1], [0.15, ...VOLT.spark, 1], [0.6, 2.5, 1.2, 0.15, 1], [1, 0.4, 0.15, 0, 0]] }, { pos: p, scale: s });
      v2.burst({ tex: 'arc', blend: 'add', count: 14, life: [0.08, 0.2], shape: { type: 'sphere', radius: 0.3 }, emit: 'radial', spread: 10, speed: [8, 14], size: [0.5, 1.1], aspect: 2.2,
        align: 'velocity', stretch: 0.01, rotation: 0, flicker: { amount: 0.7, rate: 40 }, groundFade: 0, color: [[0, 8, 6, 14, 1], [1, 2, 1, 6, 0]] }, { pos: p, scale: s });
      v2.burst({ ...LIB.glitter, count: 40, color: [[0, 6, 5, 10, 0], [0.1, 6, 5, 10, 1], [1, 2, 1.5, 4, 0]] }, { pos: p, scale: 1.6 * s });
      v2.burst({ ...LIB.smoke, count: 8, size: [0.8, 1.5], speed: [1.5, 4], emit: 'radial', shape: { type: 'sphere', radius: 0.3 }, color: [[0, 0.3, 0.2, 0.6, 0], [0.08, 0.07, 0.05, 0.12, 0.6], [1, 0.04, 0.04, 0.06, 0]] }, { pos: p, scale: s });
      v2.burst({ ...LIB.dustRing, count: 14 }, { pos: g, scale: s });
      v2.light({ pos: p, color: VOLT.core, intensity: 160, range: 9, duration: 0.4 });
      v2.distort({ kind: 'shock', pos: p, radius: [0.3, 3 * s], life: 0.5, strength: 0.05 });
      v2.distort({ kind: 'shock', pos: g, normal: [0, 1, 0], radius: [0.3, 4 * s], life: 0.6, strength: 0.04 });
      post.pulse('chroma', 0.7, { release: 0.3 });
      post.pulse('radial', 0.35, { release: 0.3 });
    });
  });

  // ---- frost hit (README worked example 1): library layers recoloured with the frost palette -----------------------
  const F = vfx.palette.frost;
  const iceSparks = { ...vfx.lib.sparks, color: vfx.util.heatRamp(F.core, F.mid, F.tail), gravity: -6 };
  const shards = { tex: 'shard', blend: 'add', count: 14, life: [0.4, 0.9], spread: 40, speed: [3, 9], size: [0.08, 0.2, 2],
    spin: [4, 12], gravity: -9, collide: 'ground', erode: 'erodeLate', erodeChannel: 'cracks', color: vfx.util.heatRamp(F.core, F.mid, F.tail) };
  vfx.define('frost.hit', (v, at) => {
    v.burst(vfx.lib.flashCore, { pos: at.pos, color: [0.5, 0.9, 1.6] });
    v.burst(iceSparks, { pos: at.pos, dir: at.dir });
    v.burst(shards, { pos: at.pos, dir: at.dir, scale: at.scale });
    v.burst({ ...vfx.lib.glitter, color: [[0, 3, 6, 9, 0], [0.1, 3, 6, 9, 1], [1, 1, 2, 3, 0]] }, { pos: at.pos });
    v.light({ pos: at.pos, color: F.core, intensity: 120, duration: 0.3 });
    v.schedule(0.05, (v2) => v2.distort({ kind: 'shock', pos: at.pos, radius: [0.2, 1.4] }));
  });

  // ---- swing trail with ember spray off the tip and a refraction twin --------------------------------------------
  vfx.define('demo.swingTrail', (v) => {
    const r = lab.rig;
    const tr = lab.play('trail', { distort: 0.025 });
    const em = v.emitter({ ...LIB.embers, count: undefined, rate: 0, perMeter: 22, delay: 0, speed: [0.2, 1.2], life: [0.4, 1.2], inherit: 0.12, spread: 180, emit: 'random' }, { pos: [0, 0, 0] }).follow(r.tip);
    const sp = v.emitter({ ...LIB.sparksFine, count: undefined, rate: 0, perMeter: 14, life: [0.1, 0.35], inherit: 0.35, spread: 180, emit: 'random' }, { pos: [0, 0, 0] }).follow(r.tip);
    v.schedule(0.5, () => { tr.stop(); em.stop(); sp.stop(); });
  });
}

/**
 * Afterimage test subject: a skinned body (3 bones, smooth weights) with a rigid head and blade parented to the top
 * bone, so ghosts of both SkinnedMesh and plain Mesh children are exercised. play(t) poses it along a dash.
 */
function makeFigure(ctx) {
  const geo = new THREE.CylinderGeometry(0.2, 0.27, 1.3, 18, 16, false);
  geo.translate(0, 0.65, 0);
  const p = geo.getAttribute('position');
  const si = [], sw = [];
  for (let i = 0; i < p.count; i++) {
    const y = p.getY(i) / 0.5;
    const b = Math.min(1, Math.floor(y)), w = Math.min(1, Math.max(0, y - b));
    si.push(b, Math.min(2, b + 1), 0, 0); sw.push(1 - w, w, 0, 0);
  }
  geo.setAttribute('skinIndex', new THREE.Uint16BufferAttribute(si, 4));
  geo.setAttribute('skinWeight', new THREE.Float32BufferAttribute(sw, 4));
  const metal = new THREE.MeshStandardMaterial({ color: 0x6d7380, metalness: 0.85, roughness: 0.35 });
  const body = new THREE.SkinnedMesh(geo, metal);
  const b0 = new THREE.Bone(), b1 = new THREE.Bone(), b2 = new THREE.Bone();
  b1.position.y = 0.5; b2.position.y = 0.5;
  b0.add(b1); b1.add(b2);
  body.add(b0);
  body.bind(new THREE.Skeleton([b0, b1, b2]));
  const head = new THREE.Mesh(new THREE.SphereGeometry(0.17, 16, 12), metal);
  head.position.y = 0.48;
  const blade = new THREE.Mesh(new THREE.BoxGeometry(0.06, 1.1, 0.02), new THREE.MeshStandardMaterial({ color: 0x9aa0aa, metalness: 0.9, roughness: 0.3 }));
  blade.position.set(0.32, 0.25, 0.1); blade.rotation.z = -0.9;
  b2.add(head, blade);
  const root = new THREE.Group();
  root.add(body);
  root.visible = false;
  ctx.scene.add(root);
  return {
    root, bones: [b0, b1, b2],
    /** pose at dash time t (0..1): run from x = -3 to x = 3, leaning into the dash, blade sweeping */
    play(t) {
      const e = t < 1 ? 1 - Math.pow(1 - t, 3) : 1;
      root.position.set(-3 + 6 * e, 0, 0);
      const lean = Math.sin(Math.min(1, t) * Math.PI) * 0.5;
      b1.rotation.z = -lean * 0.6; b2.rotation.z = -lean * 0.5; b2.rotation.y = t * 2.2;
    },
  };
}

createLab({
  view: { target: [0, 1.0, 0], dist: 7, yaw: 0, pitch: 8 },
  setup(ctx, lab) {
    const vfx = createVfx(ctx);
    lab.vfx = vfx;
    lab.D = D;
    // dim backdrop wall with a stone-block pattern: something for refraction to bend and smoke to read against
    const cv = document.createElement('canvas');
    cv.width = cv.height = 256;
    const g = cv.getContext('2d');
    g.fillStyle = '#1a1c22'; g.fillRect(0, 0, 256, 256);
    g.strokeStyle = '#2c303a'; g.lineWidth = 3;
    for (let y = 0; y < 256; y += 32) { g.beginPath(); g.moveTo(0, y); g.lineTo(256, y); g.stroke(); for (let x = (y / 32) % 2 ? 0 : 32; x < 256; x += 64) { g.beginPath(); g.moveTo(x, y); g.lineTo(x, y + 32); g.stroke(); } }
    const tex = new THREE.CanvasTexture(cv);
    tex.colorSpace = THREE.SRGBColorSpace; tex.wrapS = tex.wrapT = THREE.RepeatWrapping; tex.repeat.set(6, 2);
    const wall = new THREE.Mesh(new THREE.PlaneGeometry(30, 10), new THREE.MeshStandardMaterial({ map: tex, roughness: 0.9 }));
    wall.position.set(0, 5, -5);
    ctx.scene.add(wall);
    // swinging weapon rig: pivot at shoulder height, blade from 0.25 m to 1.45 m along the arm
    const pivot = new THREE.Group();
    pivot.position.set(-0.2, 1.3, 0.3);
    const blade = new THREE.Mesh(new THREE.BoxGeometry(1.2, 0.07, 0.02), new THREE.MeshStandardMaterial({ color: 0x9aa0aa, metalness: 0.9, roughness: 0.3 }));
    blade.position.x = 0.85;
    const base = new THREE.Object3D(); base.position.x = 0.25;
    const tip = new THREE.Object3D(); tip.position.x = 1.45;
    pivot.add(blade, base, tip);
    pivot.visible = false;
    ctx.scene.add(pivot);
    lab.rig = { pivot, base, tip, t: 1e9, keys: null };
    ctx.onUpdate((dt) => {
      const r = lab.rig;
      if (!r.keys) return;
      r.t += dt;
      const k = r.keys;
      let i = 1;
      while (i < k.length - 1 && k[i][0] < r.t) i++;
      const a = k[i - 1], b = k[i];
      const u = Math.min(1, Math.max(0, (r.t - a[0]) / (b[0] - a[0])));
      const e = b[2] ? b[2](u) : u;
      pivot.rotation.z = (a[1] + (b[1] - a[1]) * e) * Math.PI / 180;
      pivot.rotation.y = (a[3] || 0) + ((b[3] || 0) - (a[3] || 0)) * e;
    }, ctx.ORDER.CHAR);
    lab.figure = makeFigure(ctx);
    definePresets(ctx, lab, vfx);
    vfx.prewarm();
  },
  scenarios: {
    atlas(ctx, lab, which = 'atlas', mode = 0) {
      const t = ctx.vfx.textures[which];
      const m = new THREE.Mesh(new THREE.PlaneGeometry(2, 2), new THREE.ShaderMaterial({
        depthTest: false, depthWrite: false, transparent: true, uniforms: { t: { value: t }, mode: { value: mode }, asp: { value: ctx.viewport.aspect } },
        vertexShader: 'varying vec2 vUv; uniform float asp; void main(){ vUv = uv; gl_Position = vec4(position.x / asp, position.y, 0.0, 1.0); }',
        fragmentShader: `uniform sampler2D t; uniform int mode; varying vec2 vUv; void main(){ vec4 s = texture2D(t, vUv);
          vec3 bg = vec3(mod(floor(vUv.x*64.0)+floor(vUv.y*64.0), 2.0) > 0.5 ? 0.02 : 0.035);
          vec3 col;
          if (mode == 0) { vec3 hot = vec3(0.95 + 0.05*s.g, 0.4 + 0.6*s.g, 0.12 + 0.88*s.g*s.g); col = mix(bg, hot * s.r, s.a); }
          else if (mode == 1) col = vec3(s.a);
          else if (mode == 2) col = s.rgb * s.a;
          else col = s.rgb;
          gl_FragColor = vec4(col * 0.75, 1.0); }`,
      }));
      m.frustumCulled = false; m.renderOrder = 999;
      ctx.scene.add(m);
    },
    gallery(ctx, lab, which = 'all') {
      // every sprite as a static particle: additive ones lit warm, alpha ones as grey matter against the wall
      const sp = ctx.vfx.textures.sprites;
      const alphaSet = new Set(['smoke1', 'smoke2', 'smoke3', 'smoke4', 'dust', 'pebble1', 'pebble2', 'pebble3', 'ash1', 'ash2', 'petal', 'shard1', 'shard2', 'shard3']);
      const names = Object.keys(sp).filter((n) => sp[n].frames === 1 && (which === 'all' || (which === 'alpha') === alphaSet.has(n)));
      const cols = which === 'all' ? 10 : 7;
      names.forEach((n, i) => {
        const a = alphaSet.has(n);
        const big = n.startsWith('smoke') || n.startsWith('flame') || n === 'burst';
        const def = { tex: n, blend: a ? 'alpha' : 'add', count: 1, life: 1e4, speed: 0, size: (big ? 1.1 : 0.62) * (which === 'all' ? 1 : 1.5), rotation: 0, groundFade: 0,
          color: a ? [0.32, 0.3, 0.28] : [3, 1.4, 0.45], heat: a ? 0 : 0.0 };
        if (!a) def.color = [[0, 3, 1.3, 0.4, 1], [1, 3, 1.3, 0.4, 1]];
        const x = ((i % cols) - (cols - 1) / 2) * (which === 'all' ? 0.85 : 1.2), y = 2.5 - Math.floor(i / cols) * (which === 'all' ? 0.8 : 1.15);
        ctx.vfx.burst(def, { pos: [x, y, 0], color: a ? null : [1, 1, 1] });
      });
    },
    sparks(ctx, lab, p) { return ctx.vfx.burst(D.sparks, { pos: P(p, [0, 1.2, 0]), dir: [0.6, 0.5, 0.3] }); },
    embers(ctx, lab, p) { return ctx.vfx.burst(D.embers, { pos: P(p, [0, 0.8, 0]) }); },
    smoke(ctx, lab, p) { return ctx.vfx.burst(D.smoke, { pos: P(p, [0, 0.6, 0]) }); },
    fire(ctx, lab, p) {
      // standing fire: flames + rising smoke + embers + a flickering light, all following one point
      const at = { pos: P(p, [0, 0.02, 0]) };
      const v = ctx.vfx;
      return [
        v.emitter(D.fire, at),
        v.emitter({ ...LIB.smokeLinger, rate: 5, delay: 0, size: [0.7, 1.4], life: [1.6, 2.6], speed: [0.6, 1.2], shape: { type: 'disc', radius: 0.25 }, emit: 'axis', spread: 10 }, { pos: at.pos.clone().setY(0.7) }),
        v.emitter({ ...LIB.embers, rate: 12, delay: 0, speed: [0.5, 2] }, { pos: at.pos.clone().setY(0.5) }),
        v.light({ pos: at.pos.clone().setY(0.6), color: PALETTE.ember.core, intensity: 25, range: 5, duration: Infinity, flicker: 0.4, flickerRate: 9 }),
      ];
    },
    converge(ctx, lab, p) { return ctx.vfx.emitter(D.converge, { pos: P(p, [0, 1.2, 0]) }); },
    trail(ctx, lab, opts = {}) {
      const r = lab.rig;
      r.pivot.visible = true;
      // anticipation (slow wind-up), smear (fast arc), follow-through, settle
      const inQ = (u) => u * u, outQ = (u) => 1 - (1 - u) * (1 - u), outE = (u) => 1 - Math.pow(2, -8 * u);
      r.keys = [[0, 150, null, 0], [0.22, 165, outQ, -0.2], [0.36, -40, inQ, 0.25], [0.5, -95, outE, 0.35], [0.9, -100, outQ, 0.3]];
      r.t = 0;
      r.pivot.rotation.set(0, 0, 150 * Math.PI / 180);
      r.pivot.updateMatrixWorld(true);
      return ctx.vfx.trail({ a: r.base, b: r.tip, ...opts });
    },
    ribbon(ctx, lab) {
      const o = new THREE.Object3D();
      ctx.scene.add(o);
      let t = 0;
      const off = ctx.onUpdate((dt) => { t += dt; o.position.set(-4 + t * 7, 1.3 + Math.sin(t * 6) * 0.35, Math.cos(t * 4) * 0.4); if (t > 1.3) off(); }, ctx.ORDER.CHAR);
      o.position.set(-4, 1.3, 0.4);
      ctx.vfx.ribbon({ follow: o, width: 0.22, life: 0.5 });
      ctx.vfx.emitter({ ...D.embers, rate: 60, delay: 0, speed: [0.1, 0.6], life: [0.3, 0.9] }, { pos: o.position }).follow(o);
      return o;
    },
    flare(ctx, lab) {
      const kinds = ['glow', 'star', 'streak', 'ring', 'flash'];
      kinds.forEach((k, i) => ctx.vfx.flare({ kind: k, pos: [-3 + i * 1.5, 1.3, 0], size: k === 'streak' ? 0.5 : k === 'ring' ? [0.3, 1.2] : k === 'flash' ? 2.5 : 0.9, life: 1.2, color: [5, 3, 1.5], intensity: k === 'flash' ? 0.3 : 1 }));
    },
    distort(ctx, lab) {
      ctx.vfx.distort({ kind: 'shock', pos: [-2.5, 1.3, 0], radius: [0.2, 2.2], life: 0.8 });
      ctx.vfx.distort({ kind: 'shock', pos: [0, 0.02, 0], normal: [0, 1, 0], radius: [0.3, 3], life: 0.8 });
      ctx.vfx.distort({ kind: 'heat', pos: [2.2, 1.0, 0], radius: 1.0, life: 2 });
      ctx.vfx.distort({ kind: 'lens', pos: [0, 2.6, -1], radius: 1.0, strength: 0.06, life: 2 });
    },
    light(ctx, lab, p) {
      ctx.vfx.light({ pos: P(p, [0, 0.6, 0.5]), color: [8, 3, 0.6], intensity: 120, range: 7, duration: 1.2 });
      ctx.vfx.flare({ kind: 'glow', pos: P(p, [0, 0.6, 0.5]), size: 0.8, life: 1.2, color: [8, 3, 0.6] });
    },
    schedule(ctx, lab) {
      for (let i = 0; i < 5; i++) ctx.vfx.schedule(i * 0.15, (v) => v.burst(D.sparks, { pos: [-2 + i, 1.2, 0], dir: [0, 1, 0], count: 30 }));
    },
    swordImpact(ctx, lab, p, d) { return ctx.vfx.play('demo.swordImpact', { pos: P(p, [0, 1.35, 0]), dir: d || [0.85, -0.35, 0.4] }); },
    fireBurst(ctx, lab, p) { return ctx.vfx.play('demo.fireBurst', { pos: P(p, [0, 0.9, 0]) }); },
    chargeRelease(ctx, lab, p, charge) { return ctx.vfx.play('demo.chargeRelease', { pos: P(p, [0, 1.4, 0]) }, { charge }); },
    swingTrail(ctx) { return ctx.vfx.play('demo.swingTrail'); },
    frostHit(ctx, lab, p, d) { return ctx.vfx.play('frost.hit', { pos: P(p, [0, 1.35, 0]), dir: d || [-1, 0.2, 0.3] }); },
    // ---- mesh effects (stage 2) ---------------------------------------------------------------------------------
    slash(ctx, lab, look = 'razor', o = {}) {
      return ctx.vfx.slash({ look, pos: [0, 1.25, 0], normal: [0, 0.28, 1], forward: [1, 0, 0], arc: [150, -25], radius: 1.5, distort: 0.02, ...o });
    },
    slashes(ctx, lab, o = {}) {
      const looks = ['razor', 'flame', 'ice', 'electric', 'eclipse'];
      looks.forEach((look, i) => ctx.vfx.slash({ look, pos: [-4 + i * 2, 1.2, 0], normal: [0, 0.25, 1], arc: [150, -25], radius: 0.85, width: 0.32, ...o }));
    },
    slashWave(ctx, lab, look = 'flame') {
      // a crescent projectile: sweeps, then flies forward and grows
      return ctx.vfx.slash({ look, pos: [-3, 1.0, 0], normal: [0, 0, 1], forward: [1, 0, 0], arc: [-70, 70], radius: 0.9, width: 0.45, speed: 9, expand: 0.6, drag: 1.2, life: 0.9, sweep: 0.05, distort: 0.03 });
    },
    ring(ctx, lab, look = 'shock', o = {}) {
      return ctx.vfx.ring({ look, pos: [0, 0, 0], distort: look === 'dust' ? 0 : 0.035, ...o });
    },
    rings(ctx, lab, o = {}) {
      ['shock', 'dust', 'fire', 'frost', 'volt'].forEach((look, i) => ctx.vfx.ring({ look, pos: [-5 + i * 2.5, 0, 0], scale: 0.42, ...o }));
    },
    ringsAir(ctx) {
      // camera-facing and tilted rings in the air
      ctx.vfx.ring({ look: 'shock', orient: 'camera', pos: [-2.2, 1.4, 0], radius: [0.1, 1.6], width: [0.25, 0.5] });
      ctx.vfx.ring({ look: 'volt', normal: [1, 0.3, 0.2], pos: [0, 1.4, 0], radius: [0.1, 1.4], width: [0.2, 0.4] });
      ctx.vfx.ring({ look: 'frost', normal: [0.2, 0.4, 1], pos: [2.2, 1.4, 0], radius: [0.1, 1.4], width: [0.3, 0.6] });
    },
    pillar(ctx, lab, look = 'fire', o = {}) { return ctx.vfx.pillar({ look, pos: [0, 0, 0], ...o }); },
    pillars(ctx, lab, o = {}) {
      ['fire', 'frost', 'volt', 'eclipse'].forEach((look, i) => ctx.vfx.pillar({ look, pos: [-3.6 + i * 2.4, 0, 0], scale: 0.6, ...o }));
    },
    beams(ctx, lab, o = {}) {
      // every look, each released after 0.9 s (stop())
      const hs = ['energy', 'fire', 'frost', 'volt', 'eclipse'].map((look, i) => ctx.vfx.beam({ look, from: [-3.6, 0.5 + i * 0.55, 0], to: [3.6, 0.4 + i * 0.6, -0.5], ...o }));
      ctx.vfx.schedule(0.9, () => hs.forEach((h) => h.stop()));
      return hs;
    },
    beam(ctx, lab, look = 'energy', o = {}) {
      // a beam whose impact end sweeps (setEnds every frame), released after 1.2 s
      const h = ctx.vfx.beam({ look, from: [-3, 1.3, 0], to: [3, 1.0, 0], ...o });
      let t = 0;
      const off = ctx.onUpdate((dt) => { t += dt; h.setEnds(null, [2.5 + Math.sin(t * 2) * 0.8, 0.8 + Math.sin(t * 3.1) * 0.6, Math.cos(t * 2) * 0.6]); if (t > 1.6) off(); }, ctx.ORDER.GAME);
      ctx.vfx.schedule(1.2, () => h.stop());
      return h;
    },
    bolt(ctx, lab, o = {}) {
      // sky strike onto the floor, lighting the stage
      return ctx.vfx.bolt({ from: [-0.8, 6.5, -1.5], to: [0.3, 0, 0], width: 0.34, light: 160, ...o });
    },
    bolts(ctx, lab) {
      // palettes side by side, horizontal arcs between two points, and a long crackling arc
      ctx.vfx.bolt({ from: [-4.5, 5.5, -1], to: [-3, 0, 0], palette: 'volt' });
      ctx.vfx.bolt({ from: [-1.5, 5.5, -1], to: [-0.6, 0, 0], palette: 'frost', branches: 7 });
      ctx.vfx.bolt({ from: [1.2, 5.5, -1], to: [1.6, 0, 0], palette: 'ember', roughness: 0.32 });
      ctx.vfx.bolt({ from: [2.6, 1.6, 0], to: [4.6, 0.9, 0], width: 0.18, branches: 2, strikes: 14, interval: [0.03, 0.06], life: 0.8, leader: 0, detail: 6 });
    },
    decal(ctx, lab, kind = 'crack', o = {}) { return ctx.vfx.decal({ kind, pos: [0, 0, 0], ...o }); },
    decals(ctx, lab) {
      // every kind (cracks twice: dry and with cooling magma)
      ctx.vfx.decal({ kind: 'crack', pos: [-4.4, 0, 0], radius: 1.5, life: 5 });
      ctx.vfx.decal({ kind: 'crack', pos: [-1.6, 0, 0], radius: 1.5, magma: 1, life: 5 });
      ctx.vfx.decal({ kind: 'scorch', pos: [1.1, 0, 0], radius: 1.3, life: 5 });
      ctx.vfx.decal({ kind: 'frost', pos: [3.9, 0, 0], radius: 1.5, life: 5 });
      ctx.vfx.decal({ kind: 'rune', pos: [-2.9, 0, -3.2], radius: 1.5, life: 5, palette: 'volt' });
      ctx.vfx.decal({ kind: 'rune', pos: [0.6, 0, -3.2], radius: 1.5, life: 5 });
      ctx.vfx.decal({ kind: 'glow', pos: [3.6, 0, -3.2], radius: 1.4, life: 5 });
    },
    debris(ctx, lab, kind = 'rock', o = {}) { return ctx.vfx.debris({ kind, pos: [0, 0.1, 0], count: 22, ...o }); },
    debrisAll(ctx) {
      ['rock', 'ember', 'ice', 'crystal'].forEach((kind, i) => ctx.vfx.debris({ kind, pos: [-3.6 + i * 2.4, 0.1, 0], count: 18, speed: [2.5, 6.5, 1.3] }));
      ctx.vfx.light({ pos: [-1.2, 1.2, 1.2], color: [8, 3, 0.6], intensity: 30, range: 6, duration: 2 });
    },
    spikes(ctx, lab, kind = 'ice', pattern = 'line', o = {}) {
      return ctx.vfx.spikes({ kind, pattern, pos: pattern === 'line' ? [-2.5, 0, 0] : [0, 0, 0], dir: [1, 0, 0.15], ...o });
    },
    spikesAll(ctx) {
      // a line of ice, a cluster of crystal, a ring of rock, a magma cluster; a light so the facets read
      ctx.vfx.spikes({ kind: 'ice', pattern: 'line', pos: [-4.6, 0, 0.6], dir: [1, 0, 0.1], length: 3.2, count: 6 });
      ctx.vfx.spikes({ kind: 'crystal', pattern: 'cluster', pos: [0.6, 0, 0.3], count: 7 });
      ctx.vfx.spikes({ kind: 'rock', pattern: 'ring', pos: [3.6, 0, -0.4], radius: 1.0, count: 9, height: [0.5, 1.0] });
      ctx.vfx.spikes({ kind: 'magma', pattern: 'cluster', pos: [-1.6, 0, -2.2], count: 6, height: [0.6, 1.3] });
      ctx.vfx.light({ pos: [-2, 2.2, 2.2], color: [6, 5, 4], intensity: 40, range: 10, duration: 3 });
    },
    speedlines(ctx, lab, mode = 'focus', o = {}) {
      return ctx.vfx.speedlines({ mode, life: 0.8, ...o });
    },
    speedlinesAll(ctx, lab, which = 0) {
      // 0 focus on a world point (tracks it), 1 directional, 2 ink focus
      if (which === 0) return ctx.vfx.speedlines({ pos: [1.2, 1.4, 0], life: 0.8, inner: 0.45 });
      if (which === 1) return ctx.vfx.speedlines({ mode: 'directional', dir: [1, -0.15], life: 0.8 });
      return ctx.vfx.speedlines({ style: 'ink', life: 0.8, density: 90, inner: 0.6 });
    },
    afterimage(ctx, lab, o = {}) {
      // the skinned figure dashes; ghosts every 50 ms (game time: hit-stop freezes them too)
      const fig = lab.figure;
      fig.root.visible = true;
      let t = 0;
      fig.play(0);
      const off = ctx.onUpdate((dt) => { t += dt / 0.55; fig.play(t); if (t > 1.6) off(); }, ctx.ORDER.CHAR);
      return ctx.vfx.afterimage(fig.root, { count: 9, interval: 0.05, life: 0.42, drift: [0, 0.15, 0], ...o });
    },
    slowmo(ctx, lab, s = 0.2, d = 2) { ctx.time.slowmo(s, d, { easeIn: 0, easeOut: 0 }); },
    hitstop(ctx, lab, d = 0.3) { ctx.time.hitstop(d); },
    clear(ctx) { ctx.vfx.clear(); },
  },
});
