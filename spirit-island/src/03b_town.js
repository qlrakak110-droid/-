// ============================================================================
//  town: half-timbered cottages with tiled gable roofs, chimney smoke, cobbled
//  plaza, wall lanterns, flower boxes and yard props. Everything static is
//  merged into one mesh per material so the village costs a handful of draws.
// ============================================================================

// collects transformed copies of geometry per material, then merges each bin
function StaticKit() {
  const bins = new Map();
  const m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), e = new THREE.Euler(), v = new THREE.Vector3(), sv = new THREE.Vector3();
  const stack = [];
  const kit = {
    base: new THREE.Matrix4(),
    // run fn with a local frame (position + yaw) pushed on top of the current base
    frame(pos, yaw, fn) {
      stack.push(kit.base.clone());
      kit.base.multiply(new THREE.Matrix4().compose(v.set(pos[0], pos[1], pos[2]), q.setFromEuler(e.set(0, yaw, 0)), sv.set(1, 1, 1)));
      fn(); kit.base.copy(stack.pop());
    },
    add(geo, mat, pos, scl = 1, rot = [0, 0, 0]) {
      e.set(rot[0], rot[1], rot[2]); q.setFromEuler(e);
      if (Array.isArray(scl)) sv.set(scl[0], scl[1], scl[2]); else sv.setScalar(scl);
      m4.compose(v.set(pos[0], pos[1], pos[2]), q, sv).premultiply(kit.base);
      const g = geo.index ? geo.toNonIndexed() : geo.clone();
      const keepCol = !!mat.userData.archColor;           // architecture materials read COLOR_0 = (AO, variation, grime)
      for (const k of Object.keys(g.attributes)) if (k !== 'position' && k !== 'normal' && k !== 'uv' && !(keepCol && k === 'color')) g.deleteAttribute(k);
      if (!g.attributes.uv) g.setAttribute('uv', new THREE.BufferAttribute(new Float32Array(g.attributes.position.count * 2), 2));
      if (keepCol && !g.attributes.color) { const c = new Float32Array(g.attributes.position.count * 3); for (let i = 0; i < c.length; i += 3) { c[i] = 1; c[i + 1] = 0.5; } g.setAttribute('color', new THREE.BufferAttribute(c, 3)); }
      g.clearGroups(); g.applyMatrix4(m4);
      if (!bins.has(mat)) bins.set(mat, []);
      bins.get(mat).push(g);
    },
    // add a geometry with an explicit local matrix (applied under the current base)
    addM(geo, mat, local) { m4.copy(local).premultiply(kit.base); kit._push(geo, mat, m4); },
    _push(geo, mat, M) {
      const g = geo.index ? geo.toNonIndexed() : geo.clone();
      const keepCol = !!mat.userData.archColor;
      for (const k of Object.keys(g.attributes)) if (k !== 'position' && k !== 'normal' && k !== 'uv' && !(keepCol && k === 'color')) g.deleteAttribute(k);
      if (!g.attributes.uv) g.setAttribute('uv', new THREE.BufferAttribute(new Float32Array(g.attributes.position.count * 2), 2));
      if (keepCol && !g.attributes.color) { const c = new Float32Array(g.attributes.position.count * 3); for (let i = 0; i < c.length; i += 3) { c[i] = 1; c[i + 1] = 0.5; } g.setAttribute('color', new THREE.BufferAttribute(c, 3)); }
      g.clearGroups(); g.applyMatrix4(M);
      if (!bins.has(mat)) bins.set(mat, []);
      bins.get(mat).push(g);
    },
    point(p) { return new THREE.Vector3(p[0], p[1], p[2]).applyMatrix4(kit.base); },
    build(parent) {
      const out = [];
      for (const [mat, list] of bins) {
        const geo = mergeGeometries(list, false);
        for (const g of list) g.dispose();
        const mesh = new THREE.Mesh(geo, mat);
        const lit = !(mat.isMeshBasicMaterial || mat.transparent);
        mesh.castShadow = lit && !mat.userData.noShadow; mesh.receiveShadow = lit;
        parent.add(mesh); out.push(mesh);
      }
      bins.clear();
      return out;
    },
  };
  return kit;
}

// ---------------- procedural surface textures (grey-scale, tinted by material colour)
function canvasTex(w, h, draw, repeat = [1, 1]) {
  const c = document.createElement('canvas'); c.width = w; c.height = h;
  draw(c.getContext('2d'), w, h);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace; t.wrapS = t.wrapT = THREE.RepeatWrapping; t.repeat.set(repeat[0], repeat[1]);
  t.anisotropy = 4;
  return t;
}
const TownTex = {};
function townTextures() {
  if (TownTex.ready) return TownTex;
  const rng = mulberry32(7077);
  // lime plaster: soft blotches and a few hairline cracks
  TownTex.plaster = canvasTex(256, 256, (g, w, h) => {
    g.fillStyle = '#f2f0ec'; g.fillRect(0, 0, w, h);
    for (let i = 0; i < 140; i++) {
      const x = rng() * w, y = rng() * h, r = 6 + rng() * 26, a = 0.025 + rng() * 0.05;
      const gr = g.createRadialGradient(x, y, 0, x, y, r); const d = rng() < 0.5;
      gr.addColorStop(0, d ? `rgba(120,105,90,${a})` : `rgba(255,255,255,${a * 1.5})`); gr.addColorStop(1, 'rgba(0,0,0,0)');
      g.fillStyle = gr; g.fillRect(x - r, y - r, r * 2, r * 2);
    }
    g.strokeStyle = 'rgba(90,80,70,.18)'; g.lineWidth = 1;
    for (let i = 0; i < 5; i++) { let x = rng() * w, y = rng() * h; g.beginPath(); g.moveTo(x, y); for (let k = 0; k < 5; k++) { x += (rng() - 0.5) * 18; y += 4 + rng() * 8; g.lineTo(x, y); } g.stroke(); }
  });
  // one course of clay roof tiles: twelve tiles along the ridge, rounded lower lips
  TownTex.tiles = canvasTex(64, 768, (g, w, h) => {
    const n = 12, th = h / n;
    for (let i = 0; i < n; i++) {
      const y0 = i * th, k = 0.86 + rng() * 0.22;
      const gr = g.createLinearGradient(0, 0, w, 0);
      gr.addColorStop(0, `rgb(${110 * k},${110 * k},${110 * k})`); gr.addColorStop(0.25, `rgb(${235 * k},${235 * k},${235 * k})`);
      gr.addColorStop(0.8, `rgb(${215 * k},${215 * k},${215 * k})`); gr.addColorStop(1, `rgb(${150 * k},${150 * k},${150 * k})`);
      g.fillStyle = gr; g.fillRect(0, y0, w, th);
      const sg = g.createLinearGradient(0, y0, 0, y0 + th);   // barrel curvature across the tile
      sg.addColorStop(0, 'rgba(0,0,0,.42)'); sg.addColorStop(0.18, 'rgba(0,0,0,0)'); sg.addColorStop(0.55, 'rgba(255,255,255,.10)'); sg.addColorStop(0.9, 'rgba(0,0,0,.08)'); sg.addColorStop(1, 'rgba(0,0,0,.45)');
      g.fillStyle = sg; g.fillRect(0, y0, w, th);
    }
  });
  // fieldstone: irregular blocks in grey mortar
  TownTex.stone = canvasTex(256, 256, (g, w, h) => {
    g.fillStyle = '#5c564f'; g.fillRect(0, 0, w, h);
    const rows = 6, rh = h / rows;
    for (let r = 0; r < rows; r++) {
      let x = -rng() * 30;
      while (x < w) {
        const bw = 30 + rng() * 34, k = 0.75 + rng() * 0.3;
        const c = [190 * k, 182 * k, 170 * k].map((v) => v | 0);
        g.fillStyle = `rgb(${c})`; roundRect(g, x + 2, r * rh + 2, bw - 4, rh - 4, 7); g.fill();
        g.fillStyle = 'rgba(255,255,255,.16)'; roundRect(g, x + 4, r * rh + 3, bw - 10, (rh - 8) * 0.4, 5); g.fill();
        g.fillStyle = 'rgba(0,0,0,.18)'; roundRect(g, x + 4, r * rh + rh * 0.62, bw - 8, rh * 0.3, 5); g.fill();
        x += bw;
      }
    }
  }, [1, 1]);
  // cobbles for the plaza
  TownTex.cobble = canvasTex(512, 512, (g, w, h) => {
    g.fillStyle = '#6d655c'; g.fillRect(0, 0, w, h);
    const n = 13, cs = w / n;
    for (let i = 0; i < n; i++) for (let j = 0; j < n; j++) {
      const off = (j % 2) * cs * 0.5;
      const x = i * cs + off + (rng() - 0.5) * cs * 0.18, y = j * cs + (rng() - 0.5) * cs * 0.18, k = 0.78 + rng() * 0.3, warm = rng() * 14;
      for (const dx of [0, -w, w]) {
        g.fillStyle = `rgb(${(196 + warm) * k | 0},${(186 + warm * 0.5) * k | 0},${172 * k | 0})`;
        roundRect(g, x + dx + 3, y + 3, cs - 6, cs - 6, cs * 0.32); g.fill();
        g.fillStyle = 'rgba(255,255,255,.18)'; roundRect(g, x + dx + 6, y + 5, cs - 14, cs * 0.34, cs * 0.2); g.fill();
        g.fillStyle = 'rgba(0,0,0,.16)'; roundRect(g, x + dx + 6, y + cs * 0.6, cs - 12, cs * 0.3, cs * 0.18); g.fill();
      }
    }
  }, [6, 6]);
  TownTex.radial = canvasTex(256, 256, (g, w, h) => {
    const gr = g.createRadialGradient(w / 2, h / 2, 0, w / 2, h / 2, w / 2);
    gr.addColorStop(0, '#fff'); gr.addColorStop(0.82, '#fff'); gr.addColorStop(1, '#000');
    g.fillStyle = gr; g.fillRect(0, 0, w, h);
  });
  TownTex.radial.colorSpace = THREE.NoColorSpace;
  // wood planks
  TownTex.wood = canvasTex(128, 128, (g, w, h) => {
    g.fillStyle = '#d8d0c8'; g.fillRect(0, 0, w, h);
    for (let i = 0; i < 40; i++) { g.strokeStyle = `rgba(60,40,30,${0.05 + rng() * 0.12})`; g.lineWidth = 1 + rng() * 2; const y = rng() * h; g.beginPath(); g.moveTo(0, y); g.bezierCurveTo(w * 0.3, y + (rng() - 0.5) * 6, w * 0.7, y + (rng() - 0.5) * 6, w, y + (rng() - 0.5) * 4); g.stroke(); }
  });
  TownTex.ready = true;
  return TownTex;
}
function roundRect(g, x, y, w, h, r) {
  r = Math.min(r, w / 2, h / 2);
  g.beginPath(); g.moveTo(x + r, y); g.arcTo(x + w, y, x + w, y + h, r); g.arcTo(x + w, y + h, x, y + h, r); g.arcTo(x, y + h, x, y, r); g.arcTo(x, y, x + w, y, r); g.closePath();
}
const _townMat = new Map();
function texMat(kind, color) {
  const k = kind + color;
  if (!_townMat.has(k)) _townMat.set(k, toonMat({ color, map: townTextures()[kind] }));
  return _townMat.get(k);
}
function shadeHex(hex, k) { const c = new THREE.Color(hex); c.multiplyScalar(k); return c.getHex(); }

// gable prism: triangle (−w/2,0) (w/2,0) (0,h) extruded along z over depth d (centred)
const _prisms = new Map();
function gablePrism(w, h, d) {
  const k = [w, h, d].join();
  if (!_prisms.has(k)) {
    const s = new THREE.Shape(); s.moveTo(-w / 2, 0); s.lineTo(w / 2, 0); s.lineTo(0, h); s.closePath();
    const g = new THREE.ExtrudeGeometry(s, { depth: d, bevelEnabled: false }); g.translate(0, 0, -d / 2);
    // planar UVs so the plaster texture lands at the same scale as the walls
    const p = g.attributes.position, uv = g.attributes.uv;
    for (let i = 0; i < p.count; i++) uv.setXY(i, p.getX(i) / 4 + p.getZ(i) / 4, p.getY(i) / 3.2);
    _prisms.set(k, g);
  }
  return _prisms.get(k);
}

let TownKit = null, TownSmoke = [];
const FLOWER_COLS = [0xff6f91, 0xffd35a, 0xffffff, 0xff8a4c, 0xb48cff, 0x7ad0ff];

// ============================================================================
//  Authored village (architecture workstream): Blender cottages, props and fountain (assets/models/architecture/*.glb,
//  tools/blender/architecture_*.py) with PBR sets (assets/tex/architecture, tools/tex/architecture_textures.py).
//  Three half-timbered variants share the old cottage footprint; roofs are individual glazed pantiles + ridge caps,
//  instanced at runtime on the roof planes stored in each variant's glTF extras. COLOR_0 on every authored mesh is
//  (R ambient occlusion, G per-piece variation, B grime mask): the material patch below turns it into contact
//  darkening, colour variation between timbers/stones and dirt splashed up the walls / streaked under sills and eaves.
//  If the GLBs are missing (file://, failed load) the procedural cottages below are used unchanged.
// ============================================================================
const ARCH_SETS = ['plaster', 'wood', 'stone', 'tile', 'cobble', 'iron'];
registerAssets({
  textures: Object.assign({}, ...ARCH_SETS.flatMap((n) => ['albedo', 'normal', 'orm'].map((s) => ({
    [`arch_${n}_${s}`]: { file: `tex/architecture/arch_${n}_${s}.jpg`, lo: `tex/architecture/arch_${n}_${s}_512.jpg`, srgb: s === 'albedo' } })))),
  models: { arch_houses: 'models/architecture/houses.glb', arch_props: 'models/architecture/props.glb', arch_tiles: 'models/architecture/tiles.glb' },
});

const Arch = { geo: null, meta: {}, mats: new Map(), tiles: [], ridges: [], houseN: 0, stats: { houses: 0, tiles: 0, props: 0 } };

// glTF meshes -> plain Float32 geometries keyed by node name (A_plaster, barrel_wood, tile_hi ...), uv flipped back to
// Blender's convention (our textures load with flipY), node extras kept as meta (roof planes, ridges, smoke points)
function archGeos() {
  if (Arch.geo) return Arch.geo;
  if (!Assets.ready) return {};                                  // never memoise before the loader finished
  const G = {};
  for (const key of ['arch_houses', 'arch_props', 'arch_tiles']) {
    const gl = assetGltf(key); if (!gl) continue;
    gl.scene.updateMatrixWorld(true);
    gl.scene.traverse((o) => {
      if (o.userData && (o.userData.roof || o.userData.smoke)) Arch.meta[o.name.replace(/_meta$/, '')] = o.userData;
      if (!o.isMesh) return;
      const src = o.geometry, g = new THREE.BufferGeometry();
      for (const name in src.attributes) {
        const a = src.attributes[name], n = a.count, s = a.itemSize, arr = new Float32Array(n * s);
        for (let i = 0; i < n; i++) {
          arr[i * s] = a.getX(i); if (s > 1) arr[i * s + 1] = a.getY(i); if (s > 2) arr[i * s + 2] = a.getZ(i); if (s > 3) arr[i * s + 3] = a.getW(i);
        }
        if (name === 'uv') for (let i = 0; i < n; i++) arr[i * 2 + 1] = 1 - arr[i * 2 + 1];
        if (name === 'color' && s === 4) {                       // keep rgb only (alpha is always 1)
          const c3 = new Float32Array(n * 3); for (let i = 0; i < n; i++) { c3[i * 3] = arr[i * 4]; c3[i * 3 + 1] = arr[i * 4 + 1]; c3[i * 3 + 2] = arr[i * 4 + 2]; }
          g.setAttribute('color', new THREE.BufferAttribute(c3, 3)); continue;
        }
        g.setAttribute(name, new THREE.BufferAttribute(arr, s));
      }
      if (src.index) g.setIndex(new THREE.BufferAttribute(src.index.array.slice(), 1));
      g.applyMatrix4(o.matrixWorld);
      g.computeBoundingSphere();
      G[o.name] = g;
    });
  }
  return (Arch.geo = G);
}
const archReady = () => !window.__archOff && !!(archGeos().A_plaster && archGeos().tile_hi);   // __archOff: dev switch for before/after shots
// all meshes of one authored piece: [[bin, geometry], ...] for node names "<piece>_<bin>"
function archPiece(piece) {
  const G = archGeos(), out = [];
  for (const k in G) if (k.startsWith(piece + '_') && !/_meta$/.test(k)) {
    const bin = k.slice(piece.length + 1);
    if (bin.includes('_') && !['A', 'B', 'C'].includes(piece)) continue;
    out.push([bin, G[k]]);
  }
  return out;
}

const ARCH_GLSL = `
  varying vec3 vArchW;
  uniform vec3 uArchGrime; uniform float uArchVar, uArchAO;
  float archHash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
  float archNoise(vec2 p){ vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
    return mix(mix(archHash(i), archHash(i + vec2(1.0, 0.0)), f.x), mix(archHash(i + vec2(0.0, 1.0)), archHash(i + vec2(1.0, 1.0)), f.x), f.y); }
`;
// material patch: COLOR_0 (AO, variation, grime) -> albedo variation, world-noise grime, AO on ambient (+ a little on direct)
function archPatch(m, o = {}) {
  const U = { uArchGrime: { value: new THREE.Color(o.grime ?? 0x5a4a3a) }, uArchVar: { value: o.vary ?? 0.24 }, uArchAO: { value: o.ao ?? 0.85 } };
  m.userData.archU = U; m.userData.archColor = true; m.vertexColors = true;
  m.onBeforeCompile = (sh) => {
    Object.assign(sh.uniforms, U);
    sh.vertexShader = 'varying vec3 vArchW;\n' + sh.vertexShader.replace('#include <begin_vertex>', `#include <begin_vertex>
      vec4 archWp = vec4(transformed, 1.0);
      #ifdef USE_INSTANCING
        archWp = instanceMatrix * archWp;
      #endif
      vArchW = (modelMatrix * archWp).xyz;`);
    sh.fragmentShader = ARCH_GLSL + sh.fragmentShader
      .replace('#include <color_fragment>', `
        float archAO = 1.0;
        #ifdef USE_COLOR
          diffuseColor.rgb *= 1.0 + (vColor.g - 0.5) * uArchVar;
          // large weathering patches (a few metres) so long walls never read as one flat colour
          diffuseColor.rgb *= 0.92 + 0.16 * archNoise(vArchW.xz * 0.45 + vArchW.y * 0.3);
          float archN = archNoise(vArchW.xz * 1.3 + vArchW.y * 0.7) * 0.5 + archNoise(vec2((vArchW.x + vArchW.z) * 5.0, vArchW.y * 0.6)) * 0.5;
          float archG = clamp(vColor.b * (0.55 + 1.15 * archN), 0.0, 1.0);
          diffuseColor.rgb = mix(diffuseColor.rgb, diffuseColor.rgb * uArchGrime, archG);
          archAO = mix(1.0, vColor.r, uArchAO);
        #endif`)
      .replace('#include <aomap_fragment>', `#include <aomap_fragment>
        reflectedLight.indirectDiffuse *= archAO; reflectedLight.indirectSpecular *= archAO;
        reflectedLight.directDiffuse *= mix(1.0, archAO, 0.3);`);
  };
  m.customProgramCacheKey = () => 'arch1';
  return m;
}
// PBR material for a bin kind, tinted (cached). kinds: plaster timber wood door paint stone ashlar iron clay glass cloth glow flora soil cobble
const ARCH_KIND = {
  plaster: { set: 'plaster', tint: 0xf3e6d2, env: 'plaster', ns: 0.9, grime: 0x5e4c3a },
  timber: { set: 'wood', tint: 0x7c5e47, env: 'wood', ns: 1.0, vary: 0.34, grime: 0x4a3c30 },
  wood: { set: 'wood', tint: 0xb39578, env: 'wood', ns: 1.0, vary: 0.3, grime: 0x5a4a3a },
  door: { set: 'wood', tint: 0xa8724a, env: 'wood', ns: 1.0, vary: 0.2 },
  paint: { set: 'wood', tint: 0x4f7a5a, env: 'wood', ns: 0.8, vary: 0.2, rough: 0.85 },
  stone: { set: 'stone', tint: 0xf2eee8, env: 'rock', ns: 1.1, vary: 0.3, grime: 0x4a4034 },
  ashlar: { set: 'plaster', tint: 0xd6cfc2, env: 'rock', ns: 1.4, vary: 0.12, grime: 0x6a604f },
  iron: { set: 'iron', tint: 0xffffff, env: 'metal', ns: 0.8, metal: 0.55, vary: 0.1 },
  clay: { set: 'tile', tint: 0xb4603f, env: 'rock', ns: 0.6, vary: 0.2 },
  soil: { set: null, tint: 0x4a3a2c, env: 'ground', rough: 1.0, vary: 0.2 },
  cloth: { set: null, tint: 0xe6dccb, env: 'default', rough: 0.95, vary: 0.25 },
};
function archMat(kind, tint) {
  const key = kind + '|' + (tint ?? '');
  if (Arch.mats.has(key)) return Arch.mats.get(key);
  let m;
  const envK = (k) => (typeof Lighting !== 'undefined' ? Lighting.envFor(k) : 0.6);
  if (kind === 'glass') {
    m = new THREE.MeshStandardMaterial({ color: 0x0d1114, roughness: 0.06, metalness: 0.0, emissive: new THREE.Color(0xffa860), emissiveIntensity: 0.05, envMapIntensity: 1.8 });
    m.userData.archColor = true; m.userData.keepEnv = true;
  } else if (kind === 'water') {
    m = new THREE.MeshStandardMaterial({ color: 0x14202a, roughness: 0.04, metalness: 0.0, envMapIntensity: 1.3 });
    m.userData.archColor = true; m.userData.keepEnv = true;
  } else if (kind === 'glow') {
    m = new THREE.MeshBasicMaterial({ color: new THREE.Color(0xffc887).multiplyScalar(2.6) });
    m.userData.archColor = true;
  } else if (kind === 'flora') {
    m = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.75, metalness: 0, side: THREE.DoubleSide, envMapIntensity: envK('foliage') });
    m.userData.archColor = true;
  } else {
    const K = ARCH_KIND[kind] || ARCH_KIND.plaster, set = K.set ? pbrSet('arch_' + K.set) : null;
    m = new THREE.MeshStandardMaterial({ color: new THREE.Color(tint ?? K.tint), roughness: K.rough ?? 1, metalness: K.metal ?? 0, envMapIntensity: envK(K.env) });
    if (set) {
      m.map = set.albedo; m.normalMap = set.normal; m.normalScale = new THREE.Vector2(K.ns ?? 1, K.ns ?? 1);
      m.roughnessMap = set.orm; m.aoMap = set.orm; m.aoMapIntensity = 0.75;
    }
    archPatch(m, { grime: K.grime, vary: K.vary });
  }
  Arch.mats.set(key, m);
  return m;
}
// material for a glTF bin of a house (per-house tints for walls / shutters)
function archBinMat(bin, o = {}) {
  if (bin === 'plaster') return archMat('plaster', o.wall);
  if (bin === 'paint') return archMat('paint', o.shutter);
  return archMat(bin);
}
// tile material: instance colour = roof tint x per-tile variation; COLOR_0 = AO across the pantile profile
let _archTileMat = null;
function archTileMat() {
  if (_archTileMat) return _archTileMat;
  const set = pbrSet('arch_tile');
  const m = new THREE.MeshStandardMaterial({ color: 0xffffff, vertexColors: true, roughness: 1, metalness: 0, envMapIntensity: (typeof Lighting !== 'undefined' ? Lighting.envFor('rock') : 0.6) * 1.2 });
  if (set) { m.map = set.albedo; m.normalMap = set.normal; m.normalScale = new THREE.Vector2(0.7, 0.7); m.roughnessMap = set.orm; }
  else m.roughness = 0.5;
  return (_archTileMat = m);
}

// queue roof tiles for one roof: meta roof planes (o, u, v, U, V) and ridges (o, dir, L) in local coords, M = local->world
function archQueueRoof(meta, M, roofHex, rng) {
  const R = meta.roof || [], Rg = meta.ridge || [];
  const base = new THREE.Color(roofHex).multiplyScalar(1.12).offsetHSL(0, -0.08, 0);   // glaze reads a touch less saturated in daylight
  const o = new THREE.Vector3(), u = new THREE.Vector3(), v = new THREE.Vector3(), n = new THREE.Vector3(), p = new THREE.Vector3();
  const x = new THREE.Vector3(), y = new THREE.Vector3(), z = new THREE.Vector3(), L = new THREE.Matrix4();
  const tint = (k) => {
    const c = base.clone(); let f = 0.84 + rng() * 0.26;
    if (rng() < 0.07) f *= 0.78; else if (rng() < 0.05) f *= 1.15;                // odd replacement tiles
    c.multiplyScalar(f * k); c.offsetHSL((rng() - 0.5) * 0.015, (rng() - 0.5) * 0.06, 0); return c;
  };
  for (let i = 0; i + 10 < R.length; i += 11) {
    o.set(R[i], R[i + 1], R[i + 2]); u.set(R[i + 3], R[i + 4], R[i + 5]); v.set(R[i + 6], R[i + 7], R[i + 8]);
    const UL = R[i + 9], VL = R[i + 10];
    n.crossVectors(v, u);
    if (n.y < 0) { o.addScaledVector(u, UL); u.negate(); n.negate(); }
    const cols = Math.max(1, Math.round(UL / 0.3)), w = UL / cols, rows = Math.floor((VL + 0.06) / 0.3) + 1;
    for (let r = 0; r < rows; r++) {
      const s = -0.06 + r * 0.3;
      if (s > VL - 0.08) break;
      const eave = 1 - Math.min(1, r / 3);
      for (let c = 0; c < cols; c++) {
        p.copy(o).addScaledVector(u, (c + 0.5) * w + (rng() - 0.5) * 0.012).addScaledVector(v, s + (rng() - 0.5) * 0.01).addScaledVector(n, 0.012 + rng() * 0.006);
        x.copy(u).multiplyScalar(w / 0.3);
        z.copy(v).multiplyScalar(0.4).addScaledVector(n, -0.016 - rng() * 0.008).normalize();
        z.applyAxisAngle(n, (rng() - 0.5) * 0.03);
        y.crossVectors(z, u).normalize();
        L.makeBasis(x, y, z).setPosition(p).premultiply(M);
        Arch.tiles.push(L.clone(), tint(1 - eave * 0.12));
      }
    }
  }
  for (let i = 0; i + 6 < Rg.length; i += 7) {
    o.set(Rg[i], Rg[i + 1], Rg[i + 2]); z.set(Rg[i + 3], Rg[i + 4], Rg[i + 5]).normalize();
    const len = Rg[i + 6], cnt = Math.max(1, Math.ceil(len / 0.36));
    x.set(0, 1, 0).cross(z).normalize(); y.crossVectors(z, x);
    for (let k = 0; k < cnt; k++) {
      p.copy(o).addScaledVector(z, (k * len) / cnt);
      L.makeBasis(x, y, z).setPosition(p).premultiply(M);
      Arch.ridges.push(L.clone(), tint(0.92));
    }
  }
}
function archBuildTiles(scene) {
  const G = archGeos(), lo = !Settings.high;
  const mk = (list, geo) => {
    if (!list.length || !geo) return null;
    const cnt = list.length / 2, im = new THREE.InstancedMesh(geo, archTileMat(), cnt);
    for (let i = 0; i < cnt; i++) { im.setMatrixAt(i, list[i * 2]); im.setColorAt(i, list[i * 2 + 1]); }
    im.instanceMatrix.needsUpdate = true; if (im.instanceColor) im.instanceColor.needsUpdate = true;
    im.castShadow = true; im.receiveShadow = true; im.computeBoundingSphere();
    scene.add(im); return im;
  };
  const a = mk(Arch.tiles, lo ? G.tile_lo || G.tile_hi : G.tile_hi), b = mk(Arch.ridges, lo ? G.ridge_lo || G.ridge_hi : G.ridge_hi);
  Arch.stats.tiles = Arch.tiles.length / 2 + Arch.ridges.length / 2;
  Arch.tiles = []; Arch.ridges = [];
  return [a, b];
}
// add an authored prop to the static kit under the current base: name, local position, yaw, scale, tint overrides
const _apM = new THREE.Matrix4(), _apQ = new THREE.Quaternion(), _apE = new THREE.Euler(), _apV = new THREE.Vector3(), _apS = new THREE.Vector3();
function archProp(K, name, pos, yaw = 0, scl = 1, tints = {}) {
  const parts = archPiece(name);
  if (!parts.length) return false;
  _apM.compose(_apV.set(pos[0], pos[1], pos[2]), _apQ.setFromEuler(_apE.set(0, yaw, 0)), _apS.setScalar(scl));
  for (const [bin, g] of parts) K.addM(g, tints[bin] !== undefined ? archMat(bin, tints[bin]) : archMat(bin === 'glass' ? 'water' : bin), _apM);
  Arch.stats.props++;
  return true;
}

// ---------------- authored cottage (same footprint, colliders, smoke and crystal hooks as the procedural one)
const ARCH_ORDER = ['A', 'B', 'C', 'B', 'C'];
function archHouse(scene, x, z, rot, wall, roof, s = 1, opts = {}) {
  const K = TownKit || (TownKit = StaticKit());
  const variant = opts.variant || (opts.crystal ? 'A' : ARCH_ORDER[Arch.houseN % ARCH_ORDER.length]);
  Arch.houseN++;
  const y = groundY(x, z);
  K.base.compose(new THREE.Vector3(x, y, z), new THREE.Quaternion().setFromEuler(new THREE.Euler(0, rot, 0)), new THREE.Vector3(s, s, s));
  const rng = mulberry32(((x * 73) | 0) ^ ((z * 131) | 0));
  const HW = 2.5, HD = 2.1;
  const tints = { wall, shutter: opts.shutter ?? shadeHex(roof, 0.85) };
  for (const [bin, g] of archPiece(variant)) K.addM(g, archBinMat(bin, tints), new THREE.Matrix4());
  const meta = Arch.meta[variant] || {};
  archQueueRoof(meta, K.base.clone(), roof, rng);
  const sm = meta.smoke || [];
  if (sm.length >= 3) TownSmoke.push(K.point([sm[0], sm[1], sm[2]]));
  // yard props: barrels and crates beside the front corner, firewood under the back eave, pebbles at the footing
  const side = rng() < 0.5 ? -1 : 1, bside = variant === 'C' ? 1 : side;
  archProp(K, rng() < 0.5 ? 'barrel' : 'barrel_b', [bside * (HW + 0.78), -0.02, HD - 0.45], rng() * 6.28);
  if (rng() < 0.7) archProp(K, 'barrel', [bside * (HW + 0.92), -0.02, HD - 1.22], rng() * 6.28, 0.92);
  archProp(K, 'crate', [-bside * (HW + 0.78), -0.01, HD - 0.62], rng() * 0.6 - 0.3);
  if (rng() < 0.6) archProp(K, 'crate_s', [-bside * (HW + 0.78), 0.6, HD - 0.62], rng() * 1.2);
  if (variant !== 'C') archProp(K, 'logs', [variant === 'B' ? -1.6 : 0.2, -0.02, -HD - 1.0], Math.PI / 2 + (rng() - 0.5) * 0.1);
  for (let i = 0; i < 4; i++) {
    const a = rng() * Math.PI * 2, f = 1.0 + rng() * 0.25;
    archProp(K, i % 2 ? 'pebbles_0' : 'pebbles_1', [Math.cos(a) * (HW + 0.45) * f, 0, Math.sin(a) * (HD + 0.45) * f], rng() * 6.28, 0.8 + rng() * 0.5);
  }
  let crystal = null;
  if (opts.crystal) {
    const p = K.point([0, (meta.top || 6.5) + 1.1, 0]);
    crystal = part(GEO.octa, E(0x8ff3ff, 2.6), scene, [p.x, p.y, p.z], [0.45 * s, 0.8 * s, 0.45 * s]);
    World.spinners.push(crystal);
    // hanging shop sign on an iron bracket beside the door
    const IRON = archMat('iron'), WOOD = archMat('wood'), A = K.add, B = GEO.box, zf = HD;
    A(B, IRON, [-1.0, 3.2, zf + 0.5], [0.05, 0.05, 0.9]);
    for (const k of [0.25, 0.75]) A(B, IRON, [-1.0, 3.08, zf + 0.15 + k * 0.7], [0.02, 0.22, 0.02]);
    A(B, WOOD, [-1.0, 2.78, zf + 0.62], [0.08, 0.5, 0.74]);
    A(B, E(0x8ff3ff, 1.7), [-1.0, 2.78, zf + 0.62], [0.11, 0.3, 0.5]);
  }
  World.colliders.push({ x, z, r: 3.2 * s });
  const cs = Math.cos(rot), sn = Math.sin(rot);
  for (const off of [-1.8, 1.8]) World.colliders.push({ x: x + cs * off * s, z: z - sn * off * s, r: 2.4 * s });
  for (const px of [-1, 1]) { const p = K.point([px * (HW + 0.8), 0, HD - 0.7]); World.colliders.push({ x: p.x, z: p.z, r: 0.45 * s }); }
  Arch.stats.houses++;
  return { crystal };
}

// ---------------- cottage (authored model when the architecture assets loaded, procedural otherwise)
function house(scene, x, z, rot, wall, roof, s = 1, opts = {}) {
  if (archReady()) return archHouse(scene, x, z, rot, wall, roof, s, opts);
  return houseProcedural(scene, x, z, rot, wall, roof, s, opts);
}
function houseProcedural(scene, x, z, rot, wall, roof, s = 1, opts = {}) {
  const K = TownKit || (TownKit = StaticKit());
  const y = groundY(x, z);
  K.base.compose(new THREE.Vector3(x, y, z), new THREE.Quaternion().setFromEuler(new THREE.Euler(0, rot, 0)), new THREE.Vector3(s, s, s));
  const rng = mulberry32(((x * 73) | 0) ^ ((z * 131) | 0));
  const B = GEO.box, A = K.add;
  const WALL = texMat('plaster', wall), STONE = texMat('stone', 0xc9c0b4), ROOF = texMat('tiles', roof), ROOF2 = texMat('tiles', shadeHex(roof, 0.88));
  const WOOD = texMat('wood', 0x6a4630), WOODL = texMat('wood', 0x9a7250), DOOR = texMat('wood', 0x8a5a36), RIDGE = M(shadeHex(roof, 0.62));
  const IRON = M(0x2a2630), GLASS = E(0xffb860, 1.15), GLASS2 = E(0xffd09a, 1.5), SHUT = texMat('wood', opts.shutter ?? shadeHex(roof, 0.85));
  const HW = 2.5, HD = 2.1, WH = 3.2, Y0 = 0.5, YT = Y0 + WH;               // half width/depth, wall height
  const RISE = 2.25, OV = 0.45, RD = HD + 0.5;                                   // roof rise, eave overhang, roof half-depth
  // foundation & walls
  A(B, STONE, [0, 0.28, 0], [HW * 2 + 0.6, 0.62, HD * 2 + 0.6]);
  A(B, M(0x8a8178), [0, 0.62, 0], [HW * 2 + 0.34, 0.08, HD * 2 + 0.34]);
  A(B, WALL, [0, Y0 + WH / 2, 0], [HW * 2, WH, HD * 2]);
  A(gablePrism(HW * 2, RISE, HD * 2), WALL, [0, YT, 0]);
  // ---- timber framing: front/back faces (z = ±HD)
  const tf = 0.24, zo = HD + 0.04, xo = HW + 0.04;
  for (const sz of [-1, 1]) {
    const zz = sz * zo, front = sz > 0;
    A(B, WOOD, [0, Y0 + 0.14, zz], [HW * 2 + 0.2, tf, 0.14]);
    A(B, WOOD, [0, YT - 0.1, zz], [HW * 2 + 0.2, tf, 0.14]);
    for (const sx of [-1, 1]) {
      A(B, WOOD, [sx * (HW - 0.02), Y0 + WH / 2, zz], [tf, WH + 0.12, 0.16]);
      A(B, WOOD, [sx * 0.92, Y0 + WH / 2, zz], [0.2, WH, 0.12]);
      A(B, WOOD, [sx * 1.71, 1.86, zz], [1.6, 0.16, 0.12]);                                    // rail under the window
      A(B, WOOD, [sx * 1.71, 3.0, zz], [1.6, 0.14, 0.12]);                                     // header over the window
      for (const d of [-1, 1]) A(B, WOOD, [sx * 1.71, 1.25, zz], [1.6, 0.13, 0.1], [0, 0, d * 0.6]); // X brace
    }
    if (!front) { A(B, WOOD, [0, 1.86, zz], [1.7, 0.16, 0.12]); for (const d of [-1, 1]) A(B, WOOD, [0, 1.25, zz], [1.9, 0.13, 0.1], [0, 0, d * 0.55]); }
    // gable timbers
    A(B, WOOD, [0, YT + 1.0, zz], [HW * 1.32, 0.15, 0.12]);
    for (const sx of [-1, 1]) A(B, WOOD, [sx * 0.95, YT + 0.5, zz], [0.15, 1.0, 0.12]);
    // round attic window
    A(GEO.cyl, GLASS2, [0, YT + 0.6, zz], [0.3, 0.06, 0.3], [Math.PI / 2, 0, 0]);
    A(GEO.torus, WOOD, [0, YT + 0.6, zz + sz * 0.03], [0.33, 0.33, 1.6]);
    A(B, WOOD, [0, YT + 0.6, zz + sz * 0.03], [0.05, 0.6, 0.04]);
    // barge boards under the roof edge
    const th = Math.atan2(RISE, HW), L = (HW + OV) / Math.cos(th);
    for (const sx of [-1, 1]) A(B, WOOD, [sx * (HW + OV) / 2, YT + RISE - (HW + OV) / 2 * Math.tan(th) - 0.08, sz * (RD - 0.06)], [L, 0.2, 0.12], [0, 0, -sx * th]);
  }
  // ---- side faces (x = ±HW)
  for (const sx of [-1, 1]) {
    const xx = sx * xo;
    A(B, WOOD, [xx, Y0 + 0.14, 0], [0.14, tf, HD * 2 + 0.2]);
    A(B, WOOD, [xx, YT - 0.1, 0], [0.14, tf, HD * 2 + 0.2]);
    A(B, WOOD, [xx, 1.86, 0], [0.12, 0.16, HD * 2]);
    for (const sz of [-1, 1]) {
      A(B, WOOD, [xx, Y0 + WH / 2, sz * 0.72], [0.12, WH, 0.2]);
      for (const d of [-1, 1]) A(B, WOOD, [xx, 1.25, sz * 1.42], [0.1, 0.13, 1.45], [d * 0.65, 0, 0]);
    }
  }
  // ---- roof: six overlapping courses of tiles per side, ridge cap
  const th = Math.atan2(RISE, HW), Ls = (HW + OV) / Math.cos(th), N = 6;
  for (const sx of [-1, 1]) for (let i = 0; i < N; i++) {
    const f = (i + 0.5) / N, px = sx * f * (HW + OV), py = YT + RISE - f * (HW + OV) * Math.tan(th);
    const nx = sx * Math.sin(th), ny = Math.cos(th), lift = 0.09 + i * 0.012;
    A(B, i % 2 ? ROOF2 : ROOF, [px + nx * lift, py + ny * lift, 0], [Ls / N * 1.3, 0.12, RD * 2], [0, 0, -sx * (th - 0.075)]);
  }
  A(GEO.cyl, RIDGE, [0, YT + RISE + 0.12, 0], [0.17, RD * 2 + 0.1, 0.17], [Math.PI / 2, 0, 0]);
  for (const sz of [-1, 1]) A(GEO.sphere, RIDGE, [0, YT + RISE + 0.12, sz * (RD + 0.05)], 0.2);
  // ---- chimney with smoke
  const cx = HW * 0.5 * (rng() < 0.5 ? -1 : 1), cz = -0.9;
  const roofAt = YT + RISE - Math.abs(cx) * Math.tan(th);
  A(B, STONE, [cx, roofAt + 0.55, cz], [0.72, 2.0, 0.72]);
  A(B, M(0x7d756c), [cx, roofAt + 1.6, cz], [0.9, 0.16, 0.9]);
  A(B, M(0x161214), [cx, roofAt + 1.69, cz], [0.5, 0.04, 0.5]);
  TownSmoke.push(K.point([cx, roofAt + 1.8, cz]));
  // ---- door, porch canopy, step, wall lantern
  const zf = HD;
  A(B, WOOD, [0, 1.68, zf + 0.04], [1.32, 2.26, 0.12]);
  A(B, DOOR, [0, 1.62, zf + 0.09], [1.06, 2.04, 0.1]);
  for (const gx of [-0.27, 0, 0.27]) A(B, M(0x3e2618), [gx, 1.62, zf + 0.145], [0.03, 1.96, 0.02]);
  for (const hy of [1.0, 2.25]) A(B, IRON, [-0.22, hy, zf + 0.15], [0.5, 0.07, 0.02]);
  A(GEO.sphereLo, M(0xd8a948), [0.38, 1.58, zf + 0.17], 0.055);
  A(B, STONE, [0, 0.2, zf + 0.62], [1.7, 0.36, 0.76]);
  for (const sx of [-1, 1]) {
    A(B, ROOF, [sx * 0.42, 3.17, zf + 0.42], [0.98, 0.09, 1.02], [0, 0, -sx * 0.5]);
    A(B, WOOD, [sx * 0.66, 2.86, zf + 0.42], [0.09, 0.09, 0.8], [-0.62, 0, 0]);
  }
  A(B, IRON, [0.92, 2.6, zf + 0.2], [0.05, 0.05, 0.3]);
  A(B, IRON, [0.92, 2.42, zf + 0.34], [0.2, 0.3, 0.2]);
  A(B, GLASS2, [0.92, 2.42, zf + 0.34], [0.15, 0.24, 0.21]);
  A(GEO.cone4, IRON, [0.92, 2.64, zf + 0.34], [0.17, 0.16, 0.17], [0, Math.PI / 4, 0]);
  // ---- windows: front & back pairs, one on each side
  const win = (px, pz, yaw) => K.frame([px, 2.42, pz], yaw, () => {
    A(B, GLASS, [0, 0, 0.01], [0.78, 0.84, 0.05]);
    A(B, WOODL, [0, 0.47, 0.06], [1.0, 0.1, 0.14]); A(B, WOODL, [0, -0.47, 0.06], [1.0, 0.1, 0.14]);
    for (const sx of [-1, 1]) A(B, WOODL, [sx * 0.45, 0, 0.06], [0.1, 1.04, 0.14]);
    A(B, WOODL, [0, 0, 0.07], [0.05, 0.84, 0.05]); A(B, WOODL, [0, 0.06, 0.07], [0.78, 0.05, 0.05]);
    for (const sx of [-1, 1]) {
      A(B, SHUT, [sx * 0.69, 0, 0.16], [0.42, 0.92, 0.05], [0, sx * 0.55, 0]);
      for (const sy of [-0.25, 0, 0.25]) A(B, M(shadeHex(opts.shutter ?? shadeHex(roof, 0.85), 0.6)), [sx * 0.69, sy, 0.19], [0.34, 0.035, 0.02], [0, sx * 0.55, 0]);
    }
    A(B, WOODL, [0, -0.55, 0.13], [1.1, 0.07, 0.28]);
    A(B, WOOD, [0, -0.68, 0.17], [0.94, 0.2, 0.24]);
    for (let k = 0; k < 7; k++) {
      const fx = -0.38 + k * 0.127 + (rng() - 0.5) * 0.04;
      A(GEO.sphereLo, M(0x4f8f3e), [fx, -0.53, 0.17 + (rng() - 0.5) * 0.08], 0.07 + rng() * 0.03);
      if (k % 2 === 0 || rng() < 0.4) A(GEO.sphereLo, M(FLOWER_COLS[(rng() * FLOWER_COLS.length) | 0]), [fx, -0.45 + rng() * 0.05, 0.2 + (rng() - 0.5) * 0.08], 0.055);
    }
  });
  for (const sx of [-1, 1]) { win(sx * 1.71, HD + 0.02, 0); win(sx * 1.71, -HD - 0.02, Math.PI); }
  win(HW + 0.02, 0, Math.PI / 2); win(-HW - 0.02, 0, -Math.PI / 2);
  // ---- yard props
  const barrel = (px, pz) => {
    A(GEO.cyl, WOODL, [px, 0.45, pz], [0.34, 0.9, 0.34]);
    for (const by of [0.18, 0.72]) A(GEO.cyl, IRON, [px, by, pz], [0.36, 0.06, 0.36]);
    A(GEO.cyl, WOOD, [px, 0.905, pz], [0.3, 0.02, 0.3]);
  };
  const crate = (px, pz, r, sz = 0.62) => K.frame([px, sz / 2, pz], r, () => {
    A(B, WOODL, [0, 0, 0], [sz, sz, sz]);
    for (const a of [-1, 1]) for (const b of [-1, 1]) { A(B, WOOD, [a * sz / 2, 0, b * sz / 2], [0.08, sz + 0.02, 0.08]); A(B, WOOD, [0, a * sz / 2, b * sz / 2], [sz + 0.02, 0.08, 0.08]); A(B, WOOD, [a * sz / 2, b * sz / 2, 0], [0.08, 0.08, sz + 0.02]); }
  });
  const side = rng() < 0.5 ? -1 : 1;
  barrel(side * (HW + 0.75), HD - 0.4);
  if (rng() < 0.7) barrel(side * (HW + 0.85), HD - 1.2);
  crate(-side * (HW + 0.75), HD - 0.6, rng());
  if (rng() < 0.6) K.frame([-side * (HW + 0.75), 0.62, HD - 0.6], rng(), () => A(B, WOODL, [0, 0.21, 0], [0.42, 0.42, 0.42]));
  // woodpile under the back eave
  for (let r = 0; r < 3; r++) for (let k = 0; k < 6 - r; k++) A(GEO.cyl, WOODL, [-1.4 + k * 0.25 + r * 0.125, 0.14 + r * 0.22, -HD - 1.05], [0.11, 1.3, 0.11], [Math.PI / 2, 0, 0]);
  // ---- healer's house: glowing crystal & sign
  let crystal = null;
  if (opts.crystal) {
    const p = K.point([0, YT + RISE + 1.5, 0]);
    crystal = part(GEO.octa, E(0x8ff3ff, 2.6), scene, [p.x, p.y, p.z], [0.45 * s, 0.8 * s, 0.45 * s]);
    World.spinners.push(crystal);
    // hanging shop sign beside the door
    A(B, IRON, [-1.0, 3.2, zf + 0.5], [0.05, 0.05, 0.9]);
    for (const k of [0.25, 0.75]) A(B, IRON, [-1.0, 3.08, zf + 0.15 + k * 0.7], [0.02, 0.22, 0.02]);
    A(B, WOOD, [-1.0, 2.78, zf + 0.62], [0.08, 0.5, 0.74]);
    A(B, E(0x8ff3ff, 1.7), [-1.0, 2.78, zf + 0.62], [0.11, 0.3, 0.5]);
  }
  World.colliders.push({ x, z, r: 3.2 * s });
  const cs = Math.cos(rot), sn = Math.sin(rot);
  for (const off of [-1.8, 1.8]) World.colliders.push({ x: x + cs * off * s, z: z - sn * off * s, r: 2.4 * s });
  for (const px of [-1, 1]) { const p = K.point([px * (HW + 0.8), 0, HD - 0.7]); World.colliders.push({ x: p.x, z: p.z, r: 0.45 * s }); }
  return { crystal };
}

// ---------------- lantern posts along the roads
function lantern(scene, x, z) {
  const K = TownKit || (TownKit = StaticKit());
  const y = groundY(x, z);
  const yaw = Math.atan2(-x, -z);                       // arm leans toward the island centre roads
  K.base.compose(new THREE.Vector3(x, y, z), new THREE.Quaternion().setFromEuler(new THREE.Euler(0, yaw, 0)), new THREE.Vector3(1, 1, 1));
  if (archReady() && archProp(K, 'lamp', [0, -0.12, 0], 0)) {
    archProp(K, 'pebbles_' + ((Math.abs(x * 7 + z) | 0) % 2), [0.1, 0, -0.15], x + z, 0.7);
    World.colliders.push({ x, z, r: 0.3 }); return;
  }
  const IRON = M(0x2e2a36), STONE = texMat('stone', 0xb8b0a4), B = GEO.box, A = K.add;
  A(B, STONE, [0, 0.18, 0], [0.46, 0.36, 0.46]);
  A(GEO.cylT, IRON, [0, 0.46, 0], [0.12, 0.22, 0.12]);
  A(GEO.cyl, IRON, [0, 1.5, 0], [0.055, 2.3, 0.055]);
  A(GEO.sphereLo, IRON, [0, 2.66, 0], 0.08);
  A(B, IRON, [0, 2.62, 0.22], [0.05, 0.05, 0.48]);
  A(B, IRON, [0, 2.48, 0.1], [0.04, 0.3, 0.04], [0.7, 0, 0]);
  A(B, IRON, [0, 2.52, 0.44], [0.02, 0.14, 0.02]);
  A(B, IRON, [0, 2.22, 0.44], [0.3, 0.05, 0.3]);
  for (const a of [-1, 1]) for (const b of [-1, 1]) A(B, IRON, [a * 0.13, 2.04, 0.44 + b * 0.13], [0.035, 0.36, 0.035]);
  A(B, IRON, [0, 1.86, 0.44], [0.28, 0.04, 0.28]);
  A(B, E(0xffcf8a, 2.8), [0, 2.04, 0.44], [0.2, 0.3, 0.2]);
  A(GEO.cone4, IRON, [0, 2.36, 0.44], [0.26, 0.22, 0.26], [0, Math.PI / 4, 0]);
  World.colliders.push({ x, z, r: 0.3 });
}

// ---------------- plaza: cobbles, benches, flower beds, notice board
function buildPlaza(scene) {
  if (archReady() && pbrSet('arch_cobble')) return buildPlazaArch(scene);
  const T = SITES.town, tx = townTextures(), y = groundY(T.x, T.z);
  const mat = toonMat({ color: 0xf4ede4, map: tx.cobble, alphaMap: tx.radial, transparent: true, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -3, polygonOffsetUnits: -6 });
  const disc = new THREE.Mesh(new THREE.CircleGeometry(9.6, 72).rotateX(-Math.PI / 2), mat);
  disc.position.set(T.x, y + 0.025, T.z); disc.receiveShadow = true; disc.renderOrder = -1; scene.add(disc);
  // a ring of kerb stones
  const K = TownKit || (TownKit = StaticKit());
  K.base.identity();
  const KERB = texMat('stone', 0xd6cec2);
  for (let i = 0; i < 36; i++) {
    const a = (i / 36) * Math.PI * 2;
    if (Math.abs(Math.sin(a)) > 0.93 || Math.abs(Math.cos(a) + 0.0) > 0.985) continue;   // gaps where the roads come in
    const px = T.x + Math.cos(a) * 9.2, pz = T.z + Math.sin(a) * 9.2;
    K.add(GEO.box, KERB, [px, groundY(px, pz) + 0.07, pz], [0.34, 0.16, 1.55], [0, -a, 0]);
  }
  // benches facing the fountain
  const WOODL = texMat('wood', 0x9a7250), IRON = M(0x2e2a36);
  for (const [bx, bz] of [[-5.4, 52.6], [5.4, 52.6], [-5.8, 45.2]]) {
    const yaw = Math.atan2(T.x - bx, T.z - bz);
    K.frame([bx, groundY(bx, bz), bz], yaw, () => {
      for (const k of [-0.13, 0.13]) K.add(GEO.box, WOODL, [0, 0.5, k], [1.8, 0.07, 0.22]);
      K.add(GEO.box, WOODL, [0, 0.9, -0.3], [1.8, 0.22, 0.06], [-0.18, 0, 0]);
      for (const sx of [-0.75, 0.75]) { K.add(GEO.box, IRON, [sx, 0.25, 0], [0.07, 0.5, 0.42]); K.add(GEO.box, IRON, [sx, 0.7, -0.27], [0.06, 0.45, 0.06], [-0.18, 0, 0]); }
    });
    World.colliders.push({ x: bx, z: bz, r: 0.7 });
  }
  // round flower beds at the plaza edge
  const rng = mulberry32(99);
  for (const [fx, fz] of [[-7.4, 56.4], [7.4, 56.4], [-7.9, 43.0]]) {
    K.add(GEO.cyl, KERB, [fx, groundY(fx, fz) + 0.18, fz], [1.0, 0.36, 1.0]);
    K.add(GEO.cyl, M(0x4a3426), [fx, groundY(fx, fz) + 0.34, fz], [0.88, 0.06, 0.88]);
    for (let k = 0; k < 16; k++) {
      const a = rng() * 6.28, r = Math.sqrt(rng()) * 0.75, px = fx + Math.cos(a) * r, pz = fz + Math.sin(a) * r;
      K.add(GEO.sphereLo, M(0x4f8f3e), [px, groundY(fx, fz) + 0.46, pz], 0.12 + rng() * 0.05);
      K.add(GEO.sphereLo, M(FLOWER_COLS[(rng() * FLOWER_COLS.length) | 0]), [px, groundY(fx, fz) + 0.6 + rng() * 0.06, pz], 0.07);
    }
    World.colliders.push({ x: fx, z: fz, r: 1.05 });
  }
}

// authored plaza: PBR cobbles (setts with sand/moss joints) feathered into the terrain, dressed kerb stones,
// trestle benches and fieldstone flower beds
function buildPlazaArch(scene) {
  const T = SITES.town, y = groundY(T.x, T.z), set = pbrSet('arch_cobble'), tx = townTextures();
  const rep = (t, k) => { const c = t.clone(); c.repeat.set(k, k); c.needsUpdate = true; return c; };
  const R = 9.6, k = (R * 2) / 2.1;                      // one 3 m texture tile spread over 2.1 m: setts ~12 cm
  const mat = new THREE.MeshStandardMaterial({ color: 0xe2dcd2, map: rep(set.albedo, k), normalMap: rep(set.normal, k), roughnessMap: rep(set.orm, k), aoMap: rep(set.orm, k), aoMapIntensity: 0.8,
    normalScale: new THREE.Vector2(0.75, 0.75), roughness: 1.15, alphaMap: tx.radial, transparent: true, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -3, polygonOffsetUnits: -6,
    envMapIntensity: (typeof Lighting !== 'undefined' ? Lighting.envFor('ground') : 0.5) * 0.8 });
  archPatch(mat, { grime: 0x4a3e32, vary: 0.3, ao: 0.6 });
  // ground-hugging disc: follows the terrain so the feathered edge never floats or cuts in
  const geo = new THREE.CircleGeometry(R, 96, 0, Math.PI * 2);
  const g2 = new THREE.RingGeometry(0.001, R, 96, 12); g2.rotateX(-Math.PI / 2);
  const pa = g2.attributes.position;
  for (let i = 0; i < pa.count; i++) pa.setY(i, groundY(T.x + pa.getX(i), T.z + pa.getZ(i)) - y + 0.03);
  g2.computeVertexNormals();
  const uv = g2.attributes.uv; for (let i = 0; i < uv.count; i++) uv.setXY(i, pa.getX(i) / (2 * R) + 0.5, -pa.getZ(i) / (2 * R) + 0.5);
  // COLOR_0 for the architecture patch: darker, dirtier setts toward the kerb and in a damp ring around the basin
  const col = new Float32Array(pa.count * 3);
  for (let i = 0; i < pa.count; i++) {
    const r = Math.hypot(pa.getX(i), pa.getZ(i));
    col[i * 3] = 1 - 0.35 * smooth(3.6, 3.0, r);
    col[i * 3 + 1] = 0.5 + 0.5 * Math.sin(pa.getX(i) * 0.7 + Math.cos(pa.getZ(i) * 0.5) * 2.0);
    col[i * 3 + 2] = Math.max(smooth(6.5, 9.4, r) * 0.55, smooth(4.2, 3.0, r) * 0.45);
  }
  g2.setAttribute('color', new THREE.BufferAttribute(col, 3));
  geo.dispose();
  const disc = new THREE.Mesh(g2, mat);
  disc.position.set(T.x, y, T.z); disc.receiveShadow = true; disc.renderOrder = -1; scene.add(disc);
  const K = TownKit || (TownKit = StaticKit());
  K.base.identity();
  for (let i = 0; i < 40; i++) {
    const a = (i / 40) * Math.PI * 2;
    if (Math.abs(Math.sin(a)) > 0.93 || Math.abs(Math.cos(a)) > 0.985) continue;   // gaps where the roads come in
    const px = T.x + Math.cos(a) * 9.25, pz = T.z + Math.sin(a) * 9.25;
    archProp(K, 'kerb_' + (i % 3), [px, groundY(px, pz) + 0.02, pz], -a + (i % 2 ? Math.PI : 0), 0.95);
  }
  for (const [bx, bz] of [[-5.4, 52.6], [5.4, 52.6], [-5.8, 45.2]]) {
    const yaw = Math.atan2(T.x - bx, T.z - bz);
    archProp(K, 'bench', [bx, groundY(bx, bz) - 0.02, bz], yaw);
    World.colliders.push({ x: bx, z: bz, r: 0.7 });
  }
  for (const [fx, fz] of [[-7.4, 56.4], [7.4, 56.4], [-7.9, 43.0]]) {
    archProp(K, 'planter', [fx, groundY(fx, fz) - 0.04, fz], fx * 3.1 + fz);
    World.colliders.push({ x: fx, z: fz, r: 1.05 });
  }
}

// ---------------- chimney smoke: soft sprites rising and drifting with the wind
function buildSmoke(scene, points) {
  const per = 16, n = points.length * per;
  const pos = new Float32Array(n * 3), seed = new Float32Array(n);
  points.forEach((p, i) => { for (let k = 0; k < per; k++) { const j = i * per + k; pos[j * 3] = p.x; pos[j * 3 + 1] = p.y; pos[j * 3 + 2] = p.z; seed[j] = (k + Math.random() * 0.6) / per; } });
  const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.BufferAttribute(pos, 3)); g.setAttribute('seed', new THREE.BufferAttribute(seed, 1));
  const mat = new THREE.ShaderMaterial({
    uniforms: Object.assign(THREE.UniformsUtils.merge([THREE.UniformsLib.fog]), { uTime: Shared.time, uTex: { value: TEX.cloud }, uTint: { value: new THREE.Color(0xffd8c0) } }),
    transparent: true, depthWrite: false, fog: true,
    vertexShader: `attribute float seed; uniform float uTime; varying float vA; varying float vAge; ${FOG_V}
      void main(){
        float age = fract(uTime * 0.075 + seed);
        vec3 p = position;
        p.y += age * 5.2;
        p.x += age * age * 2.6 + sin(seed * 41.0 + uTime * 0.6) * 0.35 * age;
        p.z += age * age * 1.1 + cos(seed * 23.0 + uTime * 0.5) * 0.3 * age;
        vAge = age; vA = smoothstep(0.0, 0.12, age) * (1.0 - smoothstep(0.55, 1.0, age));
        vec4 mvPosition = modelViewMatrix * vec4(p, 1.0);
        gl_PointSize = (560.0 + 2100.0 * age) / -mvPosition.z;
        gl_Position = projectionMatrix * mvPosition;
        #include <fog_vertex>
      }`,
    fragmentShader: `uniform sampler2D uTex; uniform vec3 uTint; varying float vA; varying float vAge; ${FOG_F}
      void main(){
        float a = texture2D(uTex, gl_PointCoord).a * vA * 0.62;
        vec3 c = mix(vec3(0.66, 0.64, 0.7), uTint, 0.25 + vAge * 0.35);
        gl_FragColor = vec4(c, a);
        #include <fog_fragment>
      }`,
  });
  const pts = new THREE.Points(g, mat); pts.frustumCulled = false; scene.add(pts);
  return pts;
}

// ---------------- fountain of healing: octagonal basin, upper bowl, living water
function buildFountain(scene) {
  const T = SITES.town, fy = groundY(T.x, T.z);
  const f = grp(scene, [T.x, fy, T.z]);
  const authored = archReady() && archPiece('fountain').length;
  if (authored) {
    // carved limestone basin, pedestal and bowl (Blender) with a ring of worn paving stones
    for (const [bin, g] of archPiece('fountain')) { const m = new THREE.Mesh(g, archMat(bin)); m.castShadow = true; m.receiveShadow = true; f.add(m); }
  } else {
    // the basin wall wraps ~16 m of stone, so it gets its own copy of the texture tiled around
    const bt = townTextures().stone.clone(); bt.repeat.set(9, 0.55); bt.needsUpdate = true;
    const BASIN = toonMat({ color: 0xd8d0c4, map: bt }), STONE = M(0xcfc7bb), STONE2 = M(0xb4aca2);
    const oct = new THREE.CylinderGeometry(1, 1, 1, 8);
    part(oct, BASIN, f, [0, 0.32, 0], [2.6, 0.64, 2.6], [0, Math.PI / 8, 0]);
    part(oct, STONE2, f, [0, 0.68, 0], [2.78, 0.12, 2.78], [0, Math.PI / 8, 0]);
    part(new THREE.CylinderGeometry(0.78, 1, 1, 8), STONE, f, [0, 1.25, 0], [0.42, 1.2, 0.42], [0, Math.PI / 8, 0]);
    part(new THREE.CylinderGeometry(1, 0.55, 1, 16), STONE, f, [0, 1.95, 0], [1.05, 0.32, 1.05]);
    part(GEO.torus, STONE2, f, [0, 2.1, 0], [1.02, 1.02, 1.6], [Math.PI / 2, 0, 0]);
    part(GEO.cylT, STONE, f, [0, 2.25, 0], [0.16, 0.3, 0.16]);
  }
  // water: animated ripples + sparkles, emissive cyan
  const wmat = new THREE.ShaderMaterial({
    uniforms: { uTime: Shared.time, uCol: { value: new THREE.Color(0x5fd8ff) } },
    vertexShader: 'varying vec2 vP; void main(){ vP = position.xy; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }',
    fragmentShader: `uniform float uTime; uniform vec3 uCol; varying vec2 vP;
      void main(){ float r = length(vP); float w = sin(r * 14.0 - uTime * 3.0) * 0.5 + 0.5; float w2 = sin(r * 31.0 - uTime * 5.0 + vP.x * 3.0) * 0.5 + 0.5;
        vec3 c = uCol * (0.75 + 0.35 * w) + vec3(0.6, 0.95, 1.0) * pow(w2, 12.0) * 0.8; c += vec3(0.9, 1.0, 1.0) * smoothstep(0.85, 1.0, r) * 0.35;
        gl_FragColor = vec4(c * 1.15, 1.0); }`,
  });
  part(authored ? new THREE.CircleGeometry(1, 8, Math.PI / 8) : GEO.circle, wmat, f, [0, 0.66, 0], authored ? 2.62 : 2.42, [-Math.PI / 2, 0, 0]).castShadow = false;
  part(GEO.circle, wmat, f, [0, 2.06, 0], 0.92, [-Math.PI / 2, 0, 0]).castShadow = false;
  // falling sheets of water from the upper bowl
  const fall = new THREE.ShaderMaterial({
    uniforms: { uTime: Shared.time }, transparent: true, depthWrite: false, side: THREE.DoubleSide,
    vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }',
    fragmentShader: `uniform float uTime; varying vec2 vUv;
      void main(){
        float col = vUv.x * 40.0, id = floor(col);
        float w = 0.16 + 0.12 * fract(sin(id * 12.9898) * 43758.5);
        float stream = smoothstep(w, 0.0, abs(fract(col) - 0.5));                       // thin separate streams
        float flow = fract(vUv.y * 2.4 + uTime * (1.7 + fract(id * 0.37) * 0.6) + id * 0.37);
        float a = stream * (0.3 + 0.7 * smoothstep(0.55, 1.0, flow)) * smoothstep(0.0, 0.25, vUv.y) * smoothstep(1.0, 0.85, vUv.y);
        gl_FragColor = vec4(vec3(0.72, 0.95, 1.0) * 1.5, a * 0.6); }`,
  });
  const sheet = new THREE.Mesh(new THREE.CylinderGeometry(1.06, 1.4, 1.4, 64, 1, true), fall);
  sheet.position.set(0, 1.4, 0); f.add(sheet);
  const cr = part(GEO.octa, E(0x8ff3ff, 3), f, [0, 2.9, 0], [0.42, 0.75, 0.42]);
  f.traverse((o) => { if (o.isMesh && !o.material.isMeshBasicMaterial && !o.material.isShaderMaterial) { o.castShadow = true; o.receiveShadow = true; } });
  if (authored) f.traverse((o) => { if (o.isMesh && o.material.isShaderMaterial && o.position.y < 1) o.position.y = 0.64; });
  World.colliders.push({ x: T.x, z: T.z, r: 2.9 });
  const pl = new THREE.PointLight(0x8ff3ff, 18, 16, 1.6); pl.position.set(T.x, fy + 2.8, T.z); scene.add(pl);
  return { f, cr };
}

// ---------------- fluted column shaft (unit radius/height, centred), slight taper toward the top
let _fluted = null;
function flutedColumnGeo() {
  if (_fluted) return _fluted;
  const g = new THREE.CylinderGeometry(0.9, 1, 1, 48, 6, false);
  const p = g.attributes.position, v = new THREE.Vector3();
  for (let i = 0; i < p.count; i++) {
    v.fromBufferAttribute(p, i);
    const r = Math.hypot(v.x, v.z); if (r < 1e-4) continue;
    const a = Math.atan2(v.z, v.x), k = 1 - 0.075 * Math.pow(Math.abs(Math.cos(a * 8)), 0.6);
    p.setXYZ(i, v.x * k, v.y, v.z * k);
  }
  g.computeVertexNormals();
  return (_fluted = g);
}

// ---------------- hooks called from 03_world.js (buildTown / updateWorld)
// buildTownExtras(scene, K): add more village props; static parts go into K (StaticKit, base must be set by you), animated parts to the scene
function buildTownExtras(scene, K) {
  if (!archReady()) return;
  const T = SITES.town;
  // the village well on the west lane, a garden fence behind the north cottages, scattered stones along the lanes
  K.base.identity();
  const wx = T.x - 7.6, wz = T.z - 12.4, wy = groundY(wx, wz);
  if (archProp(K, 'well', [wx, wy - 0.05, wz], 0.5)) {
    const wm = Arch.meta.well; const M = new THREE.Matrix4().compose(new THREE.Vector3(wx, wy - 0.05, wz), new THREE.Quaternion().setFromEuler(new THREE.Euler(0, 0.5, 0)), new THREE.Vector3(1, 1, 1));
    if (wm) archQueueRoof(wm, M, 0x8a4a36, mulberry32(4242));
    World.colliders.push({ x: wx, z: wz, r: 1.25 });
    if (typeof groundStamp === 'function') groundStamp(wx, wz, 2.2, { dirt: 0.6, dark: 0.35 }, { soft: 0.6, noise: 0.5 });
  }
  for (const [fx, fz, yaw, n] of [[T.x - 17.6, T.z + 13.6, 0.55, 3], [T.x + 17.2, T.z + 12.4, -0.6, 3], [T.x + 16.4, T.z - 18.2, 0.35 - Math.PI / 2, 2]]) {
    const c = Math.cos(yaw), s = Math.sin(yaw);
    for (let i = 0; i < n; i++) {
      const px = fx + c * (i - (n - 1) / 2) * 2.4, pz = fz - s * (i - (n - 1) / 2) * 2.4;
      archProp(K, 'fence', [px, groundY(px, pz) - 0.03, pz], yaw + (i % 2 ? 0.03 : -0.02));
      World.colliders.push({ x: px, z: pz, r: 0.55 });
    }
  }
  const rng = mulberry32(911);
  for (const P of PATHS) for (let i = 0; i < P.length - 1; i++) {
    const [ax, az] = P[i], [bx, bz] = P[i + 1], L = Math.hypot(bx - ax, bz - az);
    for (let d = 2; d < L; d += 3 + rng() * 5) {
      const t = d / L, nx = -(bz - az) / L, nz = (bx - ax) / L, sd = (rng() < 0.5 ? -1 : 1) * (2.1 + rng() * 1.4);
      const px = lerp(ax, bx, t) + nx * sd, pz = lerp(az, bz, t) + nz * sd;
      if (Math.hypot(px - T.x, pz - T.z) < 10.5 || Math.hypot(px - T.x, pz - T.z) > 40) continue;
      archProp(K, rng() < 0.5 ? 'pebbles_0' : 'pebbles_1', [px, groundY(px, pz), pz], rng() * 6.28, 0.7 + rng() * 0.5);
    }
  }
  archBuildTiles(scene);
  window.__town = Object.assign({ smoke: TownSmoke.length }, Arch.stats);
}
function updateTownExtras(dt) {
  // candle-like flicker on the lantern glass (one shared material for every lantern in the village)
  const g = Arch.mats.get('glow|');
  if (g) {
    Arch.t = (Arch.t || 0) + dt;
    const t = Arch.t, f = 0.92 + 0.05 * Math.sin(t * 7.3) + 0.03 * Math.sin(t * 13.1 + 1.7) + 0.02 * Math.sin(t * 23.0);
    g.color.setRGB(1.0, 0.7843, 0.5294).convertSRGBToLinear().multiplyScalar(2.6 * f);
  }
}
