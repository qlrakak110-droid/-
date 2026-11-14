// Blender hero assets (tools/blender, assets/chars/<hero>/): decode the embedded EDM1 binary once and feed its parts to
// a design's kit as ordinary skinned pieces, so the result is a normal character of the rig (cloth, springs, glow
// control, shadows, afterimages, dispose all work unchanged).
//
//   import pilotAsset from '../../assets/chars/pilot/index.js';      // registers + embeds the binary (esbuild `binary`)
//   import { addAsset, assetCloth } from '../char/assets.js';
//   const design = {
//     ..., cloth: assetCloth(pilotAsset, { skirtF: { damping: 0.05 } }),           // runtime cloth panels draped in Blender
//     build(kit) { addAsset(kit, pilotAsset, { slotMap: { cloth: 'robe' }, looks: { robe: { color: [0.05, 0.02, 0.09] } } }); },
//   };
//
// Format (written by tools/blender/ed/export.py; see tools/blender/README.md "Asset format"):
//   'EDM1' | u32 JSON length | JSON (padded to 4 bytes) | data block (every offset in the JSON is relative to it, 4-aligned)
//   per part: pos u16x4 (in bmin..bmax, game bind space), nrm i8x3 + u8 cavity (x2/255), col u8x3 (sqrt(linear / 2)) + u8
//   look, skin u8x4 bone palette indices + u8x4 weights (sum 255, or 255 x (1 - cloth share)), optional glow u8x4 masks,
//   uvw u16x4 (uv-set coordinates in min..max), uv u16x2 (baked-map coordinates), cloth u16x4 (panel u, v, share), idx.
// Bone NAMES are stored per part and resolved against the rig at load; cloth vertices store panel coordinates and are
// turned into bilinear weights on whatever particle grid the quality tier runs.

import * as THREE from 'three';
import { kitOpts } from './kit/geo.js';

const REG = new Map();
const now = () => (typeof performance !== 'undefined' ? performance.now() : Date.now()); // measurement only, never simulation

/**
 * Register an embedded asset (called by the generated assets/chars/<hero>/index.js). Decoding is lazy: the first
 * getAsset() / addAsset() / assetCloth() decodes the header, parts are dequantised on first use, and both fighters of a
 * mirror match share the result.
 * @param {string} hero
 * @param {Uint8Array|ArrayBuffer} bin
 * @returns {{hero: string}} handle
 */
export function registerAsset(hero, bin) {
  if (!REG.has(hero)) REG.set(hero, { hero, bin, asset: null });
  return REG.get(hero);
}

/** Registered hero asset ids. */
export function listAssets() { return [...REG.keys()]; }

/**
 * Decoded asset: { hero, head (JSON), parts, panels, looks, textures, stats: { bytes, decodeMs, partMs, triangles } }.
 * @param {string|{hero: string}} ref
 */
export function getAsset(ref) {
  const e = REG.get(typeof ref === 'string' ? ref : ref && ref.hero);
  if (!e) throw new Error('char assets: no asset registered for ' + (typeof ref === 'string' ? ref : ref && ref.hero) + ' (import assets/chars/<hero>/index.js)');
  if (!e.asset) e.asset = decode(e.hero, e.bin);
  return e.asset;
}

function decode(hero, bin) {
  const t0 = now();
  const u8 = bin instanceof Uint8Array ? bin : new Uint8Array(bin);
  if (u8.length < 8 || u8[0] !== 69 || u8[1] !== 68 || u8[2] !== 77 || u8[3] !== 49) throw new Error(`char assets ${hero}: not an EDM1 file`);
  const jl = u8[4] | (u8[5] << 8) | (u8[6] << 16) | (u8[7] << 24);
  const head = JSON.parse(new TextDecoder().decode(u8.subarray(8, 8 + jl)));
  // copy the data block into its own (aligned) buffer once: typed array views need aligned offsets
  const data = u8.slice(8 + jl).buffer;
  const panels = {};
  for (const p of head.panels || []) panels[p.name] = { ...p, restG: new Float32Array(data, p.rest, p.cols * p.rows * 3) };
  const asset = {
    hero, head, data, panels, looks: head.looks, parts: head.parts, textures: null,
    stats: { bytes: u8.length, decodeMs: 0, partMs: 0, triangles: head.triangles, vertices: head.vertices },
  };
  asset.stats.decodeMs = now() - t0;
  return asset;
}

/** Dequantised vertex streams of one part (cached on the part). */
function partData(asset, part) {
  if (part._d) return part._d;
  const t0 = now();
  const D = asset.data, n = part.vertices;
  const q = new Uint16Array(D, part.pos, n * 4);
  const pos = new Float32Array(n * 3), nrm = new Float32Array(n * 3), cav = new Float32Array(n), col = new Float32Array(n * 3);
  const look = new Uint8Array(n);
  const s = [0, 1, 2].map((a) => (part.bmax[a] - part.bmin[a]) / 65535);
  const nq = new Int8Array(D, part.nrm, n * 4), nu = new Uint8Array(D, part.nrm, n * 4), cq = new Uint8Array(D, part.col, n * 4);
  for (let i = 0; i < n; i++) {
    for (let a = 0; a < 3; a++) pos[i * 3 + a] = part.bmin[a] + q[i * 4 + a] * s[a];
    const x = nq[i * 4], y = nq[i * 4 + 1], z = nq[i * 4 + 2], l = Math.hypot(x, y, z) || 1;
    nrm[i * 3] = x / l; nrm[i * 3 + 1] = y / l; nrm[i * 3 + 2] = z / l;
    cav[i] = (nu[i * 4 + 3] / 255) * 2;
    for (let a = 0; a < 3; a++) { const c = cq[i * 4 + a] / 255; col[i * 3 + a] = c * c * 2; }
    look[i] = cq[i * 4 + 3];
  }
  const skin = new Uint8Array(D, part.skin, n * 8);
  let glow = null, uvw = null, uv = null, cloth = null;
  if (part.glow !== undefined) { const g = new Uint8Array(D, part.glow, n * 4); glow = new Float32Array(n * 3); for (let i = 0; i < n; i++) for (let a = 0; a < 3; a++) glow[i * 3 + a] = g[i * 4 + a] / 255; }
  if (part.uvw) {
    const u = new Uint16Array(D, part.uvw.off, n * 4), lo = part.uvw.min, hi = part.uvw.max;
    uvw = new Float32Array(n * 3);
    for (let i = 0; i < n; i++) for (let a = 0; a < 3; a++) uvw[i * 3 + a] = lo[a] + (u[i * 4 + a] / 65535) * (hi[a] - lo[a]);
  }
  if (part.bake) { const u = new Uint16Array(D, part.bake.off, n * 4); uv = new Float32Array(n * 3); for (let i = 0; i < n; i++) for (let a = 0; a < 3; a++) uv[i * 3 + a] = u[i * 4 + a] / 65535; }
  if (part.cloth) { const c = new Uint16Array(D, part.cloth.off, n * 4); cloth = new Float32Array(n * 3); for (let i = 0; i < n; i++) for (let a = 0; a < 3; a++) cloth[i * 3 + a] = c[i * 4 + a] / 65535; }
  const index = part.idx.type === 32 ? new Uint32Array(D, part.idx.off, part.triangles * 3) : new Uint16Array(D, part.idx.off, part.triangles * 3);
  part._d = { pos, nrm, cav, col, look, skin, glow, uvw, uv, cloth, index };
  asset.stats.partMs += now() - t0;
  return part._d;
}

/** The asset look as a kit look ({ color, rough, metal, set, amt, inlay, vein, eye, occ, wear }), merged with overrides. */
function kitLook(L, over) {
  const g = L.glow || [0, 0, 0];
  return {
    ...L, inlay: Math.max(g[0] || 0, L.inlay || 0), vein: Math.max(g[1] || 0, L.vein || 0), eye: Math.max(g[2] || 0, L.eye || 0),
    glow: undefined, ...(over || {}),
  };
}

/** Particle grid size of a cloth panel in this rig (the quality tier scales it): { first, C, R } or null. */
function panelGrid(rig, name) {
  const first = rig.index[`${name}_0_0`];
  if (first === undefined) return null;
  let C = 0, R = 0;
  while (rig.index[`${name}_${C}_0`] !== undefined) C++;
  while (rig.index[`${name}_0_${R}`] !== undefined) R++;
  return { first, C, R };
}

/**
 * Add an asset's parts to a design's kit (call inside design.build(kit, S, rig)).
 * @param {object} kit
 * @param {string|{hero: string}} ref   asset handle or hero id
 * @param {object} [o]
 *   parts     names to add (array) or fn(name, part) -> bool (default: all)      exclude   names to skip
 *   slotMap   { assetSlot: designSlot } (default: the asset's slot names, which the design's `materials` must provide)
 *   looks     { lookName: overrides } (any kit look field: color (linear), rough, metal, set, amt, inlay, vein, eye ...)
 *   lod       'low' drops parts flagged 'hi' (none in the pilot)
 * @returns {{ triangles: number, parts: string[] }}
 */
export function addAsset(kit, ref, o = {}) {
  const asset = getAsset(ref), rig = kit.rig;
  const pick = typeof o.parts === 'function' ? o.parts : Array.isArray(o.parts) ? (n) => o.parts.includes(n) : () => true;
  const skip = new Set(o.exclude || []);
  let tris = 0;
  const added = [];
  for (const part of asset.parts) {
    if (!pick(part.name, part) || skip.has(part.name)) continue;
    if (o.lod === 'low' && part.flags.includes('hi')) continue;
    const d = partData(asset, part);
    const slot = (o.slotMap && o.slotMap[part.slot]) || part.slot;
    const pal = part.bones.map((b) => {
      const i = rig.index[b];
      if (i === undefined) throw new Error(`char assets ${asset.hero}/${part.name}: the rig has no bone ${b}`);
      return i;
    });
    const grid = part.cloth ? panelGrid(rig, part.cloth.panel) : null;
    const anchor = part.cloth && asset.panels[part.cloth.panel] ? rig.index[asset.panels[part.cloth.panel].anchors[0]] : rig.index.hips;
    const wbuf = [];
    /** Skin weights of asset vertex v: stored bone weights + the cloth share as bilinear particle weights. */
    const weightsOf = (v) => {
      wbuf.length = 0;
      let tot = 0;
      for (let k = 0; k < 4; k++) { const w = d.skin[v * 8 + 4 + k]; if (w) { wbuf.push([pal[d.skin[v * 8 + k]], w / 255]); tot += w / 255; } }
      if (d.cloth) {
        const share = d.cloth[v * 3 + 2];
        if (share > 1e-4 && grid) {
          const fu = d.cloth[v * 3] * (grid.C - 1), fv = d.cloth[v * 3 + 1] * (grid.R - 1);
          const i0 = Math.min(grid.C - 2, Math.floor(fu)), j0 = Math.min(grid.R - 2, Math.floor(fv)), tu = fu - i0, tv = fv - j0;
          const b = (i, j) => grid.first + j * grid.C + i;
          wbuf.push([b(i0, j0), share * (1 - tu) * (1 - tv)], [b(i0 + 1, j0), share * tu * (1 - tv)], [b(i0, j0 + 1), share * (1 - tu) * tv], [b(i0 + 1, j0 + 1), share * tu * tv]);
          tot += share;
        } else if (tot < 1e-4) wbuf.push([anchor, 1]);
      }
      if (!wbuf.length) wbuf.push([anchor, 1]);
      return wbuf.filter((x) => x[1] > 1e-5);
    };
    for (const run of part.runs) {
      const L = kitLook(asset.looks[run.look], o.looks && o.looks[asset.looks[run.look].name]);
      const v0 = run.v0, vn = run.vn;
      const g = new THREE.BufferGeometry();
      g.setAttribute('position', new THREE.BufferAttribute(d.pos.slice(v0 * 3, (v0 + vn) * 3), 3));
      g.setAttribute('normal', new THREE.BufferAttribute(d.nrm.slice(v0 * 3, (v0 + vn) * 3), 3));
      g.setAttribute('cav', new THREE.BufferAttribute(d.cav.slice(v0, v0 + vn), 1));
      if (d.uvw) g.setAttribute('uvw', new THREE.BufferAttribute(d.uvw.slice(v0 * 3, (v0 + vn) * 3), 3));
      const idx = d.index.subarray(run.i0, run.i0 + run.in);
      const li = vn > 65535 ? new Uint32Array(idx.length) : new Uint16Array(idx.length);
      for (let k = 0; k < idx.length; k++) li[k] = idx[k] - v0;
      g.setIndex(new THREE.BufferAttribute(li, 1));
      const lc = Array.isArray(L.color) ? L.color : [1, 1, 1];
      const ko = {
        color: (p, n, i) => [lc[0] * d.col[(v0 + i) * 3], lc[1] * d.col[(v0 + i) * 3 + 1], lc[2] * d.col[(v0 + i) * 3 + 2]],
        glow: d.glow ? (p, n, i) => [d.glow[(v0 + i) * 3], d.glow[(v0 + i) * 3 + 1], d.glow[(v0 + i) * 3 + 2]] : undefined,
      };
      kit.addSkinned(slot, g, (x, y, z, i) => weightsOf(v0 + i), kitOpts(g, L, ko));
      if (d.uv && part.bake.maps) {
        // remember the baked-map coordinates by bind position + normal: attachAssetMaps() finds these vertices in the
        // merged slot mesh (the kit's merge keeps the exact float positions)
        const bk = bakeIndex(kit, slot, part.bake.maps);
        // UV seams: the exporter splits a vertex per UV island, so several asset vertices can share one bind position and
        // normal; they are queued in asset order and handed out in the merged mesh's (same) order by attachAssetMaps.
        // (A single entry per key gave one side of every smooth seam the other island's coordinates: streaks of foreign
        // texels across the atlas, read as broken chrome along every ridge of a smart-projected bake.)
        for (let i = 0; i < vn; i++) {
          const v = v0 + i;
          if (!(d.uv[v * 3 + 2] > 0)) continue;
          const k = vkey(d.pos, d.nrm, v), e = [d.uv[v * 3], d.uv[v * 3 + 1], d.uv[v * 3 + 2]], q = bk.map.get(k);
          if (q) q.push(e); else bk.map.set(k, [e]);
        }
      }
      tris += run.in / 3;
    }
    added.push(part.name);
  }
  if (BAKED.has(kit) && o.design) LAST_BAKE.set(o.design, BAKED.get(kit));
  return { triangles: tris, parts: added };
}

const BAKED = new WeakMap();   // kit -> { slot: { maps, map: Map(key -> [u, v, w]) } }
const vkey = (P, N, v) => `${P[v * 3]},${P[v * 3 + 1]},${P[v * 3 + 2]},${Math.round(N[v * 3] * 64)},${Math.round(N[v * 3 + 1] * 64)},${Math.round(N[v * 3 + 2] * 64)}`;
function bakeIndex(kit, slot, maps) {
  if (!BAKED.has(kit)) BAKED.set(kit, {});
  const all = BAKED.get(kit);
  if (all[slot] && all[slot].maps !== maps) console.warn(`char assets: slot ${slot} already carries maps ${all[slot].maps}; ${maps} ignored (one baked map set per slot)`);
  return (all[slot] = all[slot] || { maps, map: new Map() });
}

/**
 * Give a created character the baked maps of its asset parts (call from design.attach(char), after createCharacter):
 * adds the `bake` vertex attribute (u, v, weight) to the slot meshes that carry baked parts and points their material at
 * the textures. Skipped on the low tier (no attribute, the shader's uBakeOn stays 0: vertex data only).
 * @returns {{ slots: string[], vertices: number }}
 */
export function attachAssetMaps(char, ref, quality) {
  const out = { slots: [], vertices: 0 };
  const kitData = char.kitBake || null;
  const all = kitData || LAST_BAKE.get(char.design) || null;
  if (!all || (quality && quality.tier === 'low')) return out;
  const tex = assetTextures(ref);
  for (const [slot, b] of Object.entries(all)) {
    const mesh = char.meshes[slot];
    if (!mesh) continue;
    const g = mesh.geometry, P = g.attributes.position.array, N = g.attributes.normal.array, n = g.attributes.position.count;
    const arr = new Float32Array(n * 3);
    let hit = 0;
    const used = new Map();   // key -> entries handed out (seam duplicates come in the same order as in the asset)
    for (let v = 0; v < n; v++) {
      const k = vkey(P, N, v), q = b.map.get(k);
      if (!q) continue;
      const j = used.get(k) || 0;
      used.set(k, j + 1);
      const e = q[Math.min(j, q.length - 1)];
      arr[v * 3] = e[0]; arr[v * 3 + 1] = e[1]; arr[v * 3 + 2] = e[2]; hit++;
    }
    if (!hit) continue;
    g.setAttribute('bake', new THREE.BufferAttribute(arr, 3));
    const u = mesh.material.userData.kit;
    if (tex[b.maps + '_n']) u.uBakeN.value = tex[b.maps + '_n'];
    if (tex[b.maps + '_m']) u.uBakeM.value = tex[b.maps + '_m'];
    u.uBakeOn.value = 1;
    out.slots.push(slot); out.vertices += hit;
  }
  return out;
}
const LAST_BAKE = new WeakMap();   // design -> the bake index of its last build (createCharacter does not expose the kit)

/**
 * Runtime cloth panels defined in Blender (edlib define_panel: the verlet grid starts where the Blender drape left the
 * cloth): rig cloth specs with `mesh: false` (the asset carries the render geometry, bound by panel coordinates).
 * @param {string|{hero: string}} ref
 * @param {object} [over]  { panelName: { any rig cloth option } }
 * @returns {object[]} specs for design.cloth
 */
export function assetCloth(ref, over = {}) {
  const asset = getAsset(ref);
  return Object.values(asset.panels).filter((p) => p.used !== false && p.top).map((p) => {
    const C = p.cols, R = p.rows, G = p.restG;
    // offset(u, v) = grid(u, v) - grid(u, 0): the rest shape below the pinned edge, sampled at any tier's resolution
    const at = (u, v, a) => {
      const fu = Math.min(Math.max(u, 0), 1) * (C - 1), fv = Math.min(Math.max(v, 0), 1) * (R - 1);
      const i = Math.min(C - 2, Math.floor(fu)), j = Math.min(R - 2, Math.floor(fv)), tu = fu - i, tv = fv - j;
      const g = (ii, jj) => G[(jj * C + ii) * 3 + a];
      return (g(i, j) * (1 - tu) + g(i + 1, j) * tu) * (1 - tv) + (g(i, j + 1) * (1 - tu) + g(i + 1, j + 1) * tu) * tv;
    };
    return {
      ...p.params, name: p.name, top: p.top, cols: C, rows: R, pinRows: 1, length: 0, flare: 0, drape: [0, -1, 0], mesh: false,
      offset: (u, v) => [at(u, v, 0) - at(u, 0, 0), at(u, v, 1) - at(u, 0, 1), at(u, v, 2) - at(u, 0, 2)],
      ...(over[p.name] || {}),
    };
  });
}

/**
 * Baked maps of an asset as THREE textures ({ name: Texture }), created once and shared; images decode asynchronously
 * (assetTexturesReady() resolves when every one is uploaded-ready).
 */
export function assetTextures(ref) {
  const asset = getAsset(ref);
  if (asset.textures) return asset.textures;
  asset.textures = {};
  asset.texturePromises = [];
  for (const t of asset.head.textures || []) {
    const bytes = new Uint8Array(asset.data, t.off, t.length);
    const tex = new THREE.Texture();
    tex.name = `${asset.hero}:${t.name}`;
    tex.colorSpace = THREE.NoColorSpace;   // normal / mask data: linear
    tex.flipY = true;      // Blender writes v = 0 at the bottom row
    tex.wrapS = tex.wrapT = THREE.ClampToEdgeWrapping;
    tex.generateMipmaps = true;
    tex.minFilter = THREE.LinearMipmapLinearFilter;
    tex.userData.kind = t.kind;
    asset.textures[t.name] = tex;
    if (typeof Image === 'undefined' || typeof Blob === 'undefined') continue;   // Node (rig export, tests)
    const url = URL.createObjectURL(new Blob([bytes], { type: t.mime }));
    const img = new Image();
    asset.texturePromises.push(new Promise((res) => {
      img.onload = () => { tex.image = img; tex.needsUpdate = true; URL.revokeObjectURL(url); res(); };
      img.onerror = () => { URL.revokeObjectURL(url); res(); };
    }));
    img.src = url;
  }
  return asset.textures;
}

/** Resolves when every baked map of the asset has decoded. */
export function assetTexturesReady(ref) {
  const asset = getAsset(ref);
  assetTextures(ref);
  return Promise.all(asset.texturePromises || []);
}

/** { bytes, decodeMs, partMs, triangles, vertices, parts: [{ name, slot, triangles, flags }], textures } of an asset. */
export function assetStats(ref) {
  const a = getAsset(ref);
  return { ...a.stats, parts: a.parts.map((p) => ({ name: p.name, slot: p.slot, triangles: p.triangles, flags: p.flags })), textures: (a.head.textures || []).map((t) => ({ name: t.name, bytes: t.length })) };
}

export const assets = { maps: attachAssetMaps, register: registerAsset, get: getAsset, add: addAsset, cloth: assetCloth, textures: assetTextures, ready: assetTexturesReady, stats: assetStats, list: listAssets };
