import * as THREE from 'three';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { ShaderPass } from 'three/addons/postprocessing/ShaderPass.js';
import { makeTextures } from './textures.js';
import { createMaterials, viewWeapon, Soldier } from './models.js';
import { buildWorld } from './world.js';
import {
  ARENA, BOXES, PLAYER, WEAPONS, PRIMARIES, PISTOL, RANGE,
  raycastMap, rayAABB, playerHitboxes, collideBox,
} from './shared/map.js';

const $ = (id) => document.getElementById(id);
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const lerp = (a, b, t) => a + (b - a) * t;
const damp = (a, b, k, dt) => lerp(a, b, 1 - Math.exp(-k * dt));

const settings = { sens: 1, vol: 0.6, primary: 0, quality: 'high' };
try { Object.assign(settings, JSON.parse(localStorage.getItem('sz-settings') || '{}')); } catch {}
if (!PRIMARIES.includes(settings.primary)) settings.primary = 0;
const saveSettings = () => { try { localStorage.setItem('sz-settings', JSON.stringify(settings)); } catch {} };

// =====================================================================
// Renderer / scene / post-processing
// =====================================================================
const renderer = new THREE.WebGLRenderer({ antialias: true, powerPreference: 'high-performance' });
const pixelRatio = () => Math.min(devicePixelRatio, settings.quality === 'low' ? 1 : 2);
renderer.setPixelRatio(pixelRatio());
renderer.setSize(innerWidth, innerHeight);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.0;
renderer.autoClear = false;
document.body.prepend(renderer.domElement);

const envTex = new THREE.PMREMGenerator(renderer).fromScene(new RoomEnvironment(), 0.04).texture;
const T = makeTextures();
const M = createMaterials(T);

const scene = new THREE.Scene();
scene.environment = envTex;
const world = buildWorld(scene, T, M, { shadowSize: settings.quality === 'low' ? 1024 : 2048 });

const BASE_FOV = 78;
const camera = new THREE.PerspectiveCamera(BASE_FOV, innerWidth / innerHeight, 0.05, 500);
camera.rotation.order = 'YXZ';

// First-person weapon scene: rendered on top so the gun never clips into walls.
const vmScene = new THREE.Scene();
vmScene.environment = envTex;
const vmCam = new THREE.PerspectiveCamera(60, innerWidth / innerHeight, 0.01, 10);
vmScene.add(new THREE.HemisphereLight(0xe8f0ff, 0x4a4036, 0.7));
{
  const l = new THREE.DirectionalLight(0xfff0d8, 2.2);
  l.position.set(0.6, 1.5, 0.8);
  vmScene.add(l);
  const rim = new THREE.DirectionalLight(0xbcd4ff, 0.8);
  rim.position.set(-1, 0.5, -1);
  vmScene.add(rim);
}

const composer = new EffectComposer(renderer, new THREE.WebGLRenderTarget(innerWidth, innerHeight, { type: THREE.HalfFloatType, samples: 4 }));
composer.setPixelRatio(pixelRatio());
composer.setSize(innerWidth, innerHeight);
composer.addPass(new RenderPass(scene, camera));
const vmPass = new RenderPass(vmScene, vmCam);
vmPass.clear = false;
vmPass.clearDepth = true;
composer.addPass(vmPass);
const bloom = new UnrealBloomPass(new THREE.Vector2(innerWidth, innerHeight), 0.32, 0.45, 0.92);
composer.addPass(bloom);
composer.addPass(new OutputPass());
// Final grade: vignette, slight contrast and fine grain.
const grade = new ShaderPass({
  uniforms: { tDiffuse: { value: null }, time: { value: 0 }, hurt: { value: 0 } },
  vertexShader: `varying vec2 vUv; void main() { vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }`,
  fragmentShader: `uniform sampler2D tDiffuse; uniform float time; uniform float hurt; varying vec2 vUv;
    void main() {
      vec4 c = texture2D(tDiffuse, vUv);
      c.rgb = mix(c.rgb, smoothstep(0.0, 1.0, c.rgb), 0.18);
      float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
      c.rgb = mix(vec3(l), c.rgb, 1.06 - hurt * 0.6);
      vec2 d = vUv - 0.5;
      c.rgb *= 1.0 - dot(d, d) * 0.55;
      c.rgb += (fract(sin(dot(vUv * (time + 1.0), vec2(12.9898, 78.233))) * 43758.5453) - 0.5) * 0.018;
      gl_FragColor = c;
    }`,
});
composer.addPass(grade);

// =====================================================================
// Effects: tracers, impacts, particles
// =====================================================================
const fx = { tracers: [], decals: [], particles: [], puffs: [], casings: [] };
const tracerGeo = new THREE.BoxGeometry(0.025, 0.025, 1).translate(0, 0, 0.5);
const decalGeo = new THREE.CircleGeometry(0.07, 10);
const decalMat = new THREE.MeshBasicMaterial({ color: 0x15130f, transparent: true, opacity: 0.85, depthWrite: false,
  polygonOffset: true, polygonOffsetFactor: -4 });
const sparkGeo = new THREE.BoxGeometry(0.035, 0.035, 0.035);

function spawnTracer(from, to, color = 0xffe7a0, width = 1) {
  const len = from.distanceTo(to);
  if (len < 0.5) return;
  const m = new THREE.Mesh(tracerGeo, new THREE.MeshBasicMaterial({
    color, transparent: true, opacity: 0.7, blending: THREE.AdditiveBlending, depthWrite: false }));
  m.position.copy(from);
  m.lookAt(to);
  m.scale.set(width, width, len);
  scene.add(m);
  const life = width > 1 ? 0.18 : 0.06;
  fx.tracers.push({ m, life, max: life });
}

function spawnImpact(point, normal, blood) {
  if (!blood && normal) {
    const d = new THREE.Mesh(decalGeo, decalMat);
    const n = new THREE.Vector3(...normal);
    d.position.copy(point).addScaledVector(n, 0.012);
    d.lookAt(d.position.clone().add(n));
    d.rotation.z = Math.random() * 6;
    scene.add(d);
    fx.decals.push(d);
    if (fx.decals.length > 150) scene.remove(fx.decals.shift());
  }
  for (let i = 0; i < (blood ? 2 : 3); i++) {
    const sp = new THREE.Sprite(new THREE.SpriteMaterial({
      map: T.puff, color: blood ? 0x8a0f14 : 0xb8b0a2, transparent: true, depthWrite: false, opacity: blood ? 0.8 : 0.55 }));
    sp.position.copy(point);
    const v = new THREE.Vector3((Math.random() - 0.5) * 0.6, 0.4 + Math.random() * 0.5, (Math.random() - 0.5) * 0.6);
    if (normal) v.addScaledVector(new THREE.Vector3(...normal), 0.9);
    sp.scale.setScalar(0.15);
    scene.add(sp);
    fx.puffs.push({ m: sp, v, life: 0.7 + Math.random() * 0.5, max: 1.2, grow: blood ? 1.2 : 1.8, base: sp.material.opacity });
  }
  const count = blood ? 10 : 7;
  for (let i = 0; i < count; i++) {
    const mat = new THREE.MeshBasicMaterial({ color: blood ? 0xa0121a : (i % 2 ? 0xffd27a : 0x9c958a), transparent: true });
    const p = new THREE.Mesh(sparkGeo, mat);
    p.position.copy(point);
    const v = new THREE.Vector3(Math.random() - 0.5, Math.random() - 0.2, Math.random() - 0.5).multiplyScalar(blood ? 3 : 5);
    if (normal) v.addScaledVector(new THREE.Vector3(...normal), 2.5);
    scene.add(p);
    fx.particles.push({ m: p, v, life: 0.35 + Math.random() * 0.25, max: 0.6 });
  }
}

function updateFx(dt) {
  for (let i = fx.puffs.length - 1; i >= 0; i--) {
    const p = fx.puffs[i];
    p.life -= dt;
    p.m.position.addScaledVector(p.v, dt);
    p.v.multiplyScalar(1 - dt * 2);
    p.m.scale.multiplyScalar(1 + p.grow * dt);
    p.m.material.opacity = Math.max(0, p.life / p.max) * p.base;
    if (p.life <= 0) { scene.remove(p.m); p.m.material.dispose(); fx.puffs.splice(i, 1); }
  }
  for (let i = fx.casings.length - 1; i >= 0; i--) {
    const c = fx.casings[i];
    c.life -= dt;
    c.v.y -= 7 * dt;
    c.m.position.addScaledVector(c.v, dt);
    c.m.rotation.x += c.spin * dt; c.m.rotation.z += c.spin * 0.6 * dt;
    if (c.life <= 0) { vmScene.remove(c.m); fx.casings.splice(i, 1); }
  }
  for (let i = fx.tracers.length - 1; i >= 0; i--) {
    const t = fx.tracers[i];
    t.life -= dt;
    t.m.material.opacity = Math.max(0, t.life / t.max) * 0.7;
    if (t.life <= 0) { scene.remove(t.m); t.m.material.dispose(); fx.tracers.splice(i, 1); }
  }
  for (let i = fx.particles.length - 1; i >= 0; i--) {
    const p = fx.particles[i];
    p.life -= dt;
    p.v.y -= 12 * dt;
    p.m.position.addScaledVector(p.v, dt);
    p.m.material.opacity = Math.max(0, p.life / p.max);
    if (p.life <= 0) { scene.remove(p.m); p.m.material.dispose(); fx.particles.splice(i, 1); }
  }
}

const muzzleTex = T.muzzle;

const flashLight = new THREE.PointLight(0xffb060, 0, 9, 2);
scene.add(flashLight);

// =====================================================================
// Audio (all synthesized)
// =====================================================================
const SHOT_SOUND = [
  { crack: 5200, crackDur: 0.22, crackGain: 0.55, body: 160, bodyDur: 0.14, tail: 0.4 },  // ar
  { crack: 6500, crackDur: 0.14, crackGain: 0.45, body: 200, bodyDur: 0.09, tail: 0.25 }, // smg
  { crack: 3800, crackDur: 0.5, crackGain: 0.8, body: 110, bodyDur: 0.35, tail: 1.1 },    // sniper
  { crack: 6000, crackDur: 0.16, crackGain: 0.5, body: 230, bodyDur: 0.1, tail: 0.3 },    // pistol
];

const audio = {
  ctx: null, master: null, noise: null,
  init() {
    if (this.ctx) return;
    const Ctx = window.AudioContext || window.webkitAudioContext;
    if (!Ctx) return;
    this.ctx = new Ctx();
    this.master = this.ctx.createGain();
    this.master.gain.value = settings.vol;
    const comp = this.ctx.createDynamicsCompressor();
    this.master.connect(comp).connect(this.ctx.destination);
    const len = this.ctx.sampleRate;
    this.noise = this.ctx.createBuffer(1, len, this.ctx.sampleRate);
    const data = this.noise.getChannelData(0);
    for (let i = 0; i < len; i++) data[i] = Math.random() * 2 - 1;
  },
  out(pos) {
    if (!pos) return this.master;
    const p = this.ctx.createPanner();
    p.panningModel = 'HRTF';
    p.distanceModel = 'inverse';
    p.refDistance = 4;
    p.rolloffFactor = 1.3;
    if (p.positionX) { p.positionX.value = pos.x; p.positionY.value = pos.y; p.positionZ.value = pos.z; }
    else p.setPosition(pos.x, pos.y, pos.z);
    p.connect(this.master);
    return p;
  },
  burst(out, t, { freq, endFreq = freq, dur, gain, type = 'lowpass', q = 0.7 }) {
    const n = this.ctx.createBufferSource();
    n.buffer = this.noise;
    const f = this.ctx.createBiquadFilter();
    f.type = type; f.Q.value = q;
    f.frequency.setValueAtTime(freq, t);
    f.frequency.exponentialRampToValueAtTime(endFreq, t + dur);
    const g = this.ctx.createGain();
    g.gain.setValueAtTime(gain, t);
    g.gain.exponentialRampToValueAtTime(0.001, t + dur);
    n.connect(f).connect(g).connect(out);
    n.start(t, Math.random() * 0.5);
    n.stop(t + dur + 0.02);
  },
  tone(out, t, { freq, endFreq = freq, dur, gain, type = 'sine' }) {
    const o = this.ctx.createOscillator();
    o.type = type;
    o.frequency.setValueAtTime(freq, t);
    o.frequency.exponentialRampToValueAtTime(endFreq, t + dur);
    const g = this.ctx.createGain();
    g.gain.setValueAtTime(gain, t);
    g.gain.exponentialRampToValueAtTime(0.001, t + dur);
    o.connect(g).connect(out);
    o.start(t);
    o.stop(t + dur + 0.02);
  },
  shot(pos, weapon = 0) {
    if (!this.ctx) return;
    const s = SHOT_SOUND[weapon] || SHOT_SOUND[0];
    const t = this.ctx.currentTime, out = this.out(pos), far = pos ? 0.5 : 1;
    this.burst(out, t, { freq: s.crack * far, endFreq: 250, dur: s.crackDur, gain: s.crackGain * (pos ? 2 : 1) });
    this.burst(out, t, { freq: 900, endFreq: 110, dur: s.tail, gain: pos ? 0.4 : 0.25, type: 'bandpass', q: 0.5 });
    this.tone(out, t, { freq: s.body, endFreq: 38, dur: s.bodyDur, gain: pos ? 0.9 : 0.6, type: 'triangle' });
  },
  hit(head, killed) {
    if (!this.ctx) return;
    const t = this.ctx.currentTime;
    this.tone(this.master, t, { freq: head ? 2300 : 1600, dur: 0.06, gain: 0.25, type: 'square' });
    if (killed) this.tone(this.master, t + 0.05, { freq: 880, endFreq: 1320, dur: 0.25, gain: 0.25, type: 'triangle' });
  },
  hurt() {
    if (!this.ctx) return;
    const t = this.ctx.currentTime;
    this.tone(this.master, t, { freq: 120, endFreq: 50, dur: 0.2, gain: 0.7 });
    this.burst(this.master, t, { freq: 600, endFreq: 100, dur: 0.15, gain: 0.4 });
  },
  click(delay = 0, freq = 2500, gain = 0.5) {
    if (!this.ctx) return;
    const t = this.ctx.currentTime + delay;
    this.burst(this.master, t, { freq, endFreq: freq * 0.6, dur: 0.05, gain, type: 'bandpass', q: 3 });
  },
  step(pos) {
    if (!this.ctx) return;
    const t = this.ctx.currentTime;
    this.burst(this.out(pos), t, { freq: 520, endFreq: 140, dur: 0.09, gain: pos ? 0.55 : 0.18 });
  },
  streak() {
    if (!this.ctx) return;
    const t = this.ctx.currentTime;
    [660, 880, 1320].forEach((f, i) => this.tone(this.master, t + i * 0.07, { freq: f, dur: 0.3, gain: 0.18, type: 'triangle' }));
  },
  setListener(cam) {
    if (!this.ctx) return;
    const l = this.ctx.listener, p = cam.position;
    const f = new THREE.Vector3(0, 0, -1).applyQuaternion(cam.quaternion);
    const u = new THREE.Vector3(0, 1, 0).applyQuaternion(cam.quaternion);
    if (l.positionX) {
      l.positionX.value = p.x; l.positionY.value = p.y; l.positionZ.value = p.z;
      l.forwardX.value = f.x; l.forwardY.value = f.y; l.forwardZ.value = f.z;
      l.upX.value = u.x; l.upY.value = u.y; l.upZ.value = u.z;
    } else {
      l.setPosition(p.x, p.y, p.z);
      l.setOrientation(f.x, f.y, f.z, u.x, u.y, u.z);
    }
  },
};

// =====================================================================
// First-person weapons
// =====================================================================
const viewModels = WEAPONS.map((w) => {
  const vm = viewWeapon(w.id, M);
  vmScene.add(vm.root);
  return vm;
});

const casingGeo = [
  new THREE.CylinderGeometry(0.0045, 0.0045, 0.04, 8), new THREE.CylinderGeometry(0.0045, 0.0045, 0.025, 8),
  new THREE.CylinderGeometry(0.006, 0.006, 0.06, 8), new THREE.CylinderGeometry(0.0045, 0.0045, 0.02, 8),
];
function ejectCasing(vm, wi) {
  vm.root.updateMatrixWorld(true);
  const m = new THREE.Mesh(casingGeo[wi], M.brass);
  m.position.copy(vm.model.localToWorld(new THREE.Vector3(...vm.info.eject)));
  m.rotation.set(Math.random() * 3, 0, Math.PI / 2);
  vmScene.add(m);
  fx.casings.push({ m, v: new THREE.Vector3(0.9 + Math.random() * 0.5, 0.9 + Math.random() * 0.5, 0.15 + Math.random() * 0.2), spin: 20 + Math.random() * 20, life: 0.6 });
  if (fx.casings.length > 20) vmScene.remove(fx.casings.shift().m);
}

// =====================================================================
// Remote players
// =====================================================================
function nameSprite(name, hue) {
  const c = document.createElement('canvas');
  c.width = 256; c.height = 64;
  const g = c.getContext('2d');
  g.font = 'bold 30px "Segoe UI", "Malgun Gothic", sans-serif';
  g.textAlign = 'center'; g.textBaseline = 'middle';
  g.lineWidth = 6; g.strokeStyle = 'rgba(0,0,0,.75)';
  g.strokeText(name, 128, 34);
  g.fillStyle = `hsl(${hue},85%,72%)`;
  g.fillText(name, 128, 34);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: t, depthWrite: false }));
  s.scale.set(1.5, 0.375, 1);
  s.position.y = 2.3;
  return s;
}

class Avatar {
  constructor(id, name, hue) {
    this.id = id; this.name = name; this.hue = hue;
    this.buf = [];
    this.alive = true; this.hp = 100; this.protect = false;
    this.deathT = 0; this.walk = 0; this.stepDist = 0; this.speed = 0; this.vy = 0;
    this.pos = new THREE.Vector3(); this.yaw = 0; this.pitch = 0;
    this.flashT = 0; this.lastShotT = -1e9;

    this.soldier = new Soldier(T, M, hue);
    this.root = this.soldier.root;
    this.body = this.soldier.body;
    const fl = new THREE.Sprite(new THREE.SpriteMaterial({ map: muzzleTex, blending: THREE.AdditiveBlending, depthWrite: false, transparent: true }));
    fl.scale.setScalar(0.45);
    fl.visible = false;
    this.soldier.aim.add(fl);
    this.flash = fl;
    this.setWeapon(0);
    this.tag = nameSprite(name, hue);
    this.root.add(this.tag);
    scene.add(this.root);
  }
  push(t, x, y, z, yaw, pitch) {
    this.buf.push({ t, x, y, z, yaw, pitch });
    if (this.buf.length > 30) this.buf.shift();
  }
  setWeapon(w) {
    this.soldier.setWeapon(w);
    this.flash.position.copy(this.soldier.muzzleLocal());
  }
  muzzleWorld(out) {
    this.root.updateMatrixWorld(true);
    return this.flash.getWorldPosition(out);
  }
  update(dt, renderT, time) {
    const b = this.buf;
    if (b.length) {
      let a = b[0], c = b[b.length - 1];
      for (let i = 0; i < b.length - 1; i++) {
        if (b[i].t <= renderT && b[i + 1].t >= renderT) { a = b[i]; c = b[i + 1]; break; }
      }
      const k = c.t === a.t ? 1 : clamp((renderT - a.t) / (c.t - a.t), 0, 1);
      const prev = this.pos.clone();
      this.pos.set(lerp(a.x, c.x, k), lerp(a.y, c.y, k), lerp(a.z, c.z, k));
      let dy = c.yaw - a.yaw;
      dy = Math.atan2(Math.sin(dy), Math.cos(dy));
      this.yaw = a.yaw + dy * k;
      this.pitch = lerp(a.pitch, c.pitch, k);
      const moved = Math.hypot(this.pos.x - prev.x, this.pos.z - prev.z);
      if (moved < 3) {
        this.walk += moved * 4.2;
        this.stepDist += moved;
        if (this.stepDist > 2.4 && this.alive && moved / Math.max(dt, 1e-3) > 4.5) {
          this.stepDist = 0;
          audio.step(this.pos);
        }
        this.speed = damp(this.speed, moved / Math.max(dt, 1e-3), 10, dt);
        this.vy = damp(this.vy, (this.pos.y - prev.y) / Math.max(dt, 1e-3), 10, dt);
      }
    }
    this.root.position.copy(this.pos);
    this.root.rotation.y = this.yaw;
    this.soldier.pose(this.walk, this.speed, Math.abs(this.vy) > 1.2, this.pitch, time + this.id);

    if (!this.alive) {
      this.deathT += dt;
      const k = Math.min(1, this.deathT / 0.45);
      const e = 1 - (1 - k) * (1 - k);
      this.body.rotation.x = -e * Math.PI / 2;
      this.body.position.y = -e * 0.12;
      this.root.visible = this.deathT < 3;
      this.tag.visible = false;
    } else {
      this.body.rotation.x = 0; this.body.position.y = 0;
      this.root.visible = true; this.tag.visible = true;
      this.soldier.team.gear.emissive.setHex(this.protect ? 0x1a2a4a : 0x000000);
    }
    if (this.flashT > 0) {
      this.flashT -= dt;
      this.flash.visible = this.flashT > 0;
      this.flash.material.rotation = Math.random() * 6;
    }
  }
  setAlive(alive) {
    if (alive && !this.alive) { this.deathT = 0; this.buf.length = 0; }
    this.alive = alive;
  }
  dispose() {
    scene.remove(this.root);
    this.soldier.dispose();
    this.tag.material.map.dispose();
    this.tag.material.dispose();
    this.flash.material.dispose();
  }
}

// =====================================================================
// Local player / input
// =====================================================================
const me = {
  id: 0, name: '', pos: new THREE.Vector3(0, 0, 0), vel: new THREE.Vector3(),
  yaw: 0, pitch: 0, onGround: false, alive: false, hp: 100, life: 0,
  primary: settings.primary, slot: 0, ammo: [WEAPONS[settings.primary].mag, WEAPONS[PISTOL].mag],
  reloadUntil: 0, reloadStart: 0, switchStart: -1e9, nextShot: 0, bloom: 0,
  stepDist: 0, deadT: 0, multi: 0, lastKillT: -1e9,
};
const weaponIdx = () => (me.slot === 0 ? me.primary : PISTOL);
const weapon = () => WEAPONS[weaponIdx()];

const keys = new Set();
const mouse = { fire: false, clicked: false, ads: false };
let locked = false, chatting = false, playing = false;
let adsAmt = 0, punch = 0, kick = 0, swayX = 0, swayY = 0, bobT = 0, landDip = 0, flashT = 0;
let lastMouseDX = 0, lastMouseDY = 0;
const SWITCH_MS = 350;

const canvas = renderer.domElement;
const lock = () => { if (!chatting) canvas.requestPointerLock?.(); };
canvas.addEventListener('click', lock);
$('pause').addEventListener('click', (e) => { if (e.target === $('pause') || e.target.classList.contains('click')) lock(); });
document.addEventListener('pointerlockchange', () => {
  locked = document.pointerLockElement === canvas;
  $('pause').classList.toggle('hidden', locked || !playing || chatting);
  if (!locked) { mouse.fire = false; mouse.ads = false; keys.clear(); }
});

document.addEventListener('mousemove', (e) => {
  if (!locked) return;
  // Scale sensitivity with zoom so aiming feels the same at every FOV.
  const s = 0.0022 * settings.sens * (camera.fov / BASE_FOV);
  me.yaw -= e.movementX * s;
  me.pitch = clamp(me.pitch - e.movementY * s, -1.55, 1.55);
  lastMouseDX += e.movementX; lastMouseDY += e.movementY;
});
document.addEventListener('mousedown', (e) => {
  if (!locked) return;
  if (e.button === 0) { mouse.fire = true; mouse.clicked = true; }
  if (e.button === 2) mouse.ads = true;
});
document.addEventListener('mouseup', (e) => {
  if (e.button === 0) mouse.fire = false;
  if (e.button === 2) mouse.ads = false;
});
document.addEventListener('wheel', (e) => { if (locked && e.deltaY) switchSlot(me.slot ? 0 : 1); }, { passive: true });
document.addEventListener('contextmenu', (e) => e.preventDefault());
window.addEventListener('blur', () => { keys.clear(); mouse.fire = mouse.ads = false; });

document.addEventListener('keydown', (e) => {
  if (!playing) return;
  if (chatting) {
    if (e.code === 'Enter') sendChat();
    else if (e.code === 'Escape') closeChat();
    return;
  }
  if (e.code === 'Tab') { e.preventDefault(); $('board').classList.remove('hidden'); return; }
  if (e.code === 'Enter' || e.code === 'KeyT') { e.preventDefault(); openChat(); return; }
  if (!locked) return;
  keys.add(e.code);
  if (e.code === 'KeyR') reload();
  if (e.code === 'Digit1') switchSlot(0);
  if (e.code === 'Digit2') switchSlot(1);
  if (e.code === 'KeyQ') switchSlot(me.slot ? 0 : 1);
  if (e.code === 'Space') e.preventDefault();
});
document.addEventListener('keyup', (e) => {
  keys.delete(e.code);
  if (e.code === 'Tab' && performance.now() >= roundEndAt) $('board').classList.add('hidden');
});

function openChat() {
  chatting = true;
  keys.clear(); mouse.fire = false;
  $('chat').classList.add('open');
  if (document.pointerLockElement) document.exitPointerLock();
  setTimeout(() => $('chatinput').focus(), 0);
}
function closeChat() {
  chatting = false;
  $('chat').classList.remove('open');
  $('chatinput').value = '';
  $('chatinput').blur();
  lock();
}
function sendChat() {
  const m = $('chatinput').value.trim();
  if (m) net.send({ t: 'chat', m });
  closeChat();
}

// --- settings & loadout UI ---
function syncSettingsUI() {
  $('sens').value = settings.sens; $('sensval').textContent = Number(settings.sens).toFixed(2);
  $('vol').value = settings.vol; $('volval').textContent = Math.round(settings.vol * 100) + '%';
  document.querySelectorAll('.loadout button').forEach((b) => b.classList.toggle('sel', Number(b.dataset.w) === settings.primary));
}
$('sens').addEventListener('input', (e) => { settings.sens = Number(e.target.value); syncSettingsUI(); saveSettings(); });
$('vol').addEventListener('input', (e) => {
  settings.vol = Number(e.target.value); syncSettingsUI(); saveSettings();
  if (audio.master) audio.master.gain.value = settings.vol;
});
const TYPES = ['돌격소총', '기관단총', '저격소총'];
for (const el of document.querySelectorAll('.loadout')) {
  for (const wi of PRIMARIES) {
    const w = WEAPONS[wi];
    const b = document.createElement('button');
    b.dataset.w = wi;
    const stats = [
      ['피해', w.body / 90], ['연사', Math.min(1, (1000 / w.fireMs) / 16)],
      ['사거리', Math.min(1, w.falloffDist / 60)], ['기동', (w.speed - 0.8) / 0.35],
    ];
    b.innerHTML = `<div class="wn">${w.short}</div><div class="wt">${TYPES[wi]}</div><div class="bars">${
      stats.map(([n, v]) => `<div class="bar">${n}<i style="--v:${Math.round(clamp(v, 0.05, 1) * 100)}%"></i></div>`).join('')}</div>`;
    b.addEventListener('click', (e) => {
      e.stopPropagation();
      settings.primary = wi;
      saveSettings();
      syncSettingsUI();
      net.send({ t: 'loadout', w: wi });
    });
    el.append(b);
  }
}
syncSettingsUI();

// =====================================================================
// Movement & collision
// =====================================================================
function moveAxis(axis, amount) {
  const p = [me.pos.x, me.pos.y, me.pos.z];
  p[axis] += amount;
  const b = collideBox(p[0], p[1], p[2]);
  if (!b) { me.pos.fromArray(p); return; }
  if (me.onGround && b.max[1] - me.pos.y <= PLAYER.step) {
    const up = [p[0], b.max[1] + 0.001, p[2]];
    if (!collideBox(up[0], up[1], up[2])) {
      landDip -= (up[1] - me.pos.y); // smooth the camera over the step
      me.pos.fromArray(up);
      return;
    }
  }
  p[axis] = amount > 0 ? b.min[axis] - PLAYER.radius - 0.001 : b.max[axis] + PLAYER.radius + 0.001;
  if (!collideBox(p[0], p[1], p[2])) me.pos.fromArray(p);
  me.vel.setComponent(axis, 0);
}

function physics(dt) {
  const fwd = (keys.has('KeyW') ? 1 : 0) - (keys.has('KeyS') ? 1 : 0);
  const strafe = (keys.has('KeyD') ? 1 : 0) - (keys.has('KeyA') ? 1 : 0);
  const sprinting = keys.has('ShiftLeft') && fwd > 0 && !mouse.ads && !mouse.fire && !isReloading();
  const speed = (mouse.ads ? PLAYER.ads : sprinting ? PLAYER.sprint : PLAYER.walk) * weapon().speed;
  const wish = new THREE.Vector3(
    strafe * Math.cos(me.yaw) - fwd * Math.sin(me.yaw), 0,
    -strafe * Math.sin(me.yaw) - fwd * Math.cos(me.yaw),
  );
  if (wish.lengthSq() > 0) wish.normalize().multiplyScalar(speed);
  const accel = me.onGround ? 14 : 3;
  me.vel.x = damp(me.vel.x, wish.x, accel, dt);
  me.vel.z = damp(me.vel.z, wish.z, accel, dt);

  if (keys.has('Space') && me.onGround) {
    me.vel.y = PLAYER.jump;
    me.onGround = false;
  }
  me.vel.y -= PLAYER.gravity * dt;

  const steps = Math.ceil(Math.max(Math.abs(me.vel.x), Math.abs(me.vel.z), Math.abs(me.vel.y)) * dt / 0.2) || 1;
  const sdt = dt / steps;
  const wasGround = me.onGround;
  const fallSpeed = me.vel.y;
  for (let i = 0; i < steps; i++) {
    moveAxis(0, me.vel.x * sdt);
    moveAxis(2, me.vel.z * sdt);
    me.onGround = false;
    me.pos.y += me.vel.y * sdt;
    const b = collideBox(me.pos.x, me.pos.y, me.pos.z);
    if (b) {
      if (me.vel.y <= 0) { me.pos.y = b.max[1]; me.onGround = true; }
      else me.pos.y = b.min[1] - PLAYER.height - 0.001;
      me.vel.y = 0;
    }
    if (me.pos.y <= 0) { me.pos.y = 0; me.vel.y = 0; me.onGround = true; }
  }
  if (!wasGround && me.onGround && fallSpeed < -6) {
    landDip -= Math.min(0.25, -fallSpeed * 0.015);
    audio.step(null);
  }
  me.pos.x = clamp(me.pos.x, -ARENA + PLAYER.radius, ARENA - PLAYER.radius);
  me.pos.z = clamp(me.pos.z, -ARENA + PLAYER.radius, ARENA - PLAYER.radius);

  const hs = Math.hypot(me.vel.x, me.vel.z);
  if (me.onGround && hs > 1) {
    me.stepDist += hs * dt;
    bobT += hs * dt * 1.25;
    if (me.stepDist > (sprinting ? 2.9 : 2.3)) { me.stepDist = 0; audio.step(null); }
  }
  return { hs, sprinting };
}

// =====================================================================
// Weapons
// =====================================================================
const isReloading = () => performance.now() < me.reloadUntil;
const isSwitching = () => performance.now() < me.switchStart + SWITCH_MS;

function reload() {
  if (!me.alive || isReloading() || isSwitching() || me.ammo[me.slot] >= weapon().mag) return;
  const w = weapon();
  me.reloadStart = performance.now();
  me.reloadUntil = me.reloadStart + w.reloadMs;
  me.reloadSlot = me.slot;
  net.send({ t: 'reload' });
  const r = w.reloadMs / 1000;
  audio.click(r * 0.1, 1800);
  audio.click(r * 0.45, 2600);
  audio.click(r * 0.8, 3200);
}

function switchSlot(slot) {
  if (!me.alive || slot === me.slot) return;
  me.slot = slot;
  me.reloadUntil = 0;
  me.switchStart = performance.now();
  me.nextShot = Math.max(me.nextShot, me.switchStart + SWITCH_MS);
  net.send({ t: 'slot', s: slot });
  audio.click(0, 1400, 0.3);
  updateWeaponHud();
}

function updateWeaponHud() {
  const w = weapon();
  $('weapon').textContent = w.name;
  $('ammomax').textContent = w.mag;
  $('slot0').textContent = WEAPONS[me.primary].short;
  document.querySelectorAll('#slots span').forEach((s) => s.classList.toggle('on', Number(s.dataset.slot) === me.slot));
  viewModels.forEach((vm, i) => { vm.root.visible = i === weaponIdx(); });
}

const tmpV = new THREE.Vector3();
function fire(moveSpeed) {
  const t = performance.now();
  const w = weapon();
  me.nextShot = t + w.fireMs;
  me.ammo[me.slot]--;

  const ads = adsAmt > 0.7;
  let spread = w.spread + me.bloom + (moveSpeed / PLAYER.sprint) * w.moveSpread + (me.onGround ? 0 : 0.045);
  if (ads) spread *= w.adsMul;
  me.bloom = Math.min(me.bloom + w.bloom, w.maxBloom);

  const eye = new THREE.Vector3(me.pos.x, me.pos.y + PLAYER.eye, me.pos.z);
  const q = new THREE.Quaternion().setFromEuler(new THREE.Euler(me.pitch, me.yaw, 0, 'YXZ'));
  const a = Math.random() * Math.PI * 2, r = Math.sqrt(Math.random()) * spread;
  const dir = new THREE.Vector3(Math.cos(a) * r, Math.sin(a) * r, -1).normalize().applyQuaternion(q);

  // Client-side prediction of where the bullet lands (server is authoritative for damage).
  const o = eye.toArray(), d = dir.toArray();
  const wall = raycastMap(o, d, RANGE);
  let bestT = wall ? wall.t : RANGE, hitAvatar = null;
  for (const av of avatars.values()) {
    if (!av.alive) continue;
    for (const hb of playerHitboxes(av.pos.x, av.pos.y, av.pos.z)) {
      const h = rayAABB(o, d, hb.min, hb.max);
      if (h && h.t < bestT) { bestT = h.t; hitAvatar = av; }
    }
  }
  const end = eye.clone().addScaledVector(dir, bestT);
  net.send({ t: 'shoot', o: o.map((v) => +v.toFixed(3)), d: d.map((v) => +v.toFixed(5)), l: me.life });

  spawnTracer(muzzleWorld(tmpV), end, 0xffe7a0, w.scope ? 1.6 : 1);
  if (bestT < RANGE) spawnImpact(end, hitAvatar ? null : wall?.n, !!hitAvatar);

  // Recoil: a permanent climb the player has to pull down, plus a visual punch that recovers.
  const climb = ads ? 0.55 : 1;
  me.pitch = clamp(me.pitch + (w.recoil + Math.random() * w.recoil * 0.45) * climb, -1.55, 1.55);
  me.yaw += (Math.random() - 0.5) * w.recoil * climb;
  punch += w.punch * climb;
  kick = 1;
  const vm = viewModels[weaponIdx()];
  vm.flash.visible = true;
  vm.flash.rotation.z = Math.random() * Math.PI;
  flashT = 0.045;
  audio.shot(null, weaponIdx());
  if (w.scope) setTimeout(() => ejectCasing(vm, weaponIdx()), 380);
  else ejectCasing(vm, weaponIdx());
  if (w.scope) { audio.click(0.35, 1200, 0.35); audio.click(0.6, 1700, 0.35); }
  if (me.ammo[me.slot] <= 0) setTimeout(reload, 150);
}

function muzzleWorld(out) {
  // Approximate world position of the first-person muzzle, for tracers.
  const q = new THREE.Quaternion().setFromEuler(new THREE.Euler(me.pitch, me.yaw, 0, 'YXZ'));
  const local = new THREE.Vector3(lerp(0.2, 0, adsAmt), lerp(-0.16, -0.07, adsAmt), -0.8);
  return out.copy(local.applyQuaternion(q)).add(camera.position);
}

// =====================================================================
// HUD
// =====================================================================
const hud = {
  hitT: 0, vigT: 0, announceT: 0, streakT: 0,
  hitmarker(head, kill) {
    $('hitmarker').className = kill ? 'kill' : head ? 'head' : '';
    this.hitT = kill ? 0.45 : 0.2;
  },
  announce(html, secs = 1.6) {
    $('announce').innerHTML = html;
    this.announceT = secs;
  },
  streak(text) {
    $('streak').textContent = text;
    $('streak').classList.add('on');
    this.streakT = 1.8;
    audio.streak();
  },
  damage(fromX, fromZ) {
    this.vigT = 0.6;
    const el = document.createElement('div');
    el.className = 'dmgdir';
    el.dataset.x = fromX; el.dataset.z = fromZ;
    $('dmgdirs').appendChild(el);
    setTimeout(() => (el.style.opacity = '0'), 900);
    setTimeout(() => el.remove(), 1500);
  },
  killfeed(killer, victim, head, w) {
    const el = document.createElement('div');
    el.className = 'kf' + (killer?.id === me.id || victim?.id === me.id ? ' me' : '');
    const n = (p) => {
      const s = document.createElement('span');
      s.textContent = p ? p.name : '?';
      s.style.color = p ? `hsl(${p.hue},85%,70%)` : '#fff';
      return s;
    };
    const g = document.createElement('span');
    g.className = 'gun';
    g.textContent = `[${WEAPONS[w]?.short ?? ''}]${head ? ' ⊕' : ''}`;
    el.append(n(killer), g, n(victim));
    const feed = $('killfeed');
    feed.prepend(el);
    while (feed.children.length > 6) feed.lastChild.remove();
    setTimeout(() => (el.style.opacity = '0'), 6000);
    setTimeout(() => el.remove(), 6700);
  },
  chat(text, who, sys) {
    const el = document.createElement('div');
    el.className = 'cm' + (sys ? ' sys' : '');
    if (who) {
      const n = document.createElement('b');
      n.textContent = who.name + ': ';
      n.style.color = `hsl(${who.hue},85%,72%)`;
      el.append(n);
    }
    el.append(document.createTextNode(text));
    const log = $('chatlog');
    log.append(el);
    while (log.children.length > 8) log.firstChild.remove();
    setTimeout(() => (el.style.opacity = '0'), 9000);
  },
  update(dt) {
    this.hitT -= dt;
    $('hitmarker').style.opacity = this.hitT > 0 ? Math.min(1, this.hitT * 8) : 0;
    this.vigT -= dt;
    const low = me.alive && me.hp < 35 ? 0.35 + Math.sin(performance.now() / 250) * 0.1 : 0;
    $('vignette').style.opacity = Math.max(low, clamp(this.vigT, 0, 0.6) * 1.4);
    this.announceT -= dt;
    $('announce').style.opacity = this.announceT > 0 ? 1 : 0;
    this.streakT -= dt;
    if (this.streakT <= 0) $('streak').classList.remove('on');
    for (const el of $('dmgdirs').children) {
      const ax = el.dataset.x - me.pos.x, az = el.dataset.z - me.pos.z;
      const rot = Math.atan2(-Math.sin(me.yaw), -Math.cos(me.yaw)) - Math.atan2(ax, az);
      el.style.transform = `rotate(${rot}rad)`;
    }
    $('hpnum').textContent = Math.ceil(me.hp);
    $('hpfill').style.width = clamp(me.hp, 0, 100) + '%';
    $('hpfill').style.backgroundColor = me.hp > 60 ? '#5ee07a' : me.hp > 30 ? '#ffc23d' : '#ff4d3a';
    $('ammonum').textContent = me.ammo[me.slot];
    $('ammo').classList.toggle('low', me.ammo[me.slot] <= Math.ceil(weapon().mag * 0.25));
    const rl = isReloading();
    $('reloadbar').style.opacity = rl ? 1 : 0;
    if (rl) $('reloadfill').style.width = ((performance.now() - me.reloadStart) / weapon().reloadMs * 100) + '%';
  },
};

// --- minimap (north = -z up). Enemies only show up while they are firing. ---
const mini = (() => {
  const c = $('minimap'), g = c.getContext('2d'), S = c.width;
  const k = S / (ARENA * 2 + 4);
  const map = (x, z) => [(x + ARENA + 2) * k, (z + ARENA + 2) * k];
  const base = document.createElement('canvas');
  base.width = base.height = S;
  const bg = base.getContext('2d');
  bg.fillStyle = 'rgba(255,255,255,.04)';
  bg.fillRect(...map(-ARENA, -ARENA), ARENA * 2 * k, ARENA * 2 * k);
  for (const b of BOXES) {
    if (b.kind === 'wall' && b.min[1] > 2) continue;
    bg.fillStyle = b.kind === 'wall' ? 'rgba(220,220,220,.55)' : b.kind === 'container' ? 'rgba(160,170,190,.5)'
      : b.kind === 'crate' ? 'rgba(200,160,100,.45)' : 'rgba(200,195,180,.4)';
    const [x, y] = map(b.min[0], b.min[2]);
    bg.fillRect(x, y, (b.max[0] - b.min[0]) * k, (b.max[2] - b.min[2]) * k);
  }
  return {
    draw() {
      g.clearRect(0, 0, S, S);
      g.drawImage(base, 0, 0);
      const now = performance.now();
      for (const av of avatars.values()) {
        const age = now - av.lastShotT;
        if (!av.alive || age > 1800) continue;
        const [x, y] = map(av.pos.x, av.pos.z);
        g.globalAlpha = 1 - age / 1800;
        g.fillStyle = '#ff4d3a';
        g.beginPath(); g.arc(x, y, 3.5, 0, 7); g.fill();
      }
      g.globalAlpha = 1;
      if (!me.alive) return;
      const [x, y] = map(me.pos.x, me.pos.z);
      g.save();
      g.translate(x, y);
      g.rotate(-me.yaw);
      g.fillStyle = 'rgba(255,211,77,.18)';
      g.beginPath(); g.moveTo(0, 0); g.arc(0, 0, 26, -Math.PI / 2 - 0.6, -Math.PI / 2 + 0.6); g.fill();
      g.fillStyle = '#ffd34d';
      g.beginPath(); g.moveTo(0, -6); g.lineTo(4.5, 5); g.lineTo(0, 2.5); g.lineTo(-4.5, 5); g.closePath(); g.fill();
      g.restore();
    },
  };
})();

const board = { rows: [], killLimit: 30 };
function renderBoard() {
  const rows = [...board.rows].sort((a, b) => b[2] - a[2] || a[3] - b[3]);
  const body = $('boardrows');
  body.textContent = '';
  rows.forEach(([id, name, k, d, ping, hue], i) => {
    const tr = document.createElement('tr');
    if (id === me.id) tr.className = 'me';
    const cells = [String(i + 1), null, String(k), String(d), ping < 0 ? 'BOT' : ping + 'ms'];
    cells.forEach((c, j) => {
      const td = document.createElement('td');
      if (j === 1) {
        const sw = document.createElement('span');
        sw.className = 'sw'; sw.style.background = `hsl(${hue},70%,55%)`;
        td.append(sw, document.createTextNode(name));
      } else td.textContent = c;
      tr.append(td);
    });
    body.append(tr);
  });
  const top = rows[0];
  $('leader').textContent = top ? `1위 ${top[1]} · ${top[2]}킬` : '';
  const mine = rows.findIndex((r) => r[0] === me.id);
  $('limit').textContent = `${board.killLimit}킬 선취 · 내 순위 ${mine + 1}/${rows.length}`;
  $('boardlimit').textContent = `${board.killLimit}킬 선취 승리`;
}

// =====================================================================
// Networking
// =====================================================================
const avatars = new Map();
const names = new Map(); // id -> {id, name, hue}
let roundEndAt = 0, deathUntil = 0;
const INTERP_MS = 100; // must match CLIENT_INTERP_MS in server.js
const MULTI = { 2: '더블 킬', 3: '트리플 킬', 4: '쿼드라 킬', 5: '펜타 킬' };
const STREAK = { 3: '3연속 처치!', 5: '5연속 처치 — 폭주!', 8: '8연속 처치 — 무적!', 12: '12연속 처치 — 전설!' };

const net = {
  ws: null, rtt: 0, pingTimer: 0,
  send(msg) { if (this.ws && this.ws.readyState === 1) this.ws.send(JSON.stringify(msg)); },
  error: '',
  connect(name, opts) {
    const ws = new WebSocket((location.protocol === 'https:' ? 'wss://' : 'ws://') + location.host);
    this.ws = ws;
    this.error = '';
    ws.onopen = () => ws.send(JSON.stringify({ t: 'join', name, w: settings.primary, ...opts }));
    ws.onmessage = (e) => onMessage(JSON.parse(e.data));
    ws.onclose = () => {
      playing = false;
      if (document.pointerLockElement) document.exitPointerLock();
      $('hud').classList.add('hidden');
      $('menu').classList.remove('hidden');
      $('menuerr').textContent = this.error || '서버와 연결이 끊어졌습니다. 다시 시작해 주세요.';
      $('play').disabled = false;
      for (const av of avatars.values()) av.dispose();
      avatars.clear();
      clearInterval(this.pingTimer);
      menuOrbit();
    };
    clearInterval(this.pingTimer);
    this.pingTimer = setInterval(() => this.send({ t: 'ping', c: performance.now(), rtt: this.rtt }), 2000);
  },
};

const room = { code: '', pub: true };
const playerInfo = (id) => names.get(id);
const addAvatar = (id, name, hue) => { if (!avatars.has(id)) avatars.set(id, new Avatar(id, name, hue)); };

function onMessage(m) {
  switch (m.t) {
    case 'error':
      net.error = m.m;
      break;
    case 'welcome':
      me.id = m.id;
      room.code = m.room;
      room.pub = !!m.pub;
      $('roomtag').textContent = room.pub ? '공개 매치' : `방 코드 ${m.room}`;
      $('roomcode').textContent = room.pub ? '공개' : m.room;
      $('copylink').style.display = room.pub ? 'none' : '';
      if (!room.pub) history.replaceState(null, '', `?room=${m.room}`);
      if (!room.pub) hud.chat(`방 코드 ${m.room} — 친구에게 코드나 초대 링크(Esc 메뉴)를 보내세요`, null, true);
      board.killLimit = m.killLimit;
      for (const [id, name, hue] of m.players) {
        names.set(id, { id, name, hue });
        if (id !== me.id) addAvatar(id, name, hue);
      }
      break;
    case 'join':
      names.set(m.id, { id: m.id, name: m.name, hue: m.hue });
      addAvatar(m.id, m.name, m.hue);
      break;
    case 'leave':
      avatars.get(m.id)?.dispose();
      avatars.delete(m.id);
      break;
    case 'spawn':
      me.pos.set(m.p[0], m.p[1], m.p[2]);
      me.vel.set(0, 0, 0);
      me.yaw = m.yaw; me.pitch = 0;
      me.life = m.life;
      me.alive = true; me.hp = 100; me.deadT = 0;
      me.primary = m.w; me.slot = 0;
      me.ammo = [WEAPONS[m.w].mag, WEAPONS[PISTOL].mag];
      me.reloadUntil = 0; me.bloom = 0; me.multi = 0;
      me.switchStart = performance.now();
      updateWeaponHud();
      $('death').classList.add('hidden');
      break;
    case 'fix':
      me.pos.set(m.p[0], m.p[1], m.p[2]);
      me.vel.set(0, 0, 0);
      break;
    case 's': {
      const t = performance.now();
      for (const [id, x, y, z, yaw, pitch, alive, hp, prot, w] of m.p) {
        if (id === me.id) { if (me.alive) me.hp = hp; continue; }
        const av = avatars.get(id);
        if (!av) continue;
        av.push(t, x, y, z, yaw, pitch);
        av.setAlive(!!alive);
        av.setWeapon(w);
        av.hp = hp; av.protect = !!prot;
      }
      break;
    }
    case 'shot': {
      const av = avatars.get(m.id);
      const end = new THREE.Vector3(...m.e);
      const from = av ? av.muzzleWorld(new THREE.Vector3()) : new THREE.Vector3(...m.o);
      spawnTracer(from, end, 0xffd890, WEAPONS[m.w]?.scope ? 1.6 : 1);
      if (m.v !== me.id && (m.n || m.v)) spawnImpact(end, m.n, !!m.v);
      if (av) { av.flashT = 0.05; av.lastShotT = performance.now(); }
      audio.shot(av ? av.pos.clone().setY(av.pos.y + 1.4) : new THREE.Vector3(...m.o), m.w);
      break;
    }
    case 'dmg':
      me.hp = m.hp;
      hud.damage(m.from[0], m.from[1]);
      punch -= 0.02;
      audio.hurt();
      break;
    case 'hm':
      hud.hitmarker(m.h, m.k);
      audio.hit(m.h, m.k);
      if (m.k) {
        const v = playerInfo(m.v);
        hud.announce(`${escapeHtml(v ? v.name : '')} 처치 <span style="opacity:.6">+100</span>${m.h ? '<small>HEADSHOT</small>' : ''}`);
      }
      break;
    case 'kill': {
      const killer = playerInfo(m.k), victim = playerInfo(m.v);
      hud.killfeed(killer, victim, m.h, m.w);
      if (m.k === me.id && m.v !== me.id) {
        const t = performance.now();
        me.multi = t - me.lastKillT < 3500 ? me.multi + 1 : 1;
        me.lastKillT = t;
        if (MULTI[me.multi]) hud.streak(MULTI[me.multi]);
        else if (STREAK[m.s]) hud.streak(STREAK[m.s]);
      }
      if (m.v === me.id) {
        me.alive = false; me.hp = 0; me.deadT = 0;
        mouse.fire = false;
        $('death').classList.remove('hidden');
        const self = !killer || killer.id === me.id;
        $('deathby').textContent = self ? '' : `${killer.name} 에게 처치당했습니다${m.h ? ' (헤드샷)' : ''}`;
        $('deathinfo').textContent = self ? '' : `${WEAPONS[m.w]?.name ?? ''} · 상대 남은 체력 ${m.kh}`;
        deathUntil = performance.now() + 3000;
      } else {
        avatars.get(m.v)?.setAlive(false);
      }
      break;
    }
    case 'board':
      board.rows = m.p;
      for (const [id, name, , , , hue] of m.p) if (!names.has(id)) names.set(id, { id, name, hue });
      renderBoard();
      break;
    case 'round':
      roundEndAt = performance.now() + m.ms;
      $('roundwinner').textContent = m.w === me.id ? '🏆 승리!' : `🏆 ${m.name} 승리`;
      $('roundover').classList.remove('hidden');
      $('board').classList.remove('hidden');
      break;
    case 'roundstart':
      roundEndAt = 0;
      $('roundover').classList.add('hidden');
      $('board').classList.add('hidden');
      hud.announce('새 라운드 시작!', 2);
      break;
    case 'chat':
      hud.chat(m.m, m.sys ? null : playerInfo(m.id), !!m.sys);
      break;
    case 'pong':
      net.rtt = net.rtt ? lerp(net.rtt, performance.now() - m.c, 0.3) : performance.now() - m.c;
      $('net').textContent = Math.round(net.rtt) + ' ms';
      break;
    case 'full':
      alert('서버가 가득 찼습니다 (최대 16명).');
      break;
  }
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

// =====================================================================
// Main loop
// =====================================================================
let last = performance.now(), sendAcc = 0, fpsAcc = 0, fpsN = 0;
const crossEls = ['t', 'b', 'l', 'r'].map((c) => $('crosshair').querySelector('.' + c));

function frame() {
  requestAnimationFrame(frame);
  const now = performance.now();
  const dt = Math.min(0.05, (now - last) / 1000);
  last = now;
  const w = weapon();
  const vm = viewModels[weaponIdx()];

  let move = { hs: 0, sprinting: false };
  if (playing && me.alive) {
    if (!locked) { keys.clear(); mouse.fire = false; }
    move = physics(dt);
    const trigger = w.auto ? mouse.fire : mouse.clicked;
    if (trigger && now >= me.nextShot && !isReloading() && !isSwitching() && now >= roundEndAt) {
      if (me.ammo[me.slot] > 0) fire(move.hs);
      else if (mouse.clicked) { audio.click(0, 900, 0.4); reload(); }
    }
    sendAcc += dt;
    if (sendAcc >= 0.05) {
      sendAcc = 0;
      net.send({ t: 'state', p: [+me.pos.x.toFixed(3), +me.pos.y.toFixed(3), +me.pos.z.toFixed(3)], y: +me.yaw.toFixed(3), x: +me.pitch.toFixed(3), l: me.life });
    }
  }
  mouse.clicked = false;
  me.bloom = damp(me.bloom, 0, mouse.fire ? 2 : 8, dt);

  // --- camera ---
  const wantAds = mouse.ads && me.alive && !isReloading() && !isSwitching() && !move.sprinting ? 1 : 0;
  adsAmt = damp(adsAmt, wantAds, w.scope ? 11 : 14, dt);
  punch = damp(punch, 0, 12, dt);
  landDip = damp(landDip, 0, 10, dt);
  const bobAmt = (me.onGround ? clamp(move.hs / PLAYER.sprint, 0, 1) : 0) * (1 - adsAmt * 0.85);
  const bobY = Math.abs(Math.sin(bobT * 1.5)) * 0.05 * bobAmt;
  if (me.alive) {
    camera.position.set(me.pos.x, me.pos.y + PLAYER.eye + landDip + bobY, me.pos.z);
    camera.rotation.set(me.pitch + punch, me.yaw, Math.sin(bobT * 0.75) * 0.004 * bobAmt);
  } else {
    // Death cam: sink to the floor and tilt.
    me.deadT += dt;
    const k = Math.min(1, me.deadT / 0.5);
    camera.position.set(me.pos.x, me.pos.y + lerp(PLAYER.eye, 0.35, k), me.pos.z);
    camera.rotation.set(lerp(me.pitch, -0.2, k), me.yaw, lerp(0, 0.6, k));
  }
  const scoped = w.scope && adsAmt > 0.85;
  const targetFov = lerp(BASE_FOV, w.adsFov, adsAmt) + (move.sprinting ? 6 : 0);
  if (Math.abs(camera.fov - targetFov) > 0.01) {
    camera.fov = scoped ? w.adsFov : damp(camera.fov, targetFov, 14, dt);
    camera.updateProjectionMatrix();
  }
  world.update(camera.position, now / 1000);
  audio.setListener(camera);
  $('scope').style.opacity = scoped ? 1 : 0;

  // --- viewmodel ---
  kick = damp(kick, 0, w.scope ? 8 : 18, dt);
  swayX = damp(swayX, clamp(-lastMouseDX * 0.0004, -0.04, 0.04), 8, dt);
  swayY = damp(swayY, clamp(lastMouseDY * 0.0004, -0.04, 0.04), 8, dt);
  lastMouseDX = lastMouseDY = 0;
  const base = vm.hip.clone().lerp(vm.ads, adsAmt);
  const swayK = 1 - adsAmt * 0.8;
  const sw = clamp((now - me.switchStart) / SWITCH_MS, 0, 1);
  const raise = 1 - (1 - sw) * (1 - sw);
  vm.root.position.set(
    base.x + swayX * swayK + Math.sin(bobT * 0.75) * 0.012 * bobAmt,
    base.y + swayY * swayK - bobY * 0.4 + landDip * 0.3 - (move.sprinting ? 0.04 : 0) - (1 - raise) * 0.3,
    base.z + kick * (0.045 - adsAmt * 0.02),
  );
  let rx = kick * (w.scope ? 0.18 : 0.07) * (1 - adsAmt * 0.6) - (1 - raise) * 0.6;
  const ry = (move.sprinting ? 0.6 : 0) * (1 - adsAmt);
  let rz = swayX * 2 * swayK;
  // reload animation: tilt, drop & re-seat the magazine
  if (isReloading()) {
    const p = (now - me.reloadStart) / w.reloadMs;
    const tilt = Math.sin(Math.min(1, p) * Math.PI);
    rx -= tilt * 0.45; rz += tilt * 0.5;
    const drop = p < 0.35 ? p / 0.35 : p < 0.55 ? 1 : Math.max(0, 1 - (p - 0.55) / 0.25);
    vm.mag.position.set(vm.magBase.x, vm.magBase.y - drop * 0.25, vm.magBase.z);
    vm.mag.visible = !(p > 0.33 && p < 0.5);
  } else {
    vm.mag.position.copy(vm.magBase);
    vm.mag.visible = true;
  }
  if (!me.alive) vm.root.position.y -= 0.6;
  vm.root.rotation.set(rx, ry, rz);
  vm.root.visible = playing && !scoped;
  flashT -= dt;
  if (flashT <= 0) vm.flash.visible = false;
  flashLight.intensity = flashT > 0 ? 12 : 0;
  if (flashT > 0) flashLight.position.copy(muzzleWorld(tmpV));

  // --- crosshair ---
  const gap = 5 + (w.spread + me.bloom) * 700 + (move.hs / PLAYER.sprint) * w.moveSpread * 600 + (me.onGround ? 0 : 18);
  crossEls[0].style.top = -(gap + 9) + 'px';
  crossEls[1].style.top = gap + 'px';
  crossEls[2].style.left = -(gap + 9) + 'px';
  crossEls[3].style.left = gap + 'px';
  $('crosshair').style.opacity = adsAmt > 0.5 || !me.alive || move.sprinting ? 0 : 1;

  // --- remote players & fx ---
  const renderT = now - INTERP_MS;
  for (const av of avatars.values()) av.update(dt, renderT, now / 1000);
  updateFx(dt);
  if (playing) { hud.update(dt); mini.draw(); }

  if (!me.alive && playing) {
    $('deathtimer').textContent = `리스폰까지 ${Math.max(0, (deathUntil - now) / 1000).toFixed(1)}초`;
  }
  if (roundEndAt) $('roundtimer').textContent = `다음 라운드 ${Math.max(0, Math.ceil((roundEndAt - now) / 1000))}초`;

  fpsAcc += dt; fpsN++;
  if (fpsAcc > 0.5) { $('fps').textContent = Math.round(fpsN / fpsAcc) + ' fps'; fpsAcc = 0; fpsN = 0; }

  if (settings.quality === 'low') {
    renderer.clear();
    renderer.render(scene, camera);
    renderer.clearDepth();
    if (playing) renderer.render(vmScene, vmCam);
  } else {
    vmPass.enabled = playing;
    grade.uniforms.time.value = (now / 1000) % 100;
    grade.uniforms.hurt.value = me.alive ? clamp((50 - me.hp) / 50, 0, 1) : 1;
    composer.render();
  }
}

addEventListener('resize', () => {
  renderer.setSize(innerWidth, innerHeight);
  composer.setSize(innerWidth, innerHeight);
  camera.aspect = vmCam.aspect = innerWidth / innerHeight;
  camera.updateProjectionMatrix();
  vmCam.updateProjectionMatrix();
});

// =====================================================================
// Menu
// =====================================================================
// Idle menu camera orbits the arena.
const menuCam = { t: 0 };
function menuOrbit() {
  if (playing) return;
  menuCam.t += 0.0015;
  me.pos.set(Math.cos(menuCam.t) * 30, 6, Math.sin(menuCam.t) * 30);
  me.yaw = Math.atan2(me.pos.x, me.pos.z);
  me.pitch = -0.18;
  me.alive = true;
  requestAnimationFrame(menuOrbit);
}
menuOrbit();

try { $('name').value = localStorage.getItem('sz-name') || ''; } catch {}
fetch('/status').then((r) => r.json()).then((s) => {
  if (!new URLSearchParams(location.search).get('room')) $('online').textContent = `현재 접속자 ${s.players}명 · 방 ${s.rooms}개`;
}).catch(() => { $('online').textContent = ''; });

function start(opts = { mode: 'quick' }) {
  if (playing) return;
  const name = $('name').value.trim() || `Player${Math.floor(Math.random() * 900 + 100)}`;
  try { localStorage.setItem('sz-name', name); } catch {}
  me.name = name;
  me.alive = false;
  playing = true;
  $('play').disabled = true;
  $('menu').classList.add('hidden');
  $('hud').classList.remove('hidden');
  audio.init();
  audio.ctx?.resume();
  $('menuerr').textContent = '';
  net.connect(name, opts);
  lock();
}
const joinByCode = () => {
  const code = $('code').value.trim().toUpperCase();
  if (!code) { $('menuerr').textContent = '방 코드를 입력해 주세요.'; $('code').focus(); return; }
  start({ mode: 'code', code });
};
$('play').addEventListener('click', () => start({ mode: 'quick' }));
$('create').addEventListener('click', () => start({ mode: 'create', bots: $('botfill').checked }));
$('joincode').addEventListener('click', joinByCode);
$('code').addEventListener('keydown', (e) => { if (e.code === 'Enter') joinByCode(); });
$('name').addEventListener('keydown', (e) => { if (e.code === 'Enter') ($('code').value.trim() ? joinByCode() : start({ mode: 'quick' })); });
{
  const code = new URLSearchParams(location.search).get('room');
  if (code) {
    $('code').value = code.toUpperCase();
    $('online').textContent = `초대받은 방: ${code.toUpperCase()} — 닉네임을 입력하고 [코드로 참가]를 누르세요`;
  }
}
$('copylink').addEventListener('click', async (e) => {
  e.stopPropagation();
  const link = `${location.origin}/?room=${room.code}`;
  try { await navigator.clipboard.writeText(link); e.target.textContent = '복사됨!'; }
  catch { prompt('초대 링크를 복사하세요', link); }
  setTimeout(() => { e.target.textContent = '초대 링크 복사'; }, 1500);
});
$('quality').value = settings.quality;
$('quality').addEventListener('change', (e) => {
  settings.quality = e.target.value;
  saveSettings();
  renderer.setPixelRatio(pixelRatio());
  composer.setPixelRatio(pixelRatio());
  renderer.setSize(innerWidth, innerHeight);
  composer.setSize(innerWidth, innerHeight);
});

// Debug hook for automated browser tests (?debug).
if (new URLSearchParams(location.search).has('debug')) {
  window.__sz = { me, keys, mouse, avatars, switchSlot, setLocked: (v) => { locked = v; } };
}

frame();
