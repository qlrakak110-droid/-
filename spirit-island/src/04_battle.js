// ============================================================================
//  battle: arena scene, turn engine, move FX, catching, evolution
// ============================================================================
function josa(w, pair) {
  const c = w.charCodeAt(w.length - 1);
  const has = c >= 0xac00 && c <= 0xd7a3 ? (c - 0xac00) % 28 : 0;
  if (pair === '으로') return w + (has === 0 || has === 8 ? '로' : '으로');
  return w + (has ? pair[0] : pair[1]);
}
const STAT_N = { atk: '공격', def: '방어', spd: '속도' };

const Battle = {
  scene: null, camera: null, fx: null, active: false, shake: 0,
  A: new THREE.Vector3(-2.8, 0, 2.6), F: new THREE.Vector3(3.0, 0, -2.6),
  camPos: new THREE.Vector3(), camLook: new THREE.Vector3(), camBasePos: new THREE.Vector3(), camBaseLook: new THREE.Vector3(),
  camOverride: null, decor: null, t: 0,
};

function buildBattle() {
  const B = Battle;
  const sc = B.scene = new THREE.Scene();
  const cam = B.camera = new THREE.PerspectiveCamera(46, innerWidth / innerHeight, 0.1, 1600); Cams.push(cam);
  sc.fog = new THREE.Fog(0x2a1a40, 28, 140);
  B.hemi = new THREE.HemisphereLight(0xc8c0ff, 0x4a3a40, 0.95); sc.add(B.hemi);
  const d = B.sun = new THREE.DirectionalLight(0xffc29a, 2.1); d.position.set(-10, 13, 4); d.castShadow = true;
  d.shadow.mapSize.set(1024, 1024); Object.assign(d.shadow.camera, { left: -10, right: 10, top: 10, bottom: -10, near: 1, far: 50 }); d.shadow.bias = -0.0008; d.shadow.normalBias = 0.03;
  sc.add(d);
  B.rim = new THREE.DirectionalLight(0x9b7bff, 1.6); B.rim.position.set(6, 6, -14); sc.add(B.rim);
  B.skyU = makeSkyUniforms(); B.sky = makeSky(B.skyU); sc.add(B.sky);
  B.ground = new THREE.Mesh(new THREE.CircleGeometry(150, 64).rotateX(-Math.PI / 2), new THREE.MeshLambertMaterial({ color: 0x4f9a4a }));
  B.ground.receiveShadow = true; sc.add(B.ground);
  const plat = (p) => {
    const g = grp(sc, [p.x, 0, p.z]);
    part(GEO.cyl, M(0x8a8399), g, [0, 0.12, 0], [2.0, 0.26, 2.0]).receiveShadow = true;
    part(GEO.cyl, M(0x6f6884), g, [0, 0.27, 0], [1.75, 0.06, 1.75]).receiveShadow = true;
    const ring = part(GEO.torus, E(0xffd98a, 1.6), g, [0, 0.3, 0], [1.88, 1.88, 1], [Math.PI / 2, 0, 0]);
    g.userData.ring = ring; return g;
  };
  B.platA = plat(B.A); B.platF = plat(B.F);
  B.fx = new Particles(sc, 2400);
}

const THEMES = {
  field:  { ground: 0x4f9a4a, ring: 0xffd98a, crack: null, atm: 'world', decor: 'trees' },
  rift:   { ground: 0x3e2f5a, ring: 0xc77dff, crack: 1.6, atm: 'world', decor: 'rift', crackDir: [0.25, 0.42, -1] },
  void:   { ground: 0x07050d, ring: 0xb04bff, crack: 2.6, atm: { top: 0x010006, mid: 0x14062a, hor: 0x5a1a7a, fog: 0x14082a, stars: 1 }, decor: 'void', crackDir: [0.2, 0.32, -1] },
  being:  { ground: 0x16172e, ring: 0xffd98a, crack: 0, atm: { top: 0x070d2e, mid: 0x26286a, hor: 0xb07a7a, fog: 0x1e1f44, stars: 1 }, decor: 'being' },
};
function setupTheme(name) {
  const B = Battle, T = THEMES[name] || THEMES.field;
  B.theme = name;
  B.ground.material.color.setHex(T.ground);
  B.platA.userData.ring.material = E(T.ring, 1.6); B.platF.userData.ring.material = E(T.ring, 1.6);
  const U = B.skyU;
  if (T.atm === 'world') {
    for (const k of ['uTop', 'uMid', 'uHor']) U[k].value.copy(World.skyU[k].value);
    U.uStars.value = World.skyU.uStars.value;
    B.scene.fog.color.copy(World.scene.fog.color);
    B.sun.color.copy(World.sun.color); B.hemi.color.copy(World.hemi.color);
  } else {
    U.uTop.value.setHex(T.atm.top); U.uMid.value.setHex(T.atm.mid); U.uHor.value.setHex(T.atm.hor); U.uStars.value = T.atm.stars;
    B.scene.fog.color.setHex(T.atm.fog);
    if (name === 'void') { B.sun.color.setHex(0x8a6aff); B.hemi.color.setHex(0x6a4aaa); }
    else { B.sun.color.setHex(0xffe2b8); B.hemi.color.setHex(0x9aa4ff); }
  }
  U.uCrack.value = T.crack === null ? World.skyU.uCrack.value : T.crack;
  const cc = T.atm === 'world' ? World.sky.userData.clouds[0].material.color : new THREE.Color(name === 'void' ? 0x3a1a5a : 0x5a5a9a);
  for (const c of B.sky.userData.clouds) c.material.color.copy(cc);
  U.uCrackDir.value.set(...(T.crackDir || [0.08, 0.5, -1])).normalize();
  B.scene.fog.near = name === 'void' || name === 'being' ? 20 : 30; B.scene.fog.far = name === 'void' || name === 'being' ? 100 : 150;
  if (B.decor) { B.scene.remove(B.decor); }
  B.decor = new THREE.Group(); B.scene.add(B.decor); B.spinners = [];
  const rng = mulberry32(name.length * 77 + 5);
  if (T.decor === 'trees' || T.decor === 'rift') {
    const canM = new THREE.MeshLambertMaterial({ color: T.decor === 'rift' ? 0x4a3a6a : 0x3e8f4a, flatShading: true });
    for (let i = 0; i < 46; i++) {
      const a = rng() * Math.PI * 2, rr = 22 + rng() * 26, x = Math.cos(a) * rr, z = Math.sin(a) * rr - 6;
      if (z > 8 && Math.abs(x) < 20) continue;
      const s = 1.4 + rng() * 1.6;
      part(GEO.cyl, M(0x5a3f2c), B.decor, [x, 1.2 * s, z], [0.25 * s, 2.4 * s, 0.25 * s]);
      if (T.decor === 'rift' && rng() < 0.5) continue;
      if (rng() < 0.5) part(GEO.ico1, canM, B.decor, [x, 3.3 * s, z], 1.6 * s, [rng(), rng(), 0]);
      else for (let k = 0; k < 3; k++) part(new THREE.ConeGeometry(1, 1.6, 7), canM, B.decor, [x, (2.6 + k * 1.1) * s, z], (1.7 - k * 0.4) * s);
    }
    const bushM = new THREE.MeshLambertMaterial({ color: T.decor === 'rift' ? 0x4a3a6a : 0x4f9a4a, flatShading: true });
    for (let i = 0; i < 70; i++) {
      const a = rng() * Math.PI * 2, rr = 4.5 + rng() * 18, x = Math.cos(a) * rr, z = Math.sin(a) * rr;
      if (Math.hypot(x - B.A.x, z - B.A.z) < 2.6 || Math.hypot(x - B.F.x, z - B.F.z) < 2.6) continue;
      const s = 0.35 + rng() * 0.5;
      part(GEO.ico, bushM, B.decor, [x, s * 0.35, z], [s * 1.2, s * 0.75, s * 1.1], [0, rng() * 3, 0]);
    }
    const flM = [E(0xffc6e0, 1.3), E(0xfff1a8, 1.3), E(0xd9c8ff, 1.3)];
    for (let i = 0; i < 90; i++) { const a = rng() * Math.PI * 2, rr = 3 + rng() * 20; part(GEO.octa, flM[i % 3], B.decor, [Math.cos(a) * rr, 0.12, Math.sin(a) * rr], 0.09); }
    if (T.decor === 'rift') {
      for (let i = 0; i < 14; i++) {
        const a = rng() * Math.PI * 2, rr = 8 + rng() * 18;
        const s = part(GEO.octa, voidMat(0xb055ff, 2.2), B.decor, [Math.cos(a) * rr, 2 + rng() * 6, Math.sin(a) * rr - 4], [0.3, 0.8, 0.3]);
        B.spinners.push(s);
      }
    }
  }
  if (T.decor === 'void') {
    for (let i = 0; i < 4; i++) part(GEO.ring, E(0x8a3dff, 1.5 + i * 0.15), B.decor, [0, 0.05, -1], [5 + i * 4, 5 + i * 4, 1], [Math.PI / 2, 0, 0]);
    for (let i = 0; i < 26; i++) {
      const a = rng() * Math.PI * 2, rr = 9 + rng() * 26;
      const s = part(i % 3 ? GEO.dodeca : GEO.octa, voidMat(0xb055ff, 2.4), B.decor, [Math.cos(a) * rr, 1 + rng() * 12, Math.sin(a) * rr - 6], 0.4 + rng() * 1.4, [rng() * 3, rng() * 3, 0]);
      B.spinners.push(s);
    }
  }
  if (T.decor === 'being') {
    for (let i = 0; i < 4; i++) part(GEO.ring, E(0xffd27a, 1.3 + i * 0.1), B.decor, [0, 0.05, -1], [5 + i * 4, 5 + i * 4, 1], [Math.PI / 2, 0, 0]);
    for (let i = 0; i < 10; i++) {
      const a = (i / 10) * Math.PI * 2, rr = 22;
      part(GEO.cyl, M(0xb9b2d6), B.decor, [Math.cos(a) * rr, 6, Math.sin(a) * rr - 4], [0.9, 12, 0.9]);
      const beam = new THREE.Mesh(new THREE.CylinderGeometry(0.6, 1.2, 60, 16, 1, true), new THREE.MeshBasicMaterial({ color: new THREE.Color(1.6, 1.35, 0.8), transparent: true, opacity: 0.18, blending: THREE.AdditiveBlending, depthWrite: false }));
      beam.position.set(Math.cos(a) * rr, 40, Math.sin(a) * rr - 4); B.decor.add(beam);
    }
  }
  B.decor.traverse((o) => { if (o.isMesh && o.material.isMeshToonMaterial) { o.castShadow = true; o.receiveShadow = true; } });
}

// ---------------------------------------------------------------- rig helpers
function rigCenter(r) {
  const s = r.root.scale.x;
  return r.root.position.clone().add(new THREE.Vector3(0, ((r.float || 0) + r.size * 0.42) * s, 0));
}
function rigTop(r) { const s = r.root.scale.x; return r.root.position.clone().add(new THREE.Vector3(0, ((r.float || 0) + r.size) * s, 0)); }
function placeRig(r, side) {
  const B = Battle, p = side === 'ally' ? B.A : B.F, o = side === 'ally' ? B.F : B.A;
  const legend = SPECIES[r.sp].legend;
  const s = side === 'ally' ? (legend ? 0.6 : 1.1) : (legend ? 1.18 : 1.45);
  r.root.scale.setScalar(s);
  r.root.position.set(p.x, 0.32, p.z);
  r.root.rotation.y = Math.atan2(o.x - p.x, o.z - p.z) + (side === 'ally' ? 0.25 : -0.3);
  r.home = r.root.position.clone(); r.baseScale = s;
  B.scene.add(r.root);
}
function popAt(pos, html, cls = '') {
  const v = pos.clone().project(Battle.camera);
  const el = document.createElement('div'); el.className = 'pop ' + cls; el.innerHTML = html;
  el.style.left = ((v.x + 1) / 2 * innerWidth) + 'px'; el.style.top = ((1 - v.y) / 2 * innerHeight) + 'px';
  $('#pops').appendChild(el); setTimeout(() => el.remove(), 1200);
}
function flashScreen(color = '#fff', peak = 0.85, dur = 0.35) {
  const f = $('#flash'); f.style.background = color;
  return Tw.add(dur, (k) => { f.style.opacity = String(peak * (1 - k)); }, ease.lin);
}
async function hitReact(r, strong = false) {
  flashRig(r, true); await wait(0.07); flashRig(r, false); await wait(0.05); flashRig(r, true); await wait(0.06); flashRig(r, false);
  const h = r.home.clone();
  Battle.shake = Math.max(Battle.shake, strong ? 0.45 : 0.22);
  await Tw.add(0.3, (k) => { r.root.position.x = h.x + Math.sin(k * 40) * 0.14 * (1 - k); }, ease.lin);
  r.root.position.copy(h);
}
async function lunge(r, target, frac = 0.7) {
  const h = r.home.clone(), to = h.clone().lerp(target, frac); to.y = h.y + 0.2;
  await Tw.add(0.16, (k) => r.root.position.lerpVectors(h, to, k), ease.in);
  const back = Tw.add(0.3, (k) => r.root.position.lerpVectors(to, h, k), ease.out);
  return back;
}
function tmpMesh(geo, color, intensity = 3, extra = {}) {
  const m = new THREE.Mesh(geo, new THREE.MeshBasicMaterial(Object.assign({ color: new THREE.Color(color).multiplyScalar(intensity), transparent: true, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide }, extra)));
  Battle.scene.add(m); return m;
}
function killMesh(m) { Battle.scene.remove(m); m.material.dispose(); }

// ---------------------------------------------------------------- move FX
async function playFx(mv, uRig, tRig) {
  const B = Battle, M = MOVES[mv], col = TYPES[M.t].hex;
  const from = rigCenter(uRig), to = rigCenter(tRig);
  const sfx = { fire: 'fire', water: 'water', grass: 'grass', thunder: 'thunder', earth: 'earth', light: 'light', shadow: 'shadow', void: 'void', being: 'light', normal: 'whoosh' }[M.t];
  switch (M.fx) {
    case 'dash': {
      Snd.fx('whoosh');
      for (let i = 0; i < 18; i++) B.fx.emit({ x: from.x + rand(-0.3, 0.3), y: from.y + rand(-0.3, 0.3), z: from.z + rand(-0.3, 0.3), vx: rand(-1, 1), vy: rand(0, 1.5), vz: rand(-1, 1), color: col, size: 0.35, life: 0.5 });
      const back = await lunge(uRig, tRig.root.position, 0.62);
      Snd.fx(sfx === 'whoosh' ? 'hit' : sfx);
      B.fx.burst(to, 40, { color: [col, 0xffffff], speed: 7, size: 0.4, life: 0.6, drag: 3 });
      await back; break;
    }
    case 'slash': {
      Snd.fx('whoosh');
      for (let i = 0; i < 3; i++) {
        const arc = tmpMesh(new THREE.TorusGeometry(0.9, 0.05, 6, 28, Math.PI * 0.8), col, 3.2);
        arc.position.copy(to); arc.lookAt(B.camera.position); arc.rotateZ(rand(-1.2, 1.2) + i * 1.1);
        Tw.add(0.28, (k) => { arc.scale.setScalar(0.5 + k * 1.1); arc.material.opacity = 1 - k; }, ease.out).then(() => killMesh(arc));
        B.fx.burst(to, 14, { color: [col, 0xffffff], speed: 5, size: 0.28, life: 0.4 });
        await wait(0.09);
      }
      Snd.fx('hit'); break;
    }
    case 'bolt': {
      Snd.fx(sfx);
      const orb = tmpMesh(GEO.sphere, col, 3.4, { blending: THREE.NormalBlending }); orb.scale.setScalar(0.22);
      const core = tmpMesh(GEO.sphere, 0xffffff, 3, { blending: THREE.NormalBlending }); core.scale.setScalar(0.12);
      const mid = from.clone().lerp(to, 0.5); mid.y += 1.3;
      await Tw.add(0.38, (k) => {
        const a = from.clone().lerp(mid, k), b = mid.clone().lerp(to, k), p = a.lerp(b, k);
        orb.position.copy(p); core.position.copy(p);
        B.fx.emit({ x: p.x, y: p.y, z: p.z, vx: rand(-0.5, 0.5), vy: rand(-0.5, 0.5), vz: rand(-0.5, 0.5), color: col, size: 0.35, life: 0.35 });
      }, ease.lin);
      killMesh(orb); killMesh(core);
      B.fx.burst(to, 46, { color: [col, 0xffffff], speed: 6.5, size: 0.42, life: 0.6, drag: 3 });
      break;
    }
    case 'burst': {
      Snd.fx(sfx);
      for (let i = 0; i < 26; i++) B.fx.emit({ x: from.x, y: from.y, z: from.z, vx: rand(-2, 2), vy: rand(1, 3), vz: rand(-2, 2), color: col, size: 0.35, life: 0.5, to, toK: 30 });
      await wait(0.3);
      const sh = tmpMesh(GEO.sphere, col, 2.2); sh.position.copy(to);
      const ring = tmpMesh(GEO.torus, col, 3); ring.position.set(to.x, 0.4, to.z); ring.rotation.x = Math.PI / 2;
      B.fx.burst(to, 110, { color: [col, 0xffffff, col], speed: 10, size: 0.55, life: 0.9, drag: 2.4 });
      B.shake = 0.5;
      await Tw.add(0.5, (k) => { sh.scale.setScalar(0.3 + k * 2.4); sh.material.opacity = 1 - k; ring.scale.setScalar(0.5 + k * 4); ring.material.opacity = 1 - k; }, ease.out);
      killMesh(sh); killMesh(ring); break;
    }
    case 'beam': {
      Snd.fx(sfx);
      const dir = to.clone().sub(from), L = dir.length();
      const beam = tmpMesh(new THREE.CylinderGeometry(0.2, 0.2, 1, 16, 1, true), col, 3);
      const core = tmpMesh(new THREE.CylinderGeometry(0.08, 0.08, 1, 10, 1, true), 0xffffff, 3);
      for (const b of [beam, core]) { b.position.copy(from).addScaledVector(dir, 0.5); b.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), dir.clone().normalize()); b.scale.set(0.01, L, 0.01); }
      await Tw.add(0.12, (k) => { beam.scale.set(k * 1.4, L, k * 1.4); core.scale.set(k, L, k); }, ease.out);
      for (let i = 0; i < 12; i++) { B.fx.burst(to, 6, { color: [col, 0xffffff], speed: 6, size: 0.35, life: 0.4 }); const p = from.clone().lerp(to, Math.random()); B.fx.emit({ x: p.x, y: p.y, z: p.z, vx: rand(-1, 1), vy: rand(-1, 1), vz: rand(-1, 1), color: col, size: 0.3, life: 0.4 }); await wait(0.025); }
      B.shake = 0.3;
      await Tw.add(0.25, (k) => { beam.scale.set((1 - k) * 1.4, L, (1 - k) * 1.4); core.scale.set(1 - k, L, 1 - k); }, ease.in);
      killMesh(beam); killMesh(core); break;
    }
    case 'rain': {
      Snd.fx(sfx);
      for (let i = 0; i < 70; i++) B.fx.emit({ x: to.x + rand(-1.6, 1.6), y: to.y + rand(4, 7), z: to.z + rand(-1.6, 1.6), vy: -rand(12, 16), drag: 0, color: [col, 0xffffff][i % 2], size: 0.32, life: 0.45 });
      await wait(0.38);
      B.fx.burst(to, 60, { color: [col, 0xffffff], speed: 6, size: 0.4, life: 0.6, flat: true });
      B.shake = 0.3; break;
    }
    case 'strike': {
      Snd.fx('thunder');
      for (let f = 0; f < 3; f++) {
        const pts = []; let x = to.x + rand(-1, 1), z = to.z + rand(-1, 1);
        for (let y = 16; y > to.y; y -= 1.2) { pts.push(new THREE.Vector3(x, y, z)); x += rand(-0.7, 0.7); z += rand(-0.7, 0.7); }
        pts.push(to.clone());
        const ln = new THREE.Line(new THREE.BufferGeometry().setFromPoints(pts), new THREE.LineBasicMaterial({ color: new THREE.Color(3, 3, 2.2) }));
        B.scene.add(ln); flashScreen('#fff8d0', 0.5, 0.12);
        await wait(0.07); B.scene.remove(ln); ln.geometry.dispose(); await wait(0.05);
      }
      B.fx.burst(to, 80, { color: [0xffe066, 0xffffff], speed: 9, size: 0.45, life: 0.6 });
      B.shake = 0.5; break;
    }
    case 'aura': {
      Snd.fx('aura');
      const base = uRig.root.position.clone();
      const ring = tmpMesh(GEO.torus, col, 3); ring.position.set(base.x, 0.45, base.z); ring.rotation.x = Math.PI / 2;
      for (let i = 0; i < 50; i++) { const a = Math.random() * 6.28, rr = rand(0.6, 1.4); B.fx.emit({ x: base.x + Math.cos(a) * rr, y: 0.4, z: base.z + Math.sin(a) * rr, vy: rand(2, 5), drag: 0.5, color: [col, 0xffffff][i % 2], size: 0.3, life: 1 }); }
      await Tw.add(0.7, (k) => { ring.scale.setScalar(0.4 + k * 1.8); ring.material.opacity = 1 - k; uRig.root.scale.setScalar(uRig.baseScale * (1 + Math.sin(k * Math.PI) * 0.12)); }, ease.out);
      killMesh(ring); uRig.root.scale.setScalar(uRig.baseScale); break;
    }
    case 'glare': {
      Snd.fx(M.t === 'thunder' ? 'thunder' : 'shadow');
      await Tw.add(0.2, (k) => uRig.root.scale.setScalar(uRig.baseScale * (1 + Math.sin(k * Math.PI) * 0.15)));
      const ring = tmpMesh(GEO.torus, col, 2.8); ring.position.copy(to); ring.lookAt(B.camera.position);
      await Tw.add(0.4, (k) => { ring.scale.setScalar(2.4 - k * 2.2); ring.material.opacity = k; }, ease.in);
      killMesh(ring);
      B.fx.burst(to, 30, { color: col, speed: 4, size: 0.35, life: 0.5 }); break;
    }
    case 'heal': {
      Snd.fx('heal');
      const c = rigCenter(uRig);
      const glow = tmpMesh(GEO.sphere, col === 0x3fa7ff ? 0x9cf0ff : 0xfff1a8, 1.4); glow.position.copy(c);
      for (let i = 0; i < 60; i++) { const a = Math.random() * 6.28, rr = rand(0.4, 1.3); B.fx.emit({ x: c.x + Math.cos(a) * rr, y: c.y - 1 + Math.random(), z: c.z + Math.sin(a) * rr, vy: rand(1.5, 3.5), drag: 0.3, color: [0x9dffb0, 0xfff1a8, 0xffffff][i % 3], size: 0.28, life: 1.1 }); }
      await Tw.add(0.8, (k) => { glow.scale.setScalar(0.5 + k * 1.4); glow.material.opacity = Math.sin(k * Math.PI) * 0.6; });
      killMesh(glow); break;
    }
    case 'drain': {
      Snd.fx(sfx);
      B.fx.burst(to, 30, { color: col, speed: 5, size: 0.4, life: 0.5 });
      for (let i = 0; i < 60; i++) B.fx.emit({ x: to.x + rand(-0.6, 0.6), y: to.y + rand(-0.6, 0.6), z: to.z + rand(-0.6, 0.6), vx: rand(-3, 3), vy: rand(0, 4), vz: rand(-3, 3), drag: 1, color: [col, 0x9dffb0][i % 2], size: 0.32, life: 1.2, to: from, toK: 14 });
      await wait(0.75); break;
    }
    case 'void': {
      Snd.fx('void');
      const big = mv === 'collapse';
      const sph = new THREE.Mesh(GEO.sphere, voidMat(0xd06bff, 1.8, 0x000000, 3)); sph.position.copy(to); sph.scale.setScalar(0.01); B.scene.add(sph);
      const ring = tmpMesh(GEO.torus, 0xd06bff, 3); ring.position.copy(to); ring.lookAt(B.camera.position);
      for (let i = 0; i < (big ? 160 : 80); i++) { const a = Math.random() * 6.28, el = rand(-1, 1), rr = rand(2.5, 5); B.fx.emit({ x: to.x + Math.cos(a) * rr, y: to.y + el * 2.5, z: to.z + Math.sin(a) * rr, drag: 0.2, color: [0xb04bff, 0xff4fd8, 0x6a3dff][i % 3], size: 0.35, life: 0.9, to, toK: 9 }); }
      const R = big ? 2.2 : 1.3;
      if (big) $('#flash').style.background = '#000';
      await Tw.add(0.65, (k) => { sph.scale.setScalar(R * ease.out(k)); ring.scale.setScalar(R * 1.4 * (1 + k * 0.3)); ring.material.opacity = k; if (big) $('#flash').style.opacity = String(k * 0.45); }, ease.lin);
      B.shake = big ? 0.9 : 0.4;
      await Tw.add(0.22, (k) => { sph.scale.setScalar(R * (1 - k)); ring.scale.setScalar(R * 1.8 * (1 - k)); }, ease.in);
      B.scene.remove(sph); killMesh(ring);
      if (big) $('#flash').style.opacity = '0';
      flashScreen('#d9a6ff', big ? 0.9 : 0.4, 0.3);
      B.fx.burst(to, big ? 120 : 50, { color: [0xd06bff, 0xffffff], speed: big ? 12 : 7, size: 0.45, life: 0.7 });
      break;
    }
    case 'genesis': {
      Snd.fx('genesis');
      const pil = tmpMesh(new THREE.CylinderGeometry(1, 1.4, 40, 24, 1, true), 0xffe7a8, 2.6); pil.position.set(to.x, 20, to.z); pil.scale.set(0.01, 1, 0.01);
      for (let i = 0; i < 90; i++) { const a = Math.random() * 6.28; B.fx.emit({ x: to.x + Math.cos(a) * 1.4, y: rand(0, 10), z: to.z + Math.sin(a) * 1.4, vy: -rand(4, 9), drag: 0.1, color: [0xffe08a, 0xffffff], size: 0.4, life: 1 }); }
      await Tw.add(0.45, (k) => pil.scale.set(k * 1.6, 1, k * 1.6), ease.out);
      flashScreen('#fff6dc', 1, 0.7);
      B.shake = 0.9;
      const rings = [0, 1, 2].map(() => { const r = tmpMesh(GEO.torus, 0xffd98a, 3); r.position.set(to.x, 0.5, to.z); r.rotation.x = Math.PI / 2; return r; });
      B.fx.burst(to, 160, { color: [0xffe08a, 0xffffff, 0xfff1c0], speed: 12, size: 0.5, life: 1.1 });
      await Tw.add(0.8, (k) => { rings.forEach((r, i) => { const kk = clamp(k * 1.4 - i * 0.2, 0, 1); r.scale.setScalar(1 + kk * 9); r.material.opacity = 1 - kk; }); pil.material.opacity = 1 - k; }, ease.out);
      killMesh(pil); rings.forEach(killMesh); break;
    }
  }
}

// ---------------------------------------------------------------- panels
function bpRender(side) {
  const B = Battle, m = side === 'ally' ? B.ally : B.foe, el = side === 'ally' ? $('#bpAlly') : $('#bpFoe');
  if (!m) return;
  const sp = SPECIES[m.sp], mh = maxHp(m), f = m.hp / mh;
  const st = m.status === 'burn' ? '<span class="st">화상</span>' : m.status === 'para' ? '<span class="st para">마비</span>' : '';
  let extra = '';
  if (side === 'foe' && B.cfg.kind === 'trainer') extra = `<div class="party-dots">${B.foes.map((x) => `<i class="${x.hp > 0 ? '' : 'out'}"></i>`).join('')}</div>`;
  if (side === 'foe' && B.cfg.kind === 'wild' && S.dex.caught[m.sp]) extra = '<div class="party-dots" title="봉인한 적 있음"><i></i></div>';
  el.className = 'bp ' + side + (sp.legend ? ' legend' + (m.sp === 'ensia' ? ' being' : '') : '');
  el.innerHTML = `<div class="bp-top"><span class="nm">${sp.n}</span><span class="lv">Lv.${m.lv}</span></div>
    <div class="types">${sp.t.map(typeChip).join('')}${st}${extra}</div>
    <div class="hpline"><b>HP</b><div class="bar"><i style="width:${f * 100}%;background:${hpColor(f)}"></i></div></div>
    ${side === 'ally' ? `<div class="hpnum"><span class="hpv">${m.hp}</span> / ${mh}</div><div class="bar xp"><i style="width:${clamp(m.exp / expNeed(m.lv), 0, 1) * 100}%"></i></div>` : ''}`;
  el.dataset.hp = m.hp;
}
function bpShow(side, on) { (side === 'ally' ? $('#bpAlly') : $('#bpFoe')).classList.toggle('off', !on); }
async function animHp(side, from, to) {
  const B = Battle, m = side === 'ally' ? B.ally : B.foe, el = side === 'ally' ? $('#bpAlly') : $('#bpFoe');
  const bar = el.querySelector('.hpline .bar i'), num = el.querySelector('.hpv'), mh = maxHp(m);
  await Tw.add(clamp(Math.abs(from - to) / mh * 1.6, 0.25, 0.9), (k) => {
    const v = lerp(from, to, k), f = v / mh;
    bar.style.transition = 'none'; bar.style.width = (f * 100) + '%'; bar.style.background = hpColor(f);
    if (num) num.textContent = Math.round(v);
  }, ease.out);
}
async function bmsg(text, hold = 1.05) {
  const el = $('#bMsg'); el.textContent = text;
  await Promise.race([wait(hold), nextAction()]);
}
function bmsgSet(text) { $('#bMsg').textContent = text; }

// generic command menu: returns the chosen value
let hotkeyHandler = null;
function onHotkey(code) { if (hotkeyHandler) hotkeyHandler(code); else if (typeof worldHotkey === 'function') worldHotkey(code); }
function menu(items, opts = {}) {
  const box = $('#bCmd'); box.innerHTML = ''; box.classList.toggle('scroll', !!opts.scroll); $('#battleUI').classList.toggle('listing', !!opts.scroll);
  return new Promise((res) => {
    const btns = [];
    const done = (v) => { hotkeyHandler = null; box.innerHTML = ''; $('#battleUI').classList.remove('listing'); res(v); };
    items.forEach((it, i) => {
      const b = document.createElement('button'); b.className = 'cmd ' + (it.cls || ''); b.innerHTML = it.html; b.disabled = !!it.disabled;
      if (it.style) b.style.cssText = it.style;
      b.addEventListener('click', () => { Snd.fx(it.back ? 'back' : 'select'); done(it.value); });
      box.appendChild(b); btns.push(b);
    });
    const first = btns.find((b) => !b.disabled); if (first && !isTouch) first.focus({ preventScroll: true });
    hotkeyHandler = (code) => {
      const n = parseInt(code.replace('Digit', ''), 10);
      if (code.startsWith('Digit') && btns[n - 1] && !btns[n - 1].disabled) btns[n - 1].click();
      if (code === 'Escape' || code === 'KeyX' || code === 'Backspace') { const bi = items.findIndex((x) => x.back); if (bi >= 0) btns[bi].click(); }
      if (code.startsWith('Arrow')) {
        const live = btns.filter((b) => !b.disabled); let i = live.indexOf(document.activeElement);
        i = (i + (code === 'ArrowRight' || code === 'ArrowDown' ? 1 : -1) + live.length) % live.length; live[i].focus();
      }
      if ((code === 'KeyE' || code === 'KeyZ') && btns.includes(document.activeElement)) document.activeElement.click();
    };
  });
}
function monListItem(m, i, disabled, note) {
  const f = m.hp / maxHp(m);
  return { value: i, cls: 'list', disabled, html: `<img src="${Icons.get(m.sp)}" alt=""><div class="grow"><div class="c-t">${monName(m)} <span style="color:var(--muted);font-weight:500;font-size:12px">Lv.${m.lv}${note ? ' · ' + note : ''}</span></div><div class="bar"><i style="width:${f * 100}%;background:${hpColor(f)}"></i></div></div><span class="c-s">${m.hp}/${maxHp(m)}</span>` };
}

// ---------------------------------------------------------------- engine
function effSpd(m) { return stat(m, 3) * stageMul(m.bs.spd) * (m.status === 'para' ? 0.5 : 1); }
function resetStages(m) { m.bs = { atk: 0, def: 0, spd: 0 }; }
function calcDamage(att, def, mv) {
  const M = MOVES[mv];
  const A = stat(att, 1) * stageMul(att.bs.atk) * (att.status === 'burn' ? 0.7 : 1);
  const D = stat(def, 2) * stageMul(def.bs.def);
  const base = Math.floor(((2 * att.lv / 5 + 2) * M.p * A / D) / 50) + 2;
  const stab = monTypes(att).includes(M.t) ? 1.5 : 1;
  const eff = typeEff(M.t, monTypes(def));
  const crit = Math.random() < 1 / 16;
  return { dmg: eff === 0 ? 0 : Math.max(1, Math.floor(base * stab * eff * (crit ? 1.5 : 1) * rand(0.85, 1))), eff, crit };
}
function aiPick(user, target) {
  const mv = user.moves;
  const score = mv.map((id) => {
    const M = MOVES[id];
    if (M.p > 0) return M.p * typeEff(M.t, monTypes(target)) * (monTypes(user).includes(M.t) ? 1.5 : 1) * M.a / 100;
    if (M.eff && M.eff.heal) return user.hp / maxHp(user) < 0.45 ? 140 : 5;
    if (M.eff && M.eff.para) return target.status ? 0 : 45;
    return 38 - (user._statusUses || 0) * 18;
  });
  let best = 0; score.forEach((s, i) => { if (s > score[best]) best = i; });
  const choice = Math.random() < 0.72 ? best : Math.floor(Math.random() * mv.length);
  if (MOVES[mv[choice]].p === 0) user._statusUses = (user._statusUses || 0) + 1;
  return mv[choice];
}
function sideName(side) {
  const B = Battle, m = side === 'ally' ? B.ally : B.foe;
  if (side === 'ally') return monName(m);
  return (B.cfg.kind === 'wild' ? '야생 ' : B.cfg.kind === 'trainer' ? '상대 ' : '') + monName(m);
}
async function changeStage(side, stat, n) {
  const m = side === 'ally' ? Battle.ally : Battle.foe, nm = sideName(side);
  const before = m.bs[stat]; m.bs[stat] = clamp(before + n, -6, 6);
  if (m.bs[stat] === before) { await bmsg(`${nm}의 ${STAT_N[stat]}${n > 0 ? '은(는) 더 오르지 않는다!' : '은(는) 더 내려가지 않는다!'}`); return; }
  const rig = side === 'ally' ? Battle.allyRig : Battle.foeRig, c = rigCenter(rig);
  Battle.fx.burst(c, 24, { color: n > 0 ? 0xffb84a : 0x6aa8ff, speed: 3, size: 0.3, life: 0.7, up: n > 0 ? 2 : -2 });
  await bmsg(`${nm}의 ${josa(STAT_N[stat], '이가')} ${Math.abs(n) > 1 ? '크게 ' : ''}${n > 0 ? '올라갔다!' : '내려갔다!'}`);
}
async function useMove(side, mv) {
  const B = Battle, user = side === 'ally' ? B.ally : B.foe, target = side === 'ally' ? B.foe : B.ally;
  const uRig = side === 'ally' ? B.allyRig : B.foeRig, tRig = side === 'ally' ? B.foeRig : B.allyRig, tSide = side === 'ally' ? 'foe' : 'ally';
  const M = MOVES[mv];
  if (user.status === 'para' && Math.random() < 0.25) {
    B.fx.burst(rigCenter(uRig), 20, { color: 0xffe066, speed: 4, size: 0.3, life: 0.4 }); Snd.fx('thunder');
    await bmsg(`${josa(sideName(side), '은는')} 몸이 저려서 움직일 수 없다!`); return;
  }
  await bmsg(`${sideName(side)}의 ${M.n}!`, 0.55);
  if (Math.random() * 100 >= M.a) {
    await lunge(uRig, tRig.root.position, 0.25);
    await bmsg(`하지만 빗나갔다!`, 0.9); return;
  }
  await playFx(mv, uRig, tRig);
  if (M.p > 0) {
    const { dmg, eff, crit } = calcDamage(user, target, mv);
    if (eff === 0) { await bmsg(`${sideName(tSide)}에게는 전혀 통하지 않는다…`); return; }
    const before = target.hp; target.hp = Math.max(0, target.hp - dmg);
    Snd.fx(crit || eff > 1 ? 'crit' : eff < 1 ? 'weak' : 'hit');
    popAt(rigTop(tRig), `${dmg}${eff > 1 ? '<small>약점!</small>' : eff < 1 ? '<small>반감</small>' : ''}`, eff > 1 || crit ? 'big' : eff < 1 ? 'weak' : '');
    await Promise.all([hitReact(tRig, crit || eff > 1), animHp(tSide, before, target.hp)]);
    if (crit) await bmsg('치명타!', 0.8);
    if (eff > 1) await bmsg('약점을 찔렀다! 효과가 엄청나다!', 0.95);
    else if (eff < 1) await bmsg('상성이 나빠서 효과가 약하다…', 0.95);
    const e = M.eff || {};
    if (e.drain && user.hp > 0) {
      const h = Math.max(1, Math.floor(dmg * e.drain)), b = user.hp; user.hp = Math.min(maxHp(user), user.hp + h);
      if (user.hp > b) { popAt(rigTop(uRig), `+${user.hp - b}`, 'heal'); await animHp(side, b, user.hp); await bmsg(`${josa(sideName(side), '은는')} 힘을 흡수했다!`, 0.8); }
    }
    if (target.hp > 0) {
      if (e.burn && !target.status && !monTypes(target).includes('fire') && Math.random() < e.burn) { target.status = 'burn'; bpRender(tSide); await bmsg(`${josa(sideName(tSide), '은는')} 화상을 입었다!`); }
      if (e.para && !target.status && !monTypes(target).includes('thunder') && Math.random() < e.para) { target.status = 'para'; bpRender(tSide); await bmsg(`${josa(sideName(tSide), '은는')} 마비되었다!`); }
      if (e.reset && (target.bs.atk || target.bs.def || target.bs.spd)) { resetStages(target); await bmsg(`${sideName(tSide)}의 능력 변화가 무(無)로 돌아갔다!`); }
    }
  } else {
    const e = M.eff || {};
    if (e.self) for (const k in e.self) await changeStage(side, k, e.self[k]);
    if (e.foe) for (const k in e.foe) await changeStage(tSide, k, e.foe[k]);
    if (e.heal) {
      const b = user.hp; user.hp = Math.min(maxHp(user), user.hp + Math.floor(maxHp(user) * e.heal));
      if (user.hp > b) { popAt(rigTop(uRig), `+${user.hp - b}`, 'heal'); await animHp(side, b, user.hp); await bmsg(`${josa(sideName(side), '은는')} 체력을 회복했다!`, 0.8); }
      else if (!e.self) await bmsg('하지만 체력이 이미 가득하다!', 0.8);
    }
    if (e.para) {
      if (target.status || monTypes(target).includes('thunder')) await bmsg('하지만 효과가 없었다!');
      else { target.status = 'para'; bpRender(tSide); Snd.fx('thunder'); await bmsg(`${josa(sideName(tSide), '은는')} 마비되었다!`); }
    }
  }
}

async function sendOutAlly(m, first) {
  const B = Battle;
  if (B.allyRig) disposeRig(B.allyRig);
  B.ally = m; resetStages(m); B.participants.add(m.uid);
  B.allyRig = makeSpiritModel(m.sp); placeRig(B.allyRig, 'ally');
  const s = B.allyRig.baseScale; B.allyRig.root.scale.setScalar(0.01);
  const c = B.A.clone(); c.y = 1;
  Snd.fx('absorb');
  B.fx.burst(c, 60, { color: [0xffd98a, 0xffffff, TYPES[monTypes(m)[0]].hex], speed: 6, size: 0.4, life: 0.8 });
  bmsgSet(first ? `가랏, ${monName(m)}!` : `부탁해, ${monName(m)}!`);
  flashRig(B.allyRig, true);
  await Tw.add(0.45, (k) => B.allyRig.root.scale.setScalar(s * ease.back(k)), ease.lin);
  await wait(0.12); flashRig(B.allyRig, false);
  bpRender('ally'); bpShow('ally', true);
  await wait(0.5);
}
async function recallAlly() {
  const B = Battle, r = B.allyRig, s = r.baseScale;
  bmsgSet(`돌아와, ${monName(B.ally)}!`);
  flashRig(r, true);
  await Tw.add(0.35, (k) => r.root.scale.setScalar(s * (1 - k)), ease.in);
  disposeRig(r); B.allyRig = null; bpShow('ally', false);
  await wait(0.3);
}
async function sendOutFoe(m, announce) {
  const B = Battle;
  if (B.foeRig) disposeRig(B.foeRig);
  B.foe = m; resetStages(m);
  S.dex.seen[m.sp] = true;
  B.foeRig = makeSpiritModel(m.sp); placeRig(B.foeRig, 'foe');
  if (announce) {
    const s = B.foeRig.baseScale; B.foeRig.root.scale.setScalar(0.01);
    B.fx.burst(rigCenter(B.foeRig), 50, { color: [0xc77dff, 0xffffff], speed: 6, size: 0.4, life: 0.8 });
    bmsgSet(announce); Snd.fx('absorb');
    await Tw.add(0.45, (k) => B.foeRig.root.scale.setScalar(s * ease.back(k)), ease.lin);
  }
  bpRender('foe'); bpShow('foe', true);
}

async function faintAnim(rig) {
  Snd.fx('faint');
  const s = rig.baseScale, y0 = rig.root.position.y;
  flashRig(rig, true, E(0x9a8fb8, 1));
  Battle.fx.burst(rigCenter(rig), 40, { color: [0x9a8fb8, 0xffffff], speed: 3, size: 0.35, life: 1, up: 1.5 });
  await Tw.add(0.6, (k) => { rig.root.position.y = y0 - k * 1.2; rig.root.scale.setScalar(s * (1 - k * 0.6)); }, ease.in);
  rig.root.visible = false;
}

async function gainExp(foe) {
  const B = Battle;
  const base = Math.floor(SPECIES[foe.sp].xp * foe.lv / 6.2 * (B.cfg.kind !== 'wild' ? 1.5 : 1));
  const list = S.party.filter((m) => B.participants.has(m.uid) && m.hp > 0);
  for (const m of list) {
    const g = m === B.ally ? base : Math.max(1, Math.floor(base / 2));
    m.exp += g;
    await bmsg(`${josa(monName(m), '은는')} 경험치를 ${g} 얻었다!`, 0.85);
    if (m === B.ally) bpRender('ally');
    while (m.exp >= expNeed(m.lv) && m.lv < 60) {
      m.exp -= expNeed(m.lv);
      const oldMax = maxHp(m); m.lv++; m.hp += maxHp(m) - oldMax;
      Snd.fx('levelup');
      if (m === B.ally) { bpRender('ally'); B.fx.burst(rigCenter(B.allyRig), 40, { color: [0xffd98a, 0xffffff], speed: 4, size: 0.35, life: 0.9, up: 2 }); }
      await bmsg(`${monName(m)}의 레벨이 올랐다! Lv.${m.lv}`, 1.1);
      for (const [lv, mv] of SPECIES[m.sp].learn) {
        if (lv !== m.lv || m.moves.includes(mv)) continue;
        await learnMove(m, mv);
      }
      const evo = SPECIES[m.sp].evo; if (evo && m.lv >= evo.lv && !B.evoQueue.includes(m)) B.evoQueue.push(m);
    }
  }
}
async function learnMove(m, mv) {
  if (m.moves.length < 4) { m.moves.push(mv); Snd.fx('confirm'); await bmsg(`${josa(monName(m), '은는')} 새로 ${josa(MOVES[mv].n, '을를')} 배웠다!`, 1.1); return; }
  bmsgSet(`${josa(monName(m), '은는')} ${josa(MOVES[mv].n, '을를')} 배우고 싶어 한다.\n하지만 기술이 이미 4개다. 무엇을 잊을까?`);
  const items = m.moves.map((id, i) => ({ value: i, cls: 'mv', style: `border-left-color:${TYPES[MOVES[id].t].c}`, html: `<span class="c-t">${MOVES[id].n}</span><span class="c-s">${typeChip(MOVES[id].t)} ${MOVES[id].p ? '위력 ' + MOVES[id].p : '변화'}</span>` }));
  items.push({ value: -1, cls: 'back', back: true, html: `<span class="c-t">${MOVES[mv].n} 배우지 않기</span>` });
  const i = await menu(items);
  if (i < 0) { await bmsg(`${josa(monName(m), '은는')} ${josa(MOVES[mv].n, '을를')} 배우지 않았다.`); return; }
  const old = m.moves[i]; m.moves[i] = mv;
  await bmsg(`하나, 둘… 짠! ${josa(monName(m), '은는')} ${josa(MOVES[old].n, '을를')} 잊고 ${josa(MOVES[mv].n, '을를')} 배웠다!`, 1.3);
}

async function evolve(m) {
  const B = Battle, to = SPECIES[m.sp].evo.to;
  bpShow('foe', false); bpShow('ally', false);
  if (B.foeRig) B.foeRig.root.visible = false;
  if (B.allyRig) disposeRig(B.allyRig);
  const old = makeSpiritModel(m.sp); placeRig(old, 'ally'); B.allyRig = old;
  const nu = makeSpiritModel(to); placeRig(nu, 'ally'); nu.root.visible = false;
  const c = rigCenter(old);
  B.camOverride = { pos: new THREE.Vector3(c.x - 3.2, c.y + 1.2, c.z + 4.5), look: c.clone() };
  Snd.play('being');
  await bmsg(`어라…? ${monName(m)}의 모습이…!`, 1.6);
  flashRig(old, true); flashRig(nu, true);
  for (let i = 0; i < 14; i++) {
    const on = i % 2 === 0; old.root.visible = on; nu.root.visible = !on;
    B.fx.burst(c, 14, { color: [0xffd98a, 0xffffff], speed: 3, size: 0.35, life: 0.8, to: c, toK: 5 });
    Snd.fx('select');
    await wait(lerp(0.32, 0.06, i / 13));
  }
  flashScreen('#ffffff', 1, 0.9); Snd.fx('genesis');
  old.root.visible = false; disposeRig(old); nu.root.visible = true; flashRig(nu, false);
  B.allyRig = nu;
  B.fx.burst(c, 180, { color: [0xffd98a, 0xffffff, TYPES[SPECIES[to].t[0]].hex], speed: 10, size: 0.5, life: 1.2 });
  const before = monName(m), oldMax = maxHp(m), prevLearn = new Set(SPECIES[m.sp].learn.map((x) => x[1]));
  m.sp = to; m.hp += maxHp(m) - oldMax;
  S.dex.seen[to] = S.dex.caught[to] = true;
  await bmsg(`축하해! ${josa(before, '은는')} ${josa(SPECIES[to].n, '으로')} 진화했다!`, 2.2);
  for (const [lv, mv] of SPECIES[to].learn) if (lv <= m.lv && !prevLearn.has(mv) && !m.moves.includes(mv)) await learnMove(m, mv);
  B.camOverride = null;
}

// crystals
async function throwCrystal(id) {
  const B = Battle, it = ITEMS[id], foe = B.foe, rig = B.foeRig;
  S.items[id]--;
  const gold = id === 'origin';
  await bmsg(`${josa(it.n, '을를')} 던졌다!`, 0.5);
  const cr = new THREE.Mesh(GEO.octa, gold ? E(0xffd98a, 2.8) : E(0x8ff3ff, 2.6)); cr.scale.set(0.22, 0.34, 0.22); B.scene.add(cr);
  const halo = tmpMesh(GEO.torus, gold ? 0xffd98a : 0x8ff3ff, 2); halo.scale.setScalar(0.35);
  const from = B.A.clone().add(new THREE.Vector3(-1.2, 2.2, 2)), to = rigCenter(rig);
  const mid = from.clone().lerp(to, 0.5); mid.y += 2.6;
  Snd.fx('throw');
  await Tw.add(0.6, (k) => {
    const a = from.clone().lerp(mid, k), b = mid.clone().lerp(to, k), p = a.lerp(b, k);
    cr.position.copy(p); halo.position.copy(p); halo.lookAt(B.camera.position); cr.rotation.y += 0.4; cr.rotation.z += 0.2;
    B.fx.emit({ x: p.x, y: p.y, z: p.z, color: gold ? 0xffd98a : 0x8ff3ff, size: 0.25, life: 0.3 });
  }, ease.lin);
  // absorb
  Snd.fx('absorb');
  flashRig(rig, true, gold ? E(0xffd98a, 2.4) : E(0x8ff3ff, 2.4));
  const s = rig.baseScale, c = to.clone();
  for (let i = 0; i < 50; i++) B.fx.emit({ x: c.x + rand(-1, 1), y: c.y + rand(-1, 1), z: c.z + rand(-1, 1), color: gold ? 0xffd98a : 0x8ff3ff, size: 0.35, life: 0.6, to: c, toK: 22 });
  await Tw.add(0.45, (k) => rig.root.scale.setScalar(s * (1 - k)), ease.in);
  rig.root.visible = false;
  const groundY0 = 0.55, top = cr.position.y;
  await Tw.add(0.45, (k) => { cr.position.y = lerp(top, groundY0, k); halo.position.y = cr.position.y; cr.rotation.set(0, cr.rotation.y + 0.1, 0); }, ease.in);
  Snd.fx('wobble');
  const mh = maxHp(foe);
  const a = ((3 * mh - 2 * foe.hp) * SPECIES[foe.sp].rate * it.catch * (foe.status ? 1.5 : 1)) / (3 * mh);
  const p = clamp(a / 255, 0, 1);
  const success = Math.random() < p;
  const wob = success ? 3 : (p > 0.3 ? randi(1, 3) : randi(0, 2));
  for (let i = 0; i < wob; i++) {
    await wait(0.45);
    Snd.fx('wobble');
    await Tw.add(0.4, (k) => { cr.rotation.z = Math.sin(k * Math.PI * 2) * 0.45; }, ease.lin);
  }
  await wait(0.4);
  if (success) {
    Snd.fx('caught');
    B.fx.burst(cr.position, 70, { color: [0xffd98a, 0xffffff, 0x8ff3ff], speed: 5, size: 0.35, life: 1, up: 2 });
    await Tw.add(0.5, (k) => { halo.scale.setScalar(0.35 + k * 1.5); halo.material.opacity = 1 - k; }, ease.out);
    killMesh(halo);
    await bmsg(`좋아! ${josa(monName(foe), '을를')} 봉인했다!`, 1.6);
    B.scene.remove(cr);
    resetStages(foe); delete foe.bs; delete foe._statusUses;
    S.dex.caught[foe.sp] = true;
    if (S.party.length < 6) { S.party.push(foe); await bmsg(`${josa(monName(foe), '이가')} 동료가 되었다!`, 1.1); }
    else { S.box.push(foe); await bmsg(`동료가 가득 차서 ${josa(monName(foe), '은는')} 보관함으로 보내졌다.`, 1.4); }
    return true;
  }
  Snd.fx('break');
  B.fx.burst(cr.position, 50, { color: [gold ? 0xffd98a : 0x8ff3ff, 0xffffff], speed: 7, size: 0.35, life: 0.7 });
  B.scene.remove(cr); killMesh(halo);
  rig.root.visible = true;
  await Tw.add(0.35, (k) => rig.root.scale.setScalar(s * ease.back(k)), ease.lin);
  flashRig(rig, false);
  await bmsg(pick(wob === 0 ? ['앗! 곧바로 튀어나왔다!', '전혀 통하지 않았다…!'] : wob === 1 ? ['아쉽다! 결정이 깨져 버렸다!', '결정에서 빠져나왔다!'] : ['아깝다! 조금만 더…!', '거의 다 됐는데…!']), 1.2);
  return false;
}

// ---------------------------------------------------------------- player action selection
async function chooseAction() {
  const B = Battle;
  while (true) {
    bmsgSet(`${josa(monName(B.ally), '은는')} 무엇을 할까?`);
    const c = await menu([
      { value: 'fight', html: '<span class="c-t">싸운다</span><span class="c-s">기술 선택</span>' },
      { value: 'bag', html: '<span class="c-t">가방</span><span class="c-s">결정 · 회복약</span>' },
      { value: 'party', html: '<span class="c-t">정령</span><span class="c-s">교체</span>' },
      { value: 'run', html: `<span class="c-t">${B.cfg.kind === 'legend' ? '물러난다' : '도망간다'}</span><span class="c-s">${B.cfg.kind === 'trainer' ? '불가' : ''}</span>` },
    ]);
    if (c === 'fight') {
      bmsgSet('어떤 기술을 쓸까?');
      const items = B.ally.moves.map((id) => {
        const M = MOVES[id], eff = M.p ? typeEff(M.t, monTypes(B.foe)) : 1;
        const hint = !M.p ? '변화' : (S.dex.seen[B.foe.sp] ? (eff > 1 ? '효과 좋음' : eff === 0 ? '효과 없음' : eff < 1 ? '효과 약함' : '') : '');
        return { value: id, cls: 'mv', style: `border-left-color:${TYPES[M.t].c}`, html: `<span class="c-t">${M.n}</span><span class="c-s">${typeChip(M.t)} ${M.p ? '위력 ' + M.p : ''} ${hint ? '· ' + hint : ''}</span>` };
      });
      items.push({ value: null, cls: 'back', back: true, html: '<span class="c-t">뒤로</span>' });
      const mv = await menu(items);
      if (mv) return { type: 'move', mv };
    } else if (c === 'bag') {
      const can = (id) => (S.items[id] || 0) > 0;
      const list = [];
      if (B.cfg.kind !== 'trainer') { list.push('crystal'); if (B.cfg.kind === 'legend' || (S.items.origin || 0) > 0) list.push('origin'); }
      list.push('potion', 'elixir');
      bmsgSet('무엇을 사용할까?');
      const items = list.map((id) => ({ value: id, cls: 'list', disabled: !can(id), html: `<div class="grow"><div class="c-t">${ITEMS[id].n}</div><div class="c-s">${ITEMS[id].d}</div></div><span class="c-s" style="font-size:14px;color:var(--gold)">×${S.items[id] || 0}</span>` }));
      items.push({ value: null, cls: 'back', back: true, html: '<span class="c-t">뒤로</span>' });
      const id = await menu(items, { scroll: true });
      if (!id) continue;
      if (ITEMS[id].catch) return { type: 'catch', id };
      bmsgSet('누구에게 사용할까?');
      const pi = S.party.map((m, i) => monListItem(m, i, m.hp <= 0 || (m.hp >= maxHp(m) && !m.status)));
      pi.push({ value: null, cls: 'back', back: true, html: '<span class="c-t">뒤로</span>' });
      const t = await menu(pi, { scroll: true });
      if (t === null || t === undefined) continue;
      return { type: 'heal', id, target: t };
    } else if (c === 'party') {
      const r = await pickParty(false);
      if (r !== null) return { type: 'switch', idx: r };
    } else if (c === 'run') {
      if (B.cfg.kind === 'trainer') { await bmsg('수호자와의 승부에서는 물러설 수 없다!', 1.2); continue; }
      return { type: 'run' };
    }
  }
}
async function pickParty(forced) {
  const B = Battle;
  bmsgSet(forced ? '다음 정령을 골라 주세요.' : '누구로 교체할까?');
  const items = S.party.map((m, i) => monListItem(m, i, m.hp <= 0 || m === B.ally, m === B.ally ? '싸우는 중' : m.hp <= 0 ? '기절' : ''));
  if (!forced) items.push({ value: null, cls: 'back', back: true, html: '<span class="c-t">뒤로</span>' });
  const v = await menu(items, { scroll: true });
  return v === undefined ? null : v;
}

async function endOfTurn() {
  const B = Battle;
  for (const side of ['ally', 'foe']) {
    const m = side === 'ally' ? B.ally : B.foe;
    if (m && m.hp > 0 && m.status === 'burn') {
      const d = Math.max(1, Math.floor(maxHp(m) / 14)), b = m.hp; m.hp = Math.max(0, m.hp - d);
      B.fx.burst(rigCenter(side === 'ally' ? B.allyRig : B.foeRig), 24, { color: 0xff6a2a, speed: 3, size: 0.35, life: 0.6, up: 2 });
      Snd.fx('fire');
      await animHp(side, b, m.hp);
      await bmsg(`${josa(sideName(side), '은는')} 화상 때문에 괴로워한다!`, 0.9);
    }
  }
}
// returns null to continue, or 'win' | 'lose' | 'next'
async function checkFaints() {
  const B = Battle;
  if (B.foe.hp <= 0) {
    await faintAnim(B.foeRig);
    await bmsg(`${josa(sideName('foe'), '은는')} 쓰러졌다!`, 1);
    bpShow('foe', false);
    await gainExp(B.foe);
    B.foeIdx++;
    if (B.cfg.kind === 'trainer' && B.foeIdx < B.foes.length) {
      if (B.ally.hp > 0) {
        await sendOutFoe(B.foes[B.foeIdx], `${josa(B.cfg.trainer.name, '은는')} ${josa(monName(B.foes[B.foeIdx]), '을를')} 내보냈다!`);
        await wait(0.6);
      }
    } else return 'win';
  }
  if (B.ally.hp <= 0) {
    await faintAnim(B.allyRig);
    await bmsg(`${josa(monName(B.ally), '은는')} 쓰러졌다!`, 1);
    bpShow('ally', false);
    if (!S.party.some((m) => m.hp > 0)) return 'lose';
    const idx = await pickParty(true);
    await sendOutAlly(S.party[idx], false);
    return 'next';
  }
  return B.foe.hp <= 0 ? 'next' : null;
}

async function runBattle(cfg) {
  const B = Battle;
  B.active = true; B.cfg = cfg; B.foes = cfg.foes; B.foeIdx = 0; B.participants = new Set(); B.evoQueue = []; B.runTries = 0;
  B.fx.clear(); B.camOverride = null;
  setupTheme(cfg.theme || 'field');
  for (const m of S.party) delete m._statusUses;
  $('#battleUI').hidden = false; bpShow('foe', false); bpShow('ally', false); $('#bCmd').innerHTML = ''; bmsgSet('');
  await sendOutFoe(cfg.foes[0], null);
  const legend = SPECIES[cfg.foes[0].sp].legend;
  setBattleCamera(true);
  const fc = rigCenter(B.foeRig);
  B.camOverride = { pos: new THREE.Vector3(fc.x - 1.2, fc.y + (legend ? 0.2 : 0.4), fc.z + (legend ? 5.2 : 3.4)), look: fc.clone(), k: 20 };
  B.camPos.copy(B.camOverride.pos); B.camLook.copy(B.camOverride.look);
  await wait(0.05);
  B.camOverride.k = legend ? 0.9 : 1.8;
  B.camOverride.pos = new THREE.Vector3(fc.x - 3.5, fc.y + (legend ? 1.0 : 0.8), fc.z + (legend ? 9.5 : 6));
  fadeTo(0, 0.6);
  if (cfg.intro) await cfg.intro();
  else await bmsg(cfg.kind === 'wild' ? `앗! 야생 ${josa(monName(B.foe), '이가')} 나타났다!` : `${josa(cfg.trainer.name, '이가')} 승부를 걸어왔다!`, 1.4);
  if (cfg.kind === 'trainer') await bmsg(`${josa(cfg.trainer.name, '은는')} ${josa(monName(B.foe), '을를')} 내보냈다!`, 1);
  B.camOverride = null;
  bpRender('foe'); bpShow('foe', true);
  await sendOutAlly(S.party.find((m) => m.hp > 0), true);
  let result = null;
  while (!result) {
    const act = await chooseAction();
    const foeMove = aiPick(B.foe, B.ally);
    let foeActs = true, r = null;
    if (act.type === 'run') {
      B.runTries++;
      const ok = cfg.kind === 'legend' || Math.random() < clamp(0.45 + 0.4 * effSpd(B.ally) / Math.max(1, effSpd(B.foe)) + B.runTries * 0.15 - 0.2, 0.25, 1);
      if (ok) { Snd.fx('whoosh'); await bmsg(cfg.kind === 'legend' ? '전설의 기척에서 물러났다… 제단에서 다시 도전할 수 있다.' : '무사히 도망쳤다!', 1.1); result = 'run'; break; }
      await bmsg('도망칠 수 없었다!', 0.9);
    } else if (act.type === 'catch') {
      const caught = await throwCrystal(act.id);
      if (caught) { result = 'caught'; break; }
    } else if (act.type === 'heal') {
      const m = S.party[act.target], it = ITEMS[act.id]; S.items[act.id]--;
      const b = m.hp; m.hp = Math.min(maxHp(m), m.hp + it.heal); if (it.heal > 999) m.status = null;
      Snd.fx('heal');
      if (m === B.ally) { B.fx.burst(rigCenter(B.allyRig), 40, { color: [0x9dffb0, 0xffffff], speed: 3, size: 0.3, life: 0.9, up: 2 }); await animHp('ally', b, m.hp); bpRender('ally'); }
      await bmsg(`${josa(monName(m), '은는')} 체력을 ${m.hp - b} 회복했다!`, 1);
    } else if (act.type === 'switch') {
      await recallAlly(); await sendOutAlly(S.party[act.idx], false);
    } else if (act.type === 'move') {
      const allyFirst = effSpd(B.ally) > effSpd(B.foe) || (effSpd(B.ally) === effSpd(B.foe) && Math.random() < 0.5);
      if (allyFirst) {
        await useMove('ally', act.mv); r = await checkFaints(); if (r) { if (r !== 'next') result = r; foeActs = false; }
      } else {
        await useMove('foe', foeMove); r = await checkFaints(); if (r) { if (r !== 'next') result = r; foeActs = false; }
        if (!r) { await useMove('ally', act.mv); r = await checkFaints(); if (r && r !== 'next') result = r; }
        foeActs = false;
      }
    }
    if (result) break;
    if (foeActs) { await useMove('foe', foeMove); r = await checkFaints(); if (r && r !== 'next') { result = r; break; } }
    if (!r) { await endOfTurn(); r = await checkFaints(); if (r && r !== 'next') { result = r; break; } }
  }
  // aftermath
  if (result === 'win') {
    Snd.play('victory');
    if (cfg.kind === 'trainer') { await bmsg(`${josa(cfg.trainer.name, '과와')}의 승부에서 이겼다!`, 1.3); if (cfg.trainer.lose) await bmsg(`${cfg.trainer.name}: "${cfg.trainer.lose}"`, 2.2); }
    if (cfg.kind === 'legend') await bmsg(`${josa(monName(B.foe), '은는')} 빛 속으로 흩어졌다… 그러나 그 기척은 아직 제단에 남아 있다.`, 2.2);
  }
  if (result === 'lose') { bmsgSet('모든 정령이 쓰러졌다…'); await wait(1.6); }
  if (result !== 'lose') for (const m of B.evoQueue) if (m.hp > 0 && SPECIES[m.sp].evo) await evolve(m);
  for (const m of S.party) { delete m.bs; delete m._statusUses; }
  $('#bCmd').innerHTML = ''; hotkeyHandler = null;
  B.active = false;
  return result;
}

function setBattleCamera(force) {
  const B = Battle, aspect = innerWidth / innerHeight;
  const legend = B.foeRig && SPECIES[B.foeRig.sp].legend;
  B.camera.fov = aspect < 0.8 ? 64 : aspect < 1.2 ? 54 : 44; B.camera.updateProjectionMatrix();
  const back = aspect < 0.8 ? 1.25 : 1;
  B.camBasePos.set(-1.2 * back, 3.3 + (legend ? 1.2 : 0) + (aspect < 0.8 ? 1.4 : 0), 9.6 * back + (legend ? 1.5 : 0));
  B.camBaseLook.set(aspect < 0.8 ? 0.2 : 0.5, 1.25 + (legend ? 1.5 : 0), -1.2);
  if (force) { B.camPos.copy(B.camBasePos); B.camLook.copy(B.camBaseLook); }
}
function updateBattle(dt) {
  const B = Battle; B.t += dt;
  setBattleCamera(false);
  if (B.allyRig) rigUpdate(B.allyRig, dt);
  if (B.foeRig) rigUpdate(B.foeRig, dt);
  for (const s of B.spinners || []) { s.rotation.y += dt * 0.5; s.rotation.x += dt * 0.2; }
  B.fx.update(dt);
  if (B.theme === 'void' && Math.random() < 0.6) B.fx.emit({ x: rand(-12, 12), y: 0, z: rand(-14, 6), vy: rand(1, 3), drag: 0, color: 0x8a3dff, size: 0.3, life: 3 });
  if (B.theme === 'being' && Math.random() < 0.6) B.fx.emit({ x: rand(-12, 12), y: 0, z: rand(-14, 6), vy: rand(1, 2.5), drag: 0, color: 0xffd98a, size: 0.3, life: 3 });
  const o = B.camOverride;
  const tp = o ? o.pos : B.camBasePos.clone().add(new THREE.Vector3(Math.sin(B.t * 0.3) * 0.25, Math.sin(B.t * 0.4) * 0.12, 0));
  const tl = o ? o.look : B.camBaseLook;
  const k = 1 - Math.exp(-(o ? (o.k || 3) : 3) * dt);
  B.camPos.lerp(tp, k); B.camLook.lerp(tl, k);
  B.camera.position.copy(B.camPos); B.camera.lookAt(B.camLook);
  if (B.shake > 0) { B.shake = Math.max(0, B.shake - dt); const s = B.shake * 0.35; B.camera.position.x += rand(-s, s); B.camera.position.y += rand(-s, s); }
  B.sky.position.copy(B.camera.position);
}
