import * as THREE from 'three';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import {
  ARENA, BOXES, PLAYER, WEAPONS, PRIMARIES, PISTOL, RANGE,
  raycastMap, rayAABB, playerHitboxes, collideBox,
} from './shared/map.js';

const $ = (id) => document.getElementById(id);
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const lerp = (a, b, t) => a + (b - a) * t;
const damp = (a, b, k, dt) => lerp(a, b, 1 - Math.exp(-k * dt));

const settings = { sens: 1, vol: 0.6, primary: 0 };
try { Object.assign(settings, JSON.parse(localStorage.getItem('sz-settings') || '{}')); } catch {}
if (!PRIMARIES.includes(settings.primary)) settings.primary = 0;
const saveSettings = () => { try { localStorage.setItem('sz-settings', JSON.stringify(settings)); } catch {} };

// =====================================================================
// Renderer / scene
// =====================================================================
const renderer = new THREE.WebGLRenderer({ antialias: true, powerPreference: 'high-performance' });
renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
renderer.setSize(innerWidth, innerHeight);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.0;
renderer.autoClear = false;
document.body.prepend(renderer.domElement);

const scene = new THREE.Scene();
const FOG = new THREE.Color(0xc4d3e0);
scene.fog = new THREE.Fog(FOG, 45, 190);

const BASE_FOV = 78;
const camera = new THREE.PerspectiveCamera(BASE_FOV, innerWidth / innerHeight, 0.05, 500);
camera.rotation.order = 'YXZ';

const sunDir = new THREE.Vector3(0.45, 0.8, 0.35).normalize();

const sky = new THREE.Mesh(
  new THREE.SphereGeometry(400, 32, 16),
  new THREE.ShaderMaterial({
    side: THREE.BackSide,
    depthWrite: false,
    uniforms: {
      top: { value: new THREE.Color(0x2f6fc0) },
      bottom: { value: FOG.clone() },
      sunDir: { value: sunDir },
    },
    vertexShader: `varying vec3 vDir;
      void main() { vDir = normalize(position); gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }`,
    fragmentShader: `uniform vec3 top; uniform vec3 bottom; uniform vec3 sunDir; varying vec3 vDir;
      void main() {
        float h = clamp(vDir.y * 1.4, 0.0, 1.0);
        vec3 c = mix(bottom, top, pow(h, 0.6));
        float s = max(dot(normalize(vDir), sunDir), 0.0);
        c += vec3(1.0, 0.92, 0.75) * (pow(s, 900.0) * 6.0 + pow(s, 14.0) * 0.35);
        gl_FragColor = vec4(c, 1.0);
        #include <tonemapping_fragment>
        #include <colorspace_fragment>
      }`,
  }),
);
sky.renderOrder = -1;
scene.add(sky);

scene.add(new THREE.HemisphereLight(0xd6e6ff, 0x6e5f4c, 1.15));
const sun = new THREE.DirectionalLight(0xfff0d8, 2.8);
sun.position.copy(sunDir).multiplyScalar(90);
sun.castShadow = true;
sun.shadow.mapSize.set(2048, 2048);
Object.assign(sun.shadow.camera, { left: -56, right: 56, top: 56, bottom: -56, near: 1, far: 220 });
sun.shadow.bias = -0.0004;
sun.shadow.normalBias = 0.04;
scene.add(sun);

// =====================================================================
// Procedural textures
// =====================================================================
function rng(seed) {
  return () => { seed = (seed * 16807) % 2147483647; return (seed - 1) / 2147483646; };
}

function canvasTex(size, draw) {
  const c = document.createElement('canvas');
  c.width = c.height = size;
  const g = c.getContext('2d');
  draw(g, size);
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = renderer.capabilities.getMaxAnisotropy();
  return t;
}

function speckle(g, s, n, alpha, seed) {
  const r = rng(seed);
  for (let i = 0; i < n; i++) {
    const v = Math.floor(r() * 255);
    g.fillStyle = `rgba(${v},${v},${v},${r() * alpha})`;
    const w = 1 + r() * 3;
    g.fillRect(r() * s, r() * s, w, w);
  }
}

const TEX = {
  ground: canvasTex(512, (g, s) => {
    g.fillStyle = '#8b877d'; g.fillRect(0, 0, s, s);
    speckle(g, s, 9000, 0.18, 7);
    const r = rng(3);
    for (let y = 0; y < 4; y++) for (let x = 0; x < 4; x++) {
      const v = 120 + Math.floor(r() * 25);
      g.fillStyle = `rgba(${v},${v - 3},${v - 10},0.25)`;
      g.fillRect(x * 128 + 2, y * 128 + 2, 124, 124);
    }
    g.strokeStyle = 'rgba(40,36,30,.55)'; g.lineWidth = 3;
    for (let i = 0; i <= 4; i++) {
      g.beginPath(); g.moveTo(i * 128, 0); g.lineTo(i * 128, s); g.stroke();
      g.beginPath(); g.moveTo(0, i * 128); g.lineTo(s, i * 128); g.stroke();
    }
  }),
  wall: canvasTex(512, (g, s) => {
    g.fillStyle = '#a19d94'; g.fillRect(0, 0, s, s);
    speckle(g, s, 12000, 0.15, 11);
    g.fillStyle = 'rgba(0,0,0,.22)';
    g.fillRect(0, 0, s, 4); g.fillRect(0, s / 2, s, 3); g.fillRect(0, 0, 3, s);
    const r = rng(5);
    for (let i = 0; i < 6; i++) {
      g.fillStyle = 'rgba(70,60,50,.08)';
      g.fillRect(r() * s, s / 2, 6 + r() * 20, s / 2 * r());
    }
  }),
  concrete: canvasTex(512, (g, s) => {
    g.fillStyle = '#c2baab'; g.fillRect(0, 0, s, s);
    speckle(g, s, 10000, 0.12, 13);
    g.fillStyle = 'rgba(0,0,0,.18)';
    g.fillRect(0, 0, s, 3); g.fillRect(0, 0, 3, s);
    g.fillStyle = 'rgba(0,0,0,.06)';
    for (let i = 0; i < 4; i++) g.beginPath(), g.arc(64 + i * 128, 64 + (i % 2) * 256, 5, 0, 7), g.fill();
  }),
  crate: canvasTex(256, (g, s) => {
    g.fillStyle = '#a47a43'; g.fillRect(0, 0, s, s);
    const r = rng(17);
    for (let i = 0; i < 6; i++) {
      g.fillStyle = `rgba(${90 + r() * 40},${60 + r() * 25},${30},.35)`;
      g.fillRect(0, i * (s / 6), s, s / 6 - 3);
    }
    for (let i = 0; i < 400; i++) {
      g.fillStyle = `rgba(60,35,15,${r() * 0.25})`;
      g.fillRect(r() * s, r() * s, 10 + r() * 40, 1);
    }
    g.strokeStyle = '#5e4022'; g.lineWidth = 20; g.strokeRect(10, 10, s - 20, s - 20);
    g.lineWidth = 16; g.beginPath(); g.moveTo(14, 14); g.lineTo(s - 14, s - 14); g.stroke();
    g.fillStyle = '#3d2a17';
    for (const [x, y] of [[20, 20], [s - 20, 20], [20, s - 20], [s - 20, s - 20]]) g.beginPath(), g.arc(x, y, 4, 0, 7), g.fill();
  }),
  container: canvasTex(256, (g, s) => {
    g.fillStyle = '#e8e8e8'; g.fillRect(0, 0, s, s);
    for (let i = 0; i < 16; i++) {
      const grd = g.createLinearGradient(i * 16, 0, i * 16 + 16, 0);
      grd.addColorStop(0, 'rgba(0,0,0,.18)'); grd.addColorStop(0.5, 'rgba(255,255,255,.12)'); grd.addColorStop(1, 'rgba(0,0,0,.25)');
      g.fillStyle = grd; g.fillRect(i * 16, 0, 16, s);
    }
    speckle(g, s, 2500, 0.2, 23);
    g.fillStyle = 'rgba(90,50,20,.18)';
    const r = rng(31);
    for (let i = 0; i < 30; i++) g.fillRect(r() * s, r() * s, 2 + r() * 6, 8 + r() * 30);
  }),
};

// Scale box UVs to world units so textures don't stretch.
function worldUV(geo, w, h, d, scale) {
  const uv = geo.attributes.uv;
  const dims = [[d, h], [d, h], [w, d], [w, d], [w, h], [w, h]];
  for (let f = 0; f < 6; f++) for (let i = 0; i < 4; i++) {
    const k = f * 4 + i;
    uv.setXY(k, uv.getX(k) * dims[f][0] / scale, uv.getY(k) * dims[f][1] / scale);
  }
}

// =====================================================================
// World
// =====================================================================
const MATS = {
  wall: new THREE.MeshStandardMaterial({ map: TEX.wall, roughness: 0.92 }),
  concrete: new THREE.MeshStandardMaterial({ map: TEX.concrete, roughness: 0.88 }),
  crate: new THREE.MeshStandardMaterial({ map: TEX.crate, roughness: 0.8 }),
};
const containerMats = new Map();

{
  const size = ARENA * 2 + 2;
  const geo = new THREE.PlaneGeometry(size, size);
  geo.attributes.uv.array.forEach((_, i, a) => { a[i] *= size / 8; });
  const ground = new THREE.Mesh(geo, new THREE.MeshStandardMaterial({ map: TEX.ground, roughness: 0.95 }));
  ground.rotation.x = -Math.PI / 2;
  ground.receiveShadow = true;
  scene.add(ground);

  const outer = new THREE.Mesh(new THREE.PlaneGeometry(900, 900), new THREE.MeshStandardMaterial({ color: 0x7d7a72, roughness: 1 }));
  outer.rotation.x = -Math.PI / 2;
  outer.position.y = -0.02;
  scene.add(outer);

  for (const b of BOXES) {
    const w = b.max[0] - b.min[0], h = b.max[1] - b.min[1], d = b.max[2] - b.min[2];
    const geo = new THREE.BoxGeometry(w, h, d);
    let mat;
    if (b.kind === 'crate') mat = MATS.crate;
    else if (b.kind === 'container') {
      worldUV(geo, w, h, d, 2.5);
      if (!containerMats.has(b.tint)) {
        containerMats.set(b.tint, new THREE.MeshStandardMaterial({ map: TEX.container, color: b.tint, roughness: 0.6, metalness: 0.3 }));
      }
      mat = containerMats.get(b.tint);
    } else {
      worldUV(geo, w, h, d, 4);
      mat = MATS[b.kind];
    }
    const m = new THREE.Mesh(geo, mat);
    m.position.set((b.min[0] + b.max[0]) / 2, (b.min[1] + b.max[1]) / 2, (b.min[2] + b.max[2]) / 2);
    m.castShadow = m.receiveShadow = true;
    scene.add(m);
  }

  // Skyline outside the arena (decorative, no collision).
  const r = rng(99);
  const city = new THREE.InstancedMesh(new THREE.BoxGeometry(1, 1, 1),
    new THREE.MeshStandardMaterial({ color: 0x8792a0, roughness: 0.9 }), 70);
  const m4 = new THREE.Matrix4();
  for (let i = 0; i < 70; i++) {
    const a = (i / 70) * Math.PI * 2 + r() * 0.05;
    const dist = 75 + r() * 90;
    const w = 8 + r() * 14, h = 14 + r() * 50;
    m4.compose(
      new THREE.Vector3(Math.cos(a) * dist, h / 2, Math.sin(a) * dist),
      new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(0, 1, 0), r() * Math.PI),
      new THREE.Vector3(w, h, 8 + r() * 14),
    );
    city.setMatrixAt(i, m4);
  }
  scene.add(city);
}

// =====================================================================
// Effects: tracers, impacts, particles
// =====================================================================
const fx = { tracers: [], decals: [], particles: [] };
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

const muzzleTex = canvasTex(128, (g, s) => {
  const grd = g.createRadialGradient(s / 2, s / 2, 0, s / 2, s / 2, s / 2);
  grd.addColorStop(0, 'rgba(255,255,230,1)'); grd.addColorStop(0.25, 'rgba(255,200,90,.9)'); grd.addColorStop(1, 'rgba(255,120,20,0)');
  g.fillStyle = grd;
  g.beginPath();
  for (let i = 0; i < 16; i++) {
    const a = (i / 16) * Math.PI * 2, r = i % 2 ? s * 0.18 : s * 0.5;
    g.lineTo(s / 2 + Math.cos(a) * r, s / 2 + Math.sin(a) * r);
  }
  g.fill();
});

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
// First-person weapons (separate scene so they never clip into walls)
// =====================================================================
const vmScene = new THREE.Scene();
const vmCam = new THREE.PerspectiveCamera(60, innerWidth / innerHeight, 0.01, 10);
vmScene.environment = new THREE.PMREMGenerator(renderer).fromScene(new RoomEnvironment(), 0.04).texture;
vmScene.add(new THREE.HemisphereLight(0xe8f0ff, 0x4a4036, 0.8));
{
  const l = new THREE.DirectionalLight(0xfff0d8, 2.0);
  l.position.set(0.6, 1.5, 0.8);
  vmScene.add(l);
}

const VM = {
  metal: new THREE.MeshStandardMaterial({ color: 0x2e3136, roughness: 0.38, metalness: 0.75 }),
  poly: new THREE.MeshStandardMaterial({ color: 0x3d4238, roughness: 0.7, metalness: 0.1 }),
  tan: new THREE.MeshStandardMaterial({ color: 0x9a8461, roughness: 0.8 }),
  wood: new THREE.MeshStandardMaterial({ color: 0x5d4a33, roughness: 0.6 }),
  glove: new THREE.MeshStandardMaterial({ color: 0x2c2a27, roughness: 0.9 }),
  sleeve: new THREE.MeshStandardMaterial({ color: 0x4d5a3f, roughness: 0.95 }),
  lens: new THREE.MeshBasicMaterial({ color: 0x88ccff, transparent: true, opacity: 0.12, depthWrite: false }),
  dot: new THREE.MeshBasicMaterial({ color: 0xff2020 }),
  flash: new THREE.MeshBasicMaterial({ map: muzzleTex, transparent: true, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide }),
};

function buildWeapon(id) {
  const root = new THREE.Group();
  const model = new THREE.Group();
  root.add(model);
  const box = (w, h, d, mat, x, y, z, rx = 0, ry = 0) => {
    const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat);
    m.position.set(x, y, z); m.rotation.set(rx, ry, 0); model.add(m); return m;
  };
  const cyl = (r, len, mat, x, y, z) => {
    const m = new THREE.Mesh(new THREE.CylinderGeometry(r, r, len, 14), mat);
    m.rotation.x = Math.PI / 2; m.position.set(x, y, z); model.add(m); return m;
  };
  const redDot = (z) => {
    box(0.008, 0.05, 0.05, VM.metal, -0.022, 0.085, z);
    box(0.008, 0.05, 0.05, VM.metal, 0.022, 0.085, z);
    box(0.052, 0.008, 0.05, VM.metal, 0, 0.113, z);
    box(0.052, 0.012, 0.06, VM.metal, 0, 0.062, z);
    const lens = new THREE.Mesh(new THREE.PlaneGeometry(0.036, 0.042), VM.lens);
    lens.position.set(0, 0.088, z - 0.02);
    model.add(lens);
    const dot = new THREE.Mesh(new THREE.SphereGeometry(0.0016, 8, 8), VM.dot);
    dot.position.set(0, 0.088, z - 0.02);
    model.add(dot);
  };
  const arms = (gripZ, foreZ, foreY = -0.045) => {
    box(0.06, 0.06, 0.1, VM.glove, 0, -0.065, gripZ, -0.3);
    box(0.075, 0.075, 0.32, VM.sleeve, 0.05, -0.12, gripZ + 0.2, -0.35);
    if (foreZ !== null) {
      box(0.065, 0.05, 0.11, VM.glove, -0.015, foreY, foreZ);
      box(0.075, 0.075, 0.36, VM.sleeve, -0.12, foreY - 0.075, foreZ + 0.18, -0.2, -0.5);
    }
  };

  let mag, sightY = 0.088, muzzleZ, hip, adsZ, flashScale = 1;
  if (id === 'ar') {
    box(0.066, 0.085, 0.42, VM.metal, 0, 0, 0);
    box(0.074, 0.074, 0.27, VM.tan, 0, 0.004, -0.34);
    for (let i = 0; i < 4; i++) box(0.078, 0.01, 0.03, VM.poly, 0, -0.03, -0.25 - i * 0.06);
    cyl(0.012, 0.22, VM.metal, 0, 0.01, -0.56);
    cyl(0.021, 0.07, VM.metal, 0, 0.01, -0.69);
    mag = box(0.044, 0.17, 0.075, VM.poly, 0, -0.115, -0.07, 0.18);
    box(0.038, 0.11, 0.05, VM.poly, 0, -0.09, 0.12, -0.32);
    box(0.05, 0.085, 0.2, VM.tan, 0, -0.012, 0.3);
    box(0.055, 0.11, 0.03, VM.poly, 0, -0.02, 0.41);
    box(0.03, 0.016, 0.34, VM.metal, 0, 0.05, -0.1);
    redDot(0.04);
    arms(0.1, -0.33);
    muzzleZ = -0.74; hip = new THREE.Vector3(0.19, -0.2, -0.5); adsZ = -0.4;
  } else if (id === 'smg') {
    box(0.06, 0.08, 0.3, VM.metal, 0, 0, -0.02);
    box(0.066, 0.064, 0.14, VM.poly, 0, -0.004, -0.23);
    cyl(0.026, 0.18, VM.metal, 0, 0.008, -0.39);
    mag = box(0.034, 0.22, 0.05, VM.metal, 0, -0.15, -0.09, 0.06);
    box(0.036, 0.1, 0.05, VM.poly, 0, -0.085, 0.08, -0.3);
    box(0.01, 0.012, 0.22, VM.metal, -0.02, 0, 0.22);
    box(0.01, 0.012, 0.22, VM.metal, 0.02, 0, 0.22);
    box(0.05, 0.08, 0.016, VM.poly, 0, -0.015, 0.33);
    box(0.03, 0.016, 0.24, VM.metal, 0, 0.05, -0.05);
    redDot(0.02);
    arms(0.08, -0.22);
    muzzleZ = -0.49; hip = new THREE.Vector3(0.18, -0.19, -0.45); adsZ = -0.38; flashScale = 0.8;
  } else if (id === 'sniper') {
    box(0.064, 0.08, 0.42, VM.metal, 0, 0, 0);
    box(0.07, 0.07, 0.3, VM.wood, 0, -0.008, -0.34);
    cyl(0.013, 0.5, VM.metal, 0, 0.01, -0.68);
    box(0.04, 0.03, 0.07, VM.metal, 0, 0.01, -0.95);
    mag = box(0.05, 0.07, 0.09, VM.poly, 0, -0.07, -0.04);
    box(0.038, 0.11, 0.05, VM.wood, 0, -0.09, 0.13, -0.32);
    box(0.06, 0.11, 0.3, VM.wood, 0, -0.025, 0.33);
    box(0.05, 0.03, 0.14, VM.wood, 0, 0.045, 0.3);
    cyl(0.023, 0.32, VM.metal, 0, 0.088, -0.02);
    cyl(0.032, 0.07, VM.metal, 0, 0.088, -0.2);
    cyl(0.028, 0.05, VM.metal, 0, 0.088, 0.15);
    box(0.02, 0.04, 0.03, VM.metal, 0, 0.055, -0.1);
    box(0.02, 0.04, 0.03, VM.metal, 0, 0.055, 0.07);
    box(0.012, 0.012, 0.05, VM.metal, 0.05, 0.01, 0.08, 0, 1.2);
    arms(0.11, -0.34);
    sightY = 0.088; muzzleZ = -0.99; hip = new THREE.Vector3(0.2, -0.21, -0.52); adsZ = -0.3; flashScale = 1.4;
  } else {
    box(0.034, 0.042, 0.21, VM.metal, 0, 0.02, -0.06);
    box(0.032, 0.024, 0.17, VM.poly, 0, -0.01, -0.05);
    box(0.032, 0.11, 0.05, VM.poly, 0, -0.07, 0.03, -0.25);
    mag = box(0.028, 0.025, 0.045, VM.metal, 0, -0.125, 0.045, -0.25);
    box(0.006, 0.012, 0.008, VM.metal, 0, 0.046, -0.155);
    box(0.008, 0.012, 0.008, VM.metal, -0.01, 0.046, 0.04);
    box(0.008, 0.012, 0.008, VM.metal, 0.01, 0.046, 0.04);
    box(0.06, 0.06, 0.1, VM.glove, 0.0, -0.07, 0.04, -0.3);
    box(0.06, 0.05, 0.09, VM.glove, -0.025, -0.08, 0.02, -0.3);
    box(0.075, 0.075, 0.32, VM.sleeve, 0.04, -0.13, 0.24, -0.35);
    box(0.075, 0.075, 0.32, VM.sleeve, -0.09, -0.14, 0.22, -0.35, -0.4);
    sightY = 0.05; muzzleZ = -0.17; hip = new THREE.Vector3(0.15, -0.16, -0.38); adsZ = -0.34; flashScale = 0.7;
  }

  const flash = new THREE.Group();
  for (let i = 0; i < 3; i++) {
    const p = new THREE.Mesh(new THREE.PlaneGeometry(0.22, 0.22), VM.flash);
    p.rotation.set(i === 0 ? 0 : Math.PI / 2, i === 2 ? Math.PI / 2 : 0, 0);
    if (i > 0) p.scale.set(1, 2, 1), p.position.z = -0.08;
    flash.add(p);
  }
  flash.scale.setScalar(flashScale);
  flash.position.set(0, 0.01, muzzleZ);
  flash.visible = false;
  model.add(flash);
  root.visible = false;
  vmScene.add(root);
  return { root, model, mag, magBase: mag.position.clone(), flash, muzzleZ, hip, ads: new THREE.Vector3(0, -sightY, adsZ) };
}
const viewModels = WEAPONS.map((w) => buildWeapon(w.id));

// =====================================================================
// Remote players
// =====================================================================
const avatarGeo = {
  leg: new THREE.BoxGeometry(0.2, 0.9, 0.22).translate(0, -0.45, 0),
  torso: new THREE.BoxGeometry(0.56, 0.62, 0.32),
  vest: new THREE.BoxGeometry(0.6, 0.42, 0.36),
  pack: new THREE.BoxGeometry(0.4, 0.4, 0.14),
  head: new THREE.BoxGeometry(0.3, 0.32, 0.3),
  helmet: new THREE.BoxGeometry(0.36, 0.16, 0.36),
  visor: new THREE.BoxGeometry(0.26, 0.07, 0.02),
  arm: new THREE.BoxGeometry(0.14, 0.14, 0.5).translate(0, 0, -0.22),
  guns: [0.7, 0.5, 0.95, 0.26].map((len) => new THREE.BoxGeometry(0.07, 0.1, len).translate(0, 0, -0.2 - len / 2)),
};
const avatarMats = {
  skin: new THREE.MeshStandardMaterial({ color: 0xc99a76, roughness: 0.75 }),
  pants: new THREE.MeshStandardMaterial({ color: 0x3a3f36, roughness: 0.9 }),
  dark: new THREE.MeshStandardMaterial({ color: 0x24262a, roughness: 0.6, metalness: 0.4 }),
  visor: new THREE.MeshStandardMaterial({ color: 0x111111, roughness: 0.2, metalness: 0.8 }),
};

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
  s.position.y = 2.25;
  return s;
}

class Avatar {
  constructor(id, name, hue) {
    this.id = id; this.name = name; this.hue = hue;
    this.buf = [];
    this.alive = true; this.hp = 100; this.protect = false; this.weapon = 0;
    this.deathT = 0; this.walk = 0; this.stepDist = 0; this.speed = 0;
    this.pos = new THREE.Vector3(); this.yaw = 0; this.pitch = 0;
    this.flashT = 0; this.lastShotT = -1e9;

    const team = new THREE.MeshStandardMaterial({ color: new THREE.Color().setHSL(hue / 360, 0.55, 0.45), roughness: 0.8 });
    this.teamMat = team;
    const root = new THREE.Group();
    const body = new THREE.Group();
    root.add(body);
    const mesh = (geo, mat, x, y, z, parent = body) => {
      const m = new THREE.Mesh(geo, mat);
      m.position.set(x, y, z); m.castShadow = true; parent.add(m); return m;
    };
    this.legL = mesh(avatarGeo.leg, avatarMats.pants, -0.13, 0.92, 0);
    this.legR = mesh(avatarGeo.leg, avatarMats.pants, 0.13, 0.92, 0);
    mesh(avatarGeo.torso, avatarMats.pants, 0, 1.2, 0);
    mesh(avatarGeo.vest, team, 0, 1.3, 0);
    mesh(avatarGeo.pack, avatarMats.pants, 0, 1.3, 0.24);
    this.headG = new THREE.Group();
    this.headG.position.set(0, 1.66, 0);
    body.add(this.headG);
    mesh(avatarGeo.head, avatarMats.skin, 0, 0, 0, this.headG);
    mesh(avatarGeo.helmet, team, 0, 0.14, 0, this.headG);
    mesh(avatarGeo.visor, avatarMats.visor, 0, 0.03, -0.155, this.headG);
    this.armsG = new THREE.Group();
    this.armsG.position.set(0, 1.45, 0);
    body.add(this.armsG);
    mesh(avatarGeo.arm, team, -0.3, 0, 0, this.armsG).rotation.y = -0.35;
    mesh(avatarGeo.arm, team, 0.3, 0, 0, this.armsG).rotation.y = 0.35;
    this.guns = avatarGeo.guns.map((g, i) => {
      const m = mesh(g, avatarMats.dark, 0.08, 0.02, 0, this.armsG);
      m.visible = i === 0;
      return m;
    });
    const fl = new THREE.Sprite(new THREE.SpriteMaterial({ map: muzzleTex, blending: THREE.AdditiveBlending, depthWrite: false, transparent: true }));
    fl.position.set(0.08, 0.02, -0.95);
    fl.scale.setScalar(0.5);
    fl.visible = false;
    this.armsG.add(fl);
    this.flash = fl;
    this.tag = nameSprite(name, hue);
    root.add(this.tag);
    this.body = body;
    this.root = root;
    scene.add(root);
  }
  push(t, x, y, z, yaw, pitch) {
    this.buf.push({ t, x, y, z, yaw, pitch });
    if (this.buf.length > 30) this.buf.shift();
  }
  setWeapon(w) {
    if (w === this.weapon || !this.guns[w]) return;
    this.guns[this.weapon].visible = false;
    this.guns[w].visible = true;
    this.weapon = w;
    this.flash.position.z = -0.25 - avatarGeo.guns[w].parameters.depth;
  }
  muzzleWorld(out) {
    this.root.updateMatrixWorld();
    return this.flash.getWorldPosition(out);
  }
  update(dt, renderT) {
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
        this.walk += moved * 2.2;
        this.stepDist += moved;
        if (this.stepDist > 2.4 && this.alive && moved / Math.max(dt, 1e-3) > 4.5) {
          this.stepDist = 0;
          audio.step(this.pos);
        }
        this.speed = damp(this.speed, moved / Math.max(dt, 1e-3), 10, dt);
      }
    }
    this.root.position.copy(this.pos);
    this.root.rotation.y = this.yaw;
    const swing = Math.sin(this.walk) * clamp(this.speed / 6, 0, 1) * 0.7;
    this.legL.rotation.x = swing;
    this.legR.rotation.x = -swing;
    this.armsG.rotation.x = this.pitch;
    this.headG.rotation.x = this.pitch * 0.6;

    if (!this.alive) {
      this.deathT += dt;
      const k = Math.min(1, this.deathT / 0.35);
      this.body.rotation.x = -k * Math.PI / 2;
      this.body.position.y = -k * 0.1;
      this.root.visible = this.deathT < 2.6;
      this.tag.visible = false;
    } else {
      this.body.rotation.x = 0; this.body.position.y = 0;
      this.root.visible = true; this.tag.visible = true;
      this.teamMat.emissive.setHex(this.protect ? 0x223355 : 0x000000);
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
    this.tag.material.map.dispose();
    this.tag.material.dispose();
    this.flash.material.dispose();
    this.teamMat.dispose();
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
  connect(name) {
    const ws = new WebSocket((location.protocol === 'https:' ? 'wss://' : 'ws://') + location.host);
    this.ws = ws;
    ws.onopen = () => ws.send(JSON.stringify({ t: 'join', name, w: settings.primary }));
    ws.onmessage = (e) => onMessage(JSON.parse(e.data));
    ws.onclose = () => {
      playing = false;
      if (document.pointerLockElement) document.exitPointerLock();
      $('hud').classList.add('hidden');
      $('menu').classList.remove('hidden');
      $('online').textContent = '서버와 연결이 끊어졌습니다. 다시 시작해 주세요.';
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

const playerInfo = (id) => names.get(id);
const addAvatar = (id, name, hue) => { if (!avatars.has(id)) avatars.set(id, new Avatar(id, name, hue)); };

function onMessage(m) {
  switch (m.t) {
    case 'welcome':
      me.id = m.id;
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
  sky.position.copy(camera.position);
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
  for (const av of avatars.values()) av.update(dt, renderT);
  updateFx(dt);
  if (playing) { hud.update(dt); mini.draw(); }

  if (!me.alive && playing) {
    $('deathtimer').textContent = `리스폰까지 ${Math.max(0, (deathUntil - now) / 1000).toFixed(1)}초`;
  }
  if (roundEndAt) $('roundtimer').textContent = `다음 라운드 ${Math.max(0, Math.ceil((roundEndAt - now) / 1000))}초`;

  fpsAcc += dt; fpsN++;
  if (fpsAcc > 0.5) { $('fps').textContent = Math.round(fpsN / fpsAcc) + ' fps'; fpsAcc = 0; fpsN = 0; }

  renderer.clear();
  renderer.render(scene, camera);
  renderer.clearDepth();
  if (playing) renderer.render(vmScene, vmCam);
}

addEventListener('resize', () => {
  renderer.setSize(innerWidth, innerHeight);
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
  $('online').textContent = `현재 접속자 ${s.players}/${s.max}명`;
}).catch(() => { $('online').textContent = ''; });

function start() {
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
  net.connect(name);
  lock();
}
$('play').addEventListener('click', start);
$('name').addEventListener('keydown', (e) => { if (e.code === 'Enter') start(); });

// Debug hook for automated browser tests (?debug).
if (new URLSearchParams(location.search).has('debug')) {
  window.__sz = { me, keys, mouse, avatars, switchSlot, setLocked: (v) => { locked = v; } };
}

frame();
