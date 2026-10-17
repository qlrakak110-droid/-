// Detailed procedural models: weapons (first and third person), FPS arms and soldiers.
// Parts are merged per material so a model with hundreds of parts costs a handful of draw calls.
import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';

const { PI } = Math;
const V = (a) => new THREE.Vector3(a[0], a[1], a[2]);
const UP = new THREE.Vector3(0, 1, 0);

class Builder {
  constructor() {
    this.parts = new Map();
    this.m = new THREE.Matrix4();
  }
  static compose(pos = [0, 0, 0], rot = [0, 0, 0], scale = [1, 1, 1]) {
    return new THREE.Matrix4().compose(V(pos), new THREE.Quaternion().setFromEuler(new THREE.Euler(rot[0], rot[1], rot[2])), V(scale));
  }
  /** Run fn with an extra local transform pushed. */
  frame(pos, rot, fn) {
    const prev = this.m;
    this.m = prev.clone().multiply(Builder.compose(pos, rot));
    fn();
    this.m = prev;
  }
  add(geo, mat, pos, rot, scale) {
    let g = geo.index ? geo.toNonIndexed() : geo;
    g.applyMatrix4(this.m.clone().multiply(Builder.compose(pos, rot, scale)));
    if (!this.parts.has(mat)) this.parts.set(mat, []);
    this.parts.get(mat).push(g);
    return this;
  }
  box(w, h, d, mat, pos, rot, r = 0.004) {
    const rr = Math.min(r, Math.min(w, h, d) / 2 - 1e-4);
    const geo = rr > 0.0005 ? new RoundedBoxGeometry(w, h, d, 2, rr) : new THREE.BoxGeometry(w, h, d);
    return this.add(geo, mat, pos, rot);
  }
  /** Cylinder along Z by default (bore axis). */
  cyl(r, len, mat, pos, rot = [PI / 2, 0, 0], r2 = r, seg = 18, open = false) {
    return this.add(new THREE.CylinderGeometry(r2, r, len, seg, 1, open), mat, pos, rot);
  }
  sphere(r, mat, pos, scale, seg = 14) {
    return this.add(new THREE.SphereGeometry(r, seg, Math.ceil(seg * 0.7)), mat, pos, [0, 0, 0], scale);
  }
  /** Capsule spanning two points. */
  limb(a, b, r, mat, seg = 10) {
    const A = V(a), B = V(b), dir = B.clone().sub(A);
    const len = Math.max(0.001, dir.length() - 2 * r * 0.4);
    const g = new THREE.CapsuleGeometry(r, len, 4, seg);
    const q = new THREE.Quaternion().setFromUnitVectors(UP, dir.normalize());
    const mid = A.add(B).multiplyScalar(0.5);
    g.applyQuaternion(q);
    return this.add(g, mat, mid.toArray());
  }
  torus(r, tube, mat, pos, rot) {
    return this.add(new THREE.TorusGeometry(r, tube, 8, 20), mat, pos, rot);
  }
  build({ shadows = true } = {}) {
    const group = new THREE.Group();
    for (const [mat, list] of this.parts) {
      const mesh = new THREE.Mesh(mergeGeometries(list), mat);
      mesh.castShadow = shadows;
      mesh.receiveShadow = shadows;
      group.add(mesh);
    }
    return group;
  }
}

// =====================================================================
// Materials
// =====================================================================
export function createMaterials(T) {
  const std = (o) => new THREE.MeshStandardMaterial(o);
  const camoMap = T.camo.map.clone(), camoN = T.camo.normalMap.clone();
  camoMap.repeat.set(3, 3); camoN.repeat.set(3, 3);
  return {
    gunBlack: std({ color: 0x2c2f33, roughness: 0.36, metalness: 0.55, map: T.gunmetal.map, normalMap: T.gunmetal.normalMap }),
    gunPoly: std({ color: 0x313336, roughness: 0.66, metalness: 0.05, normalMap: T.nylon.normalMap, normalScale: new THREE.Vector2(0.4, 0.4) }),
    gunTan: std({ color: 0x8c775a, roughness: 0.62, metalness: 0.05, normalMap: T.nylon.normalMap, normalScale: new THREE.Vector2(0.3, 0.3) }),
    gunOlive: std({ color: 0x4f5640, roughness: 0.66, metalness: 0.05, normalMap: T.nylon.normalMap, normalScale: new THREE.Vector2(0.3, 0.3) }),
    dark: std({ color: 0x0c0d0e, roughness: 0.6, metalness: 0.3 }),
    glass: std({ color: 0x0a1620, roughness: 0.05, metalness: 0.95 }),
    lens: new THREE.MeshBasicMaterial({ color: 0x9fd6ff, transparent: true, opacity: 0.1, depthWrite: false, side: THREE.DoubleSide }),
    reticle: new THREE.MeshBasicMaterial({ color: 0xff2a2a, toneMapped: false }),
    brass: std({ color: 0xc9973f, roughness: 0.28, metalness: 1 }),
    skin: std({ color: 0xc8987a, roughness: 0.62 }),
    glove: std({ color: 0x2b2924, roughness: 0.85, normalMap: T.nylon.normalMap }),
    knuckle: std({ color: 0x1a1918, roughness: 0.55 }),
    camo: std({ map: camoMap, normalMap: camoN, roughness: 0.9 }),
    boot: std({ color: 0x3a2f25, roughness: 0.7 }),
    sole: std({ color: 0x141312, roughness: 0.9 }),
    strap: std({ color: 0x2d2f2a, roughness: 0.85, normalMap: T.nylon.normalMap }),
    goggle: std({ color: 0x0e0f10, roughness: 0.08, metalness: 0.9 }),
    watch: std({ color: 0x111111, roughness: 0.3, metalness: 0.6 }),
    metalTex: T.metal,
    burlapMat: std({ color: 0xffffff, map: T.burlap.map, normalMap: T.burlap.normalMap, roughness: 0.95 }),
    flash: new THREE.MeshBasicMaterial({ map: T.muzzle, transparent: true, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide, toneMapped: false }),
  };
}

// =====================================================================
// Weapons
// =====================================================================
function rail(B, M, z0, z1, y) {
  const len = z1 - z0;
  B.box(0.022, 0.009, len, M.gunBlack, [0, y, (z0 + z1) / 2], undefined, 0.002);
  for (let z = z0 + 0.006; z < z1 - 0.004; z += 0.011) B.box(0.026, 0.005, 0.005, M.gunBlack, [0, y + 0.006, z], undefined, 0);
}

/**
 * Build a weapon. Returns static body, a separate magazine, reticle/lens meshes and
 * attachment points (grip, fore hand, muzzle, ejection port, sight height).
 */
function buildGunParts(id, M) {
  const B = new Builder(), Mg = new Builder();
  const extras = [];
  const info = { id };
  const lens = (w, h, y, z) => {
    const m = new THREE.Mesh(new THREE.PlaneGeometry(w, h), M.lens);
    m.position.set(0, y, z);
    extras.push(m);
  };
  const dot = (y, z, ring) => {
    const d = new THREE.Mesh(new THREE.CircleGeometry(0.0013, 12), M.reticle);
    d.position.set(0, y, z); d.rotation.y = PI;
    extras.push(d);
    if (ring) {
      const r = new THREE.Mesh(new THREE.RingGeometry(0.0085, 0.0095, 32), M.reticle);
      r.position.set(0, y, z); r.rotation.y = PI;
      extras.push(r);
    }
  };

  if (id === 'ar') {
    // receivers
    B.box(0.056, 0.058, 0.27, M.gunBlack, [0, 0.012, 0], undefined, 0.006);
    B.box(0.05, 0.045, 0.19, M.gunBlack, [0, -0.036, 0.015], undefined, 0.006);
    B.box(0.05, 0.06, 0.075, M.gunBlack, [0, -0.068, -0.055], [0.08, 0, 0], 0.006);
    B.box(0.003, 0.022, 0.055, M.dark, [0.0285, 0.016, -0.005]);
    B.cyl(0.009, 0.024, M.gunBlack, [0.034, 0.026, 0.06], [0, 0, PI / 2]);
    B.box(0.034, 0.012, 0.03, M.gunBlack, [0, 0.046, 0.125], undefined, 0.003);
    B.box(0.054, 0.008, 0.012, M.gunBlack, [0, 0.046, 0.138], undefined, 0.003);
    B.box(0.006, 0.014, 0.024, M.gunBlack, [-0.027, -0.02, 0.05], undefined, 0.002); // selector
    // trigger group
    B.box(0.01, 0.007, 0.075, M.gunBlack, [0, -0.083, 0.045], undefined, 0.002);
    B.box(0.01, 0.03, 0.008, M.gunBlack, [0, -0.07, 0.083], undefined, 0.002);
    B.box(0.004, 0.022, 0.006, M.gunBlack, [0, -0.066, 0.04], [0.3, 0, 0], 0.001);
    // grip, buffer tube, stock
    B.box(0.034, 0.105, 0.046, M.gunPoly, [0, -0.11, 0.1], [-0.3, 0, 0], 0.01);
    B.cyl(0.015, 0.14, M.gunBlack, [0, 0.002, 0.19]);
    B.box(0.046, 0.07, 0.16, M.gunTan, [0, -0.012, 0.28], undefined, 0.012);
    B.box(0.044, 0.022, 0.12, M.gunTan, [0, 0.032, 0.27], undefined, 0.008);
    B.box(0.05, 0.112, 0.024, M.gunPoly, [0, -0.022, 0.37], undefined, 0.008);
    B.box(0.012, 0.02, 0.03, M.gunBlack, [0, -0.06, 0.3], undefined, 0.003); // sling point
    // handguard with M-LOK slots
    B.box(0.066, 0.066, 0.33, M.gunTan, [0, 0.008, -0.3], undefined, 0.012);
    for (let i = 0; i < 5; i++) {
      for (const s of [-1, 1]) B.box(0.004, 0.012, 0.034, M.dark, [s * 0.0335, 0.008, -0.18 - i * 0.055], undefined, 0.0015);
      B.box(0.012, 0.004, 0.034, M.dark, [0, -0.0255, -0.18 - i * 0.055], undefined, 0.0015);
    }
    B.box(0.07, 0.07, 0.012, M.gunBlack, [0, 0.008, -0.135], undefined, 0.004);
    rail(B, M, -0.46, 0.13, 0.045);
    // barrel, gas block, muzzle brake
    B.cyl(0.0105, 0.2, M.gunBlack, [0, 0.008, -0.56]);
    B.box(0.028, 0.034, 0.028, M.gunBlack, [0, 0.012, -0.487], undefined, 0.004);
    B.cyl(0.017, 0.07, M.gunBlack, [0, 0.008, -0.69]);
    for (let i = 0; i < 3; i++) B.box(0.036, 0.006, 0.007, M.dark, [0, 0.021, -0.675 - i * 0.014], undefined, 0);
    // holographic sight
    B.box(0.042, 0.016, 0.085, M.gunBlack, [0, 0.058, 0.03], undefined, 0.004);
    B.box(0.006, 0.052, 0.075, M.gunBlack, [-0.023, 0.088, 0.03], undefined, 0.002);
    B.box(0.006, 0.052, 0.075, M.gunBlack, [0.023, 0.088, 0.03], undefined, 0.002);
    B.box(0.052, 0.008, 0.075, M.gunBlack, [0, 0.117, 0.03], undefined, 0.003);
    B.box(0.03, 0.016, 0.02, M.gunBlack, [0, 0.072, 0.068], undefined, 0.003);
    B.box(0.008, 0.008, 0.012, M.gunBlack, [0.026, 0.07, 0.05], undefined, 0.002);
    lens(0.04, 0.042, 0.091, -0.004);
    dot(0.09, -0.005, true);
    // magazine (curved, three sections)
    {
      // Follow a gentle forward curve: each section continues where the previous one ended.
      let y = -0.085, z = -0.058;
      for (let i = 0; i < 4; i++) {
        const a = 0.1 + i * 0.09, segLen = 0.042;
        const cy = y - Math.cos(a) * segLen / 2, cz = z - Math.sin(a) * segLen / 2;
        Mg.box(0.04, segLen + 0.004, 0.066, M.gunPoly, [0, cy, cz], [a, 0, 0], 0.005);
        Mg.box(0.042, 0.003, 0.058, M.dark, [0, cy - segLen / 2, cz - Math.sin(a) * 0.0], [a, 0, 0], 0.001);
        y -= Math.cos(a) * segLen; z -= Math.sin(a) * segLen;
      }
      Mg.box(0.046, 0.012, 0.072, M.gunPoly, [0, y - 0.004, z], [0.45, 0, 0], 0.004);
    }
    Object.assign(info, { sightY: 0.09, muzzleZ: -0.73, grip: [0, -0.1, 0.1], gripRot: -0.3, fore: [0, -0.03, -0.33], eject: [0.035, 0.016, -0.005] });
  } else if (id === 'smg') {
    B.box(0.05, 0.07, 0.25, M.gunPoly, [0, 0, -0.01], undefined, 0.012);
    B.box(0.052, 0.022, 0.18, M.gunBlack, [0, 0.03, -0.02], undefined, 0.004);
    rail(B, M, -0.13, 0.1, 0.046);
    B.box(0.044, 0.044, 0.1, M.gunBlack, [0, 0.004, -0.18], undefined, 0.008);
    for (let i = 0; i < 4; i++) for (const s of [-1, 1]) B.box(0.003, 0.02, 0.012, M.dark, [s * 0.022, 0.004, -0.15 - i * 0.02], undefined, 0);
    B.cyl(0.022, 0.21, M.gunBlack, [0, 0.004, -0.335]);
    B.cyl(0.0235, 0.018, M.gunBlack, [0, 0.004, -0.442]);
    B.box(0.034, 0.1, 0.045, M.gunPoly, [0, -0.083, 0.045], [-0.22, 0, 0], 0.01);
    B.box(0.008, 0.007, 0.06, M.gunPoly, [0, -0.045, -0.02], undefined, 0.002);
    B.box(0.004, 0.02, 0.006, M.gunBlack, [0, -0.04, -0.005], [0.3, 0, 0], 0.001);
    B.box(0.03, 0.065, 0.045, M.gunPoly, [0, -0.06, -0.12], [0.35, 0, 0], 0.01);
    for (const s of [-1, 1]) B.cyl(0.006, 0.22, M.gunBlack, [s * 0.018, -0.002, 0.2]);
    B.box(0.052, 0.085, 0.016, M.gunPoly, [0, -0.012, 0.31], undefined, 0.006);
    B.box(0.03, 0.012, 0.025, M.gunBlack, [0, 0.03, 0.105], undefined, 0.003);
    B.box(0.003, 0.02, 0.04, M.dark, [0.026, 0.01, 0.0]);
    // reflex sight
    B.box(0.03, 0.012, 0.05, M.gunBlack, [0, 0.055, 0.0], undefined, 0.003);
    B.cyl(0.017, 0.04, M.gunBlack, [0, 0.075, 0.0], undefined, 0.017, 20, true);
    B.torus(0.0175, 0.003, M.gunBlack, [0, 0.075, -0.02]);
    lens(0.03, 0.03, 0.075, -0.005);
    dot(0.075, -0.006, false);
    Mg.box(0.03, 0.13, 0.04, M.gunBlack, [0, -0.17, 0.065], [-0.22, 0, 0], 0.004);
    Mg.box(0.034, 0.012, 0.046, M.gunPoly, [0, -0.235, 0.08], [-0.22, 0, 0], 0.004);
    Object.assign(info, { sightY: 0.075, muzzleZ: -0.46, grip: [0, -0.08, 0.045], gripRot: -0.22, fore: [0, -0.07, -0.13], foreVertical: true, eject: [0.03, 0.01, 0.0] });
  } else if (id === 'sniper') {
    B.cyl(0.022, 0.26, M.gunBlack, [0, 0.0, 0.0]);
    B.cyl(0.005, 0.05, M.gunBlack, [0.035, 0.0, 0.08], [0, 0, PI / 2]);
    B.sphere(0.011, M.gunBlack, [0.062, -0.004, 0.08]);
    // chassis / stock
    B.box(0.062, 0.062, 0.38, M.gunOlive, [0, -0.028, -0.3], undefined, 0.016);
    B.box(0.056, 0.05, 0.28, M.gunOlive, [0, -0.04, 0.02], undefined, 0.014);
    B.box(0.036, 0.1, 0.05, M.gunOlive, [0, -0.1, 0.12], [-0.35, 0, 0], 0.012);
    B.box(0.05, 0.13, 0.22, M.gunOlive, [0, -0.05, 0.3], undefined, 0.016);
    B.box(0.044, 0.03, 0.16, M.gunOlive, [0, 0.032, 0.27], undefined, 0.01);
    B.box(0.054, 0.15, 0.025, M.gunPoly, [0, -0.052, 0.415], undefined, 0.008);
    B.box(0.008, 0.007, 0.07, M.gunBlack, [0, -0.08, 0.06], undefined, 0.002);
    B.box(0.004, 0.022, 0.006, M.gunBlack, [0, -0.07, 0.06], [0.3, 0, 0], 0.001);
    // barrel + brake
    B.cyl(0.0135, 0.56, M.gunBlack, [0, 0.004, -0.62]);
    for (let a = 0; a < 6; a++) B.box(0.003, 0.003, 0.4, M.dark, [Math.cos(a) * 0.013, 0.004 + Math.sin(a) * 0.013, -0.62], undefined, 0);
    B.box(0.036, 0.032, 0.085, M.gunBlack, [0, 0.004, -0.94], undefined, 0.006);
    for (let i = 0; i < 3; i++) for (const s of [-1, 1]) B.box(0.003, 0.02, 0.012, M.dark, [s * 0.018, 0.004, -0.92 - i * 0.022], undefined, 0);
    // bipod (folded)
    for (const s of [-1, 1]) B.cyl(0.005, 0.2, M.gunBlack, [s * 0.02, -0.065, -0.42]);
    B.box(0.05, 0.02, 0.03, M.gunBlack, [0, -0.06, -0.48], undefined, 0.004);
    Mg.box(0.045, 0.06, 0.085, M.gunPoly, [0, -0.07, -0.03], undefined, 0.006);
    // scope
    B.cyl(0.017, 0.34, M.gunBlack, [0, 0.075, -0.02]);
    B.cyl(0.017, 0.07, M.gunBlack, [0, 0.075, -0.225], undefined, 0.029);
    B.cyl(0.0295, 0.045, M.gunBlack, [0, 0.075, -0.282]);
    B.cyl(0.026, 0.002, M.glass, [0, 0.075, -0.305]);
    B.cyl(0.022, 0.06, M.gunBlack, [0, 0.075, 0.17], undefined, 0.017);
    B.cyl(0.0225, 0.04, M.gunBlack, [0, 0.075, 0.215]);
    B.cyl(0.012, 0.03, M.gunBlack, [0, 0.1, -0.02], [0, 0, 0]);
    B.cyl(0.012, 0.03, M.gunBlack, [0.026, 0.075, -0.02], [0, 0, PI / 2]);
    for (const z of [-0.1, 0.08]) B.box(0.044, 0.045, 0.022, M.gunBlack, [0, 0.05, z], undefined, 0.005);
    rail(B, M, -0.15, 0.13, 0.026);
    Object.assign(info, { sightY: 0.075, muzzleZ: -0.99, grip: [0, -0.1, 0.12], gripRot: -0.35, fore: [0, -0.06, -0.32], eject: [0.03, 0.01, 0.03] });
  } else {
    // pistol
    B.box(0.032, 0.036, 0.19, M.gunBlack, [0, 0.02, -0.05], undefined, 0.005);
    for (let i = 0; i < 7; i++) for (const s of [-1, 1]) B.box(0.002, 0.026, 0.003, M.dark, [s * 0.0162, 0.02, 0.012 + i * 0.006], undefined, 0);
    B.box(0.012, 0.004, 0.045, M.dark, [0.006, 0.0385, -0.03], undefined, 0);
    B.box(0.03, 0.022, 0.17, M.gunPoly, [0, -0.008, -0.045], undefined, 0.005);
    for (let i = 0; i < 3; i++) B.box(0.026, 0.004, 0.006, M.gunPoly, [0, -0.021, -0.1 - i * 0.012], undefined, 0);
    B.cyl(0.0075, 0.006, M.dark, [0, 0.022, -0.146]);
    B.box(0.031, 0.105, 0.05, M.gunPoly, [0, -0.068, 0.03], [-0.22, 0, 0], 0.009);
    B.box(0.007, 0.007, 0.05, M.gunPoly, [0, -0.036, -0.03], undefined, 0.002);
    B.box(0.007, 0.022, 0.007, M.gunPoly, [0, -0.026, -0.055], undefined, 0.002);
    B.box(0.004, 0.018, 0.005, M.gunBlack, [0, -0.026, -0.03], [0.25, 0, 0], 0.001);
    B.box(0.005, 0.008, 0.006, M.gunBlack, [0, 0.042, -0.138], undefined, 0.001);
    for (const s of [-1, 1]) B.box(0.009, 0.009, 0.008, M.gunBlack, [s * 0.0095, 0.042, 0.03], undefined, 0.001);
    const fd = new THREE.Mesh(new THREE.SphereGeometry(0.0016, 8, 6), new THREE.MeshBasicMaterial({ color: 0x9dff6a, toneMapped: false }));
    fd.position.set(0, 0.046, -0.138);
    extras.push(fd);
    Mg.box(0.034, 0.012, 0.054, M.gunPoly, [0, -0.124, 0.045], [-0.22, 0, 0], 0.004);
    Object.assign(info, { sightY: 0.045, muzzleZ: -0.155, grip: [0, -0.06, 0.03], gripRot: -0.22, fore: null, eject: [0.018, 0.035, -0.02] });
  }
  return { B, Mg, extras, info };
}

const gunCache = new Map();
/** Third-person weapon (shared geometry; cloned per avatar). */
export function worldGun(id, M) {
  if (!gunCache.has(id)) {
    const { B, Mg, extras, info } = buildGunParts(id, M);
    const g = B.build();
    const mag = Mg.build();
    mag.name = 'mag';
    g.add(mag);
    for (const e of extras) g.add(e);
    gunCache.set(id, { g, info });
  }
  const { g, info } = gunCache.get(id);
  return { group: g.clone(), info };
}

/** First-person weapon: the gun (arms come from the character rig), plus view positions. */
export function fpWeapon(id, M) {
  const { group, info } = worldGun(id, M);
  const root = new THREE.Group();
  root.add(group);
  group.traverse((o) => { if (o.isMesh) { o.castShadow = false; o.receiveShadow = false; } });
  const mag = group.getObjectByName('mag');

  const flash = new THREE.Group();
  for (let i = 0; i < 3; i++) {
    const p = new THREE.Mesh(new THREE.PlaneGeometry(0.2, 0.2), M.flash);
    p.rotation.set(i === 0 ? 0 : PI / 2, i === 2 ? PI / 2 : 0, 0);
    if (i > 0) { p.scale.set(1, 2.2, 1); p.position.z = -0.09; }
    flash.add(p);
  }
  flash.scale.setScalar(id === 'sniper' ? 1.5 : id === 'pistol' ? 0.7 : id === 'smg' ? 0.5 : 1);
  flash.position.set(0, 0.008, info.muzzleZ);
  flash.visible = false;
  group.add(flash);
  root.visible = false;

  const POS = {
    ar: { hip: [0.15, -0.19, -0.5], adsZ: -0.52 },
    smg: { hip: [0.14, -0.17, -0.45], adsZ: -0.45 },
    sniper: { hip: [0.16, -0.19, -0.55], adsZ: -0.42 },
    pistol: { hip: [0.12, -0.15, -0.42], adsZ: -0.45 },
  }[id];
  return {
    root, model: group, mag, magBase: mag.position.clone(), flash, info,
    hip: V(POS.hip), ads: new THREE.Vector3(0, -info.sightY, POS.adsZ),
  };
}

// =====================================================================
// Props
// =====================================================================
export function barrel(M, color) {
  const B = new Builder();
  const mat = new THREE.MeshStandardMaterial({ color, map: M.metalTex.map, normalMap: M.metalTex.normalMap, roughness: 0.55, metalness: 0.4 });
  B.add(new THREE.CylinderGeometry(0.3, 0.3, 0.9, 24), mat, [0, 0.45, 0]);
  for (const y of [0.02, 0.3, 0.6, 0.88]) B.torus(0.302, 0.012, mat, [0, y, 0], [PI / 2, 0, 0]);
  B.add(new THREE.CylinderGeometry(0.28, 0.28, 0.01, 24), M.dark, [0, 0.9, 0]);
  B.add(new THREE.CylinderGeometry(0.03, 0.03, 0.02, 10), mat, [0.15, 0.91, 0.05]);
  return B.build();
}

export function sandbags(M, w, d, h) {
  const B = new Builder();
  const mat = M.burlapMat;
  const along = w >= d ? 'x' : 'z';
  const len = Math.max(w, d), bag = 0.5;
  const layers = Math.round(h / 0.18);
  for (let l = 0; l < layers; l++) {
    const n = Math.floor(len / bag) - (l % 2 ? 1 : 0);
    const start = -((n - 1) * bag) / 2;
    for (let i = 0; i < n; i++) {
      const p = start + i * bag + (Math.random() - 0.5) * 0.03;
      const y = 0.09 + l * 0.18;
      const pos = along === 'x' ? [p, y, 0] : [0, y, p];
      const rot = [0, (along === 'x' ? 0 : PI / 2) + (Math.random() - 0.5) * 0.12, (Math.random() - 0.5) * 0.06];
      B.box(0.52, 0.2, Math.min(w, d) * 0.95, mat, pos, rot, 0.08);
    }
  }
  return B.build();
}
