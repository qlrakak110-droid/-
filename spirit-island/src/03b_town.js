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
      for (const k of Object.keys(g.attributes)) if (k !== 'position' && k !== 'normal' && k !== 'uv') g.deleteAttribute(k);
      if (!g.attributes.uv) g.setAttribute('uv', new THREE.BufferAttribute(new Float32Array(g.attributes.position.count * 2), 2));
      g.clearGroups(); g.applyMatrix4(m4);
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
        mesh.castShadow = lit; mesh.receiveShadow = lit;
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

// ---------------- cottage
function house(scene, x, z, rot, wall, roof, s = 1, opts = {}) {
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
  // water: animated ripples + sparkles, emissive cyan
  const wmat = new THREE.ShaderMaterial({
    uniforms: { uTime: Shared.time, uCol: { value: new THREE.Color(0x5fd8ff) } },
    vertexShader: 'varying vec2 vP; void main(){ vP = position.xy; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }',
    fragmentShader: `uniform float uTime; uniform vec3 uCol; varying vec2 vP;
      void main(){ float r = length(vP); float w = sin(r * 14.0 - uTime * 3.0) * 0.5 + 0.5; float w2 = sin(r * 31.0 - uTime * 5.0 + vP.x * 3.0) * 0.5 + 0.5;
        vec3 c = uCol * (0.75 + 0.35 * w) + vec3(0.6, 0.95, 1.0) * pow(w2, 12.0) * 0.8; c += vec3(0.9, 1.0, 1.0) * smoothstep(0.85, 1.0, r) * 0.35;
        gl_FragColor = vec4(c * 1.15, 1.0); }`,
  });
  part(GEO.circle, wmat, f, [0, 0.66, 0], 2.42, [-Math.PI / 2, 0, 0]).castShadow = false;
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
