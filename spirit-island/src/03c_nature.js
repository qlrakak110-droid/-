// ============================================================================
//  nature kit shared by the island and the battle arenas: sculpted mossy rocks,
//  petal flowers, clumped grass fields, and an anti-aliased foliage alpha test.
// ============================================================================

// ---------------- rocks: noise-displaced icosphere, flat underside, moss on top
const _rockGeo = [];
function rockGeometry(i) {
  i %= 5;
  if (_rockGeo[i]) return _rockGeo[i];
  const rng = mulberry32(1000 + i * 17);
  const base = new THREE.IcosahedronGeometry(1, 8); base.deleteAttribute('normal'); base.deleteAttribute('uv');
  const geo = mergeVertices(base);
  const p = geo.attributes.position, v = new THREE.Vector3();
  const o = [rng() * 50, rng() * 50, rng() * 50], sq = [0.85 + rng() * 0.4, 0.72 + rng() * 0.32, 0.8 + rng() * 0.35];
  const cut = [];
  for (let c = 0; c < 5; c++) cut.push({ n: new THREE.Vector3(rng() - 0.5, rng() * 0.9 - 0.15, rng() - 0.5).normalize(), d: 0.5 + rng() * 0.18 });
  for (let k = 0; k < p.count; k++) {
    v.fromBufferAttribute(p, k);
    let n = vn3js(v.x * 1.4 + o[0], v.y * 1.4 + o[1], v.z * 1.4 + o[2]) * 0.5 + vn3js(v.x * 3.2 + o[1], v.y * 3.2 + o[2], v.z * 3.2 + o[0]) * 0.3 + vn3js(v.x * 7.5 + o[2], v.y * 7.5, v.z * 7.5 + o[1]) * 0.12;
    v.multiplyScalar(0.62 + n * 0.62);
    for (const c of cut) { const d = v.dot(c.n) - c.d; if (d > 0) v.addScaledVector(c.n, -d * 0.92); }   // broad split faces, like weathered stone
    // strata: faint horizontal ledges
    v.y += Math.sin(v.y * 14 + n * 3) * 0.012;
    v.x *= sq[0]; v.y *= sq[1]; v.z *= sq[2];
    if (v.y < -0.12) v.y = -0.12 + (v.y + 0.12) * 0.2;
    p.setXYZ(k, v.x, v.y, v.z);
  }
  geo.computeVertexNormals();
  const nor = geo.attributes.normal, col = new Float32Array(p.count * 3), c = new THREE.Color(), stone = new THREE.Color(), moss = new THREE.Color(0x4a7a30);
  for (let k = 0; k < p.count; k++) {
    const x = p.getX(k), y = p.getY(k), z = p.getZ(k);
    const n2 = vn3js(x * 4 + o[0], y * 4, z * 4 + o[2]);
    stone.setRGB(0.33 + n2 * 0.14, 0.32 + n2 * 0.12, 0.31 + n2 * 0.11);
    const m = smooth(0.55, 0.85, nor.getY(k) + (vn3js(x * 2.5, y * 2.5 + 9, z * 2.5) - 0.5) * 0.6);
    c.copy(stone).lerp(moss, m * 0.9);
    const cav = smooth(-0.2, 0.3, y);                                   // darker toward the ground
    c.multiplyScalar(0.55 + cav * 0.45);
    col[k * 3] = c.r; col[k * 3 + 1] = c.g; col[k * 3 + 2] = c.b;
  }
  geo.setAttribute('color', new THREE.BufferAttribute(col, 3));
  return (_rockGeo[i] = geo);
}
let _rockMat = null;
function rockMaterial() {
  return _rockMat || (_rockMat = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.92, metalness: 0, envMapIntensity: 0.32 }));
}
// rocks: [{ x, y, z, s, r }] → a few instanced meshes (one per shape)
function buildRockField(parent, rocks, tint) {
  const bins = [[], [], [], [], []];
  rocks.forEach((r, i) => bins[i % 5].push(r));
  const m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), e = new THREE.Euler(), v = new THREE.Vector3(), sc = new THREE.Vector3(), c = new THREE.Color();
  const out = [];
  bins.forEach((list, b) => {
    if (!list.length) return;
    const im = new THREE.InstancedMesh(rockGeometry(b), rockMaterial(), list.length);
    list.forEach((r, i) => {
      m4.compose(v.set(r.x, r.y, r.z), q.setFromEuler(e.set(0, r.r, 0)), sc.set(r.s, r.s * (r.sy || 1), r.s));
      im.setMatrixAt(i, m4);
      c.setHex(tint ?? 0xffffff).multiplyScalar(0.88 + ((i * 37) % 10) / 40); im.setColorAt(i, c);
    });
    im.castShadow = im.receiveShadow = true; parent.add(im); out.push(im);
  });
  return out;
}

// ---------------- flowers: five petals + a bright centre on a short stem
let _flowerGeo = null, _stemGeo = null;
function flowerGeometry() {
  if (_flowerGeo) return _flowerGeo;
  const parts = [], white = new THREE.Color(1, 1, 1), yellow = new THREE.Color(1.0, 0.82, 0.3);
  const add = (g, col, m) => { g = g.toNonIndexed(); g.deleteAttribute('uv'); g.applyMatrix4(m); const n = g.attributes.position.count, a = new Float32Array(n * 3); for (let i = 0; i < n; i++) col.toArray(a, i * 3); g.setAttribute('color', new THREE.BufferAttribute(a, 3)); parts.push(g); };
  const petal = new THREE.SphereGeometry(1, 6, 3);
  for (let i = 0; i < 5; i++) {
    const a = (i / 5) * Math.PI * 2;
    const m = new THREE.Matrix4().compose(new THREE.Vector3(Math.cos(a) * 0.055, 0.008, Math.sin(a) * 0.055), new THREE.Quaternion().setFromEuler(new THREE.Euler(0, -a, 0.35)), new THREE.Vector3(0.06, 0.012, 0.034));
    add(petal, white, m);
  }
  add(new THREE.SphereGeometry(1, 6, 4), yellow, new THREE.Matrix4().compose(new THREE.Vector3(0, 0.018, 0), new THREE.Quaternion(), new THREE.Vector3(0.026, 0.02, 0.026)));
  _flowerGeo = mergeGeometries(parts);
  _stemGeo = new THREE.CylinderGeometry(0.008, 0.012, 1, 4).translate(0, 0.5, 0);
  return _flowerGeo;
}
// flowers: [{ x, y, z, h, col }]
function buildFlowerField(parent, flowers) {
  const fg = flowerGeometry();
  const mat = new THREE.MeshLambertMaterial({ vertexColors: true, side: THREE.DoubleSide });
  mat.onBeforeCompile = (sh) => { sh.fragmentShader = sh.fragmentShader.replace('#include <emissivemap_fragment>', '#include <emissivemap_fragment>\n totalEmissiveRadiance += diffuseColor.rgb * 0.3;'); };
  const heads = new THREE.InstancedMesh(fg, mat, flowers.length), stems = new THREE.InstancedMesh(_stemGeo, M(0x3f7a34), flowers.length);
  const m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), e = new THREE.Euler(), v = new THREE.Vector3(), sc = new THREE.Vector3(), c = new THREE.Color();
  flowers.forEach((f, i) => {
    const s = f.s || 1, tilt = (((i * 53) % 17) / 17 - 0.5) * 0.5;
    q.setFromEuler(e.set(tilt, i * 2.39, tilt * 0.6));
    m4.compose(v.set(f.x, f.y + f.h, f.z), q, sc.setScalar(s)); heads.setMatrixAt(i, m4);
    m4.compose(v.set(f.x, f.y, f.z), q, sc.set(s, f.h, s)); stems.setMatrixAt(i, m4);
    heads.setColorAt(i, c.setHex(f.col));
  });
  heads.castShadow = false; stems.castShadow = false; heads.receiveShadow = stems.receiveShadow = true;
  parent.add(heads, stems);
  return [heads, stems];
}

// ---------------- clumped grass field (instanced blades, wind + optional player push)
function grassBladeGeometry() {
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.BufferAttribute(new Float32Array([-0.06, 0, 0, 0.06, 0, 0, -0.045, 0.45, 0.02, 0.045, 0.45, 0.02, 0, 1, 0.08]), 3));
  g.setIndex([0, 1, 2, 2, 1, 3, 2, 3, 4]);
  return g;
}
function grassMaterial(o = {}) {
  const U = {
    uTime: Shared.time, uPlayer: o.player || { value: new THREE.Vector3(1e5, 0, 1e5) },
    uLow: { value: new THREE.Color(o.low ?? 0x1f5a2c) }, uHigh: { value: new THREE.Color(o.high ?? 0x9ad86a) }, uTint: { value: new THREE.Color(o.tint ?? 0xffc8a0) },
    uSunDir: { value: o.sunDir || new THREE.Vector3(-0.86, 0.4, 0.3).normalize() },
  };
  const mat = new THREE.ShaderMaterial({
    uniforms: THREE.UniformsUtils.merge([THREE.UniformsLib.fog]), side: THREE.DoubleSide, fog: true,
    vertexShader: `uniform float uTime; uniform vec3 uPlayer; varying float vH; varying float vV; varying vec3 vWp; ${FOG_V}
      void main(){
        vec3 p = position; vH = p.y;
        vec4 wp = modelMatrix * instanceMatrix * vec4(p, 1.0);
        vec3 base = (modelMatrix * instanceMatrix * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
        vV = fract(sin(dot(base.xz, vec2(12.9898, 78.233))) * 43758.5453);
        float k = p.y * p.y;
        float gust = sin(uTime * 0.6 + base.x * 0.05 + base.z * 0.04) * 0.5 + 0.5;
        float sway = (sin(uTime * 1.7 + base.x * 0.32 + base.z * 0.25) * 0.16 + sin(uTime * 3.3 + base.x * 1.1) * 0.05) * (0.6 + gust * 0.8);
        wp.x += sway * k; wp.z += sway * 0.4 * k;
        vec2 d = base.xz - uPlayer.xz; float dist = length(d);
        float push = (1.0 - smoothstep(0.0, 1.5, dist)) * k;
        wp.xz += normalize(d + 1e-4) * push * 0.75; wp.y -= push * 0.35;
        vWp = wp.xyz;
        vec4 mvPosition = viewMatrix * wp; gl_Position = projectionMatrix * mvPosition;
        #include <fog_vertex>
      }`,
    fragmentShader: `uniform vec3 uLow, uHigh, uTint, uSunDir; varying float vH; varying float vV; varying vec3 vWp; ${FOG_F}
      void main(){
        vec3 c = mix(uLow, uHigh * (0.82 + vV * 0.36), smoothstep(0.0, 1.0, vH));
        c = mix(c, c * uTint * 1.12, smoothstep(0.55, 1.0, vH) * 0.55);
        vec3 V = normalize(cameraPosition - vWp);
        float back = pow(max(dot(-V, uSunDir), 0.0), 4.0) * smoothstep(0.3, 1.0, vH);   // light through the blades
        c += uTint * back * 0.35;
        gl_FragColor = vec4(c, 1.0);
        #include <fog_fragment>
      }`,
  });
  Object.assign(mat.uniforms, U);
  return mat;
}
// spots: [{ x, y, z, h }] → one instanced mesh
let _blade = null;
function buildGrassField(parent, spots, mat) {
  _blade = _blade || grassBladeGeometry();
  const im = new THREE.InstancedMesh(_blade, mat, spots.length);
  const m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), e = new THREE.Euler(), v = new THREE.Vector3(), sc = new THREE.Vector3();
  spots.forEach((s, i) => { m4.compose(v.set(s.x, s.y - 0.04, s.z), q.setFromEuler(e.set((((i * 13) % 7) / 7 - 0.5) * 0.4, i * 2.399, (((i * 29) % 5) / 5 - 0.5) * 0.4)), sc.set(1.15, s.h, 1)); im.setMatrixAt(i, m4); });
  im.frustumCulled = false; im.receiveShadow = false; parent.add(im);
  return im;
}
// scatter blades in clumps: each clump is a tight cluster of 5-11 blades
function grassClumps(rng, count, place) {
  const out = [];
  for (let c = 0; c < count; c++) {
    const at = place(); if (!at) continue;
    const n = 5 + ((rng() * 7) | 0), R = 0.12 + rng() * 0.22, H = at.h;
    for (let i = 0; i < n; i++) {
      const a = rng() * 6.283, r = Math.sqrt(rng()) * R;
      out.push({ x: at.x + Math.cos(a) * r, y: at.y, z: at.z + Math.sin(a) * r, h: H * (0.55 + rng() * 0.6) });
    }
  }
  return out;
}

// ---------------- anti-aliased alpha test for leaf cards (sharpened alpha + alpha-to-coverage under MSAA)
function aaAlphaTest(mat, texSize = 256, cutoff = 0.42) {
  mat.alphaToCoverage = true;
  const prev = mat.onBeforeCompile;
  mat.onBeforeCompile = (sh, r) => {
    if (prev) prev(sh, r);
    sh.fragmentShader = sh.fragmentShader.replace('#include <alphatest_fragment>', `
      #ifdef USE_MAP
        vec2 tsz = vMapUv * ${texSize.toFixed(1)};
        float mipL = max(0.0, 0.5 * log2(max(dot(dFdx(tsz), dFdx(tsz)), dot(dFdy(tsz), dFdy(tsz)))));
        diffuseColor.a *= 1.0 + mipL * 0.14;
      #endif
      diffuseColor.a = clamp((diffuseColor.a - ${cutoff.toFixed(3)}) / max(fwidth(diffuseColor.a), 0.0001) + 0.5, 0.0, 1.0);
      if (diffuseColor.a < 0.01) discard;`)
      // keep the sharpened alpha (OPAQUE would force 1.0) so alpha-to-coverage can feather the edge
      .replace('#include <opaque_fragment>', 'gl_FragColor = vec4( outgoingLight, diffuseColor.a );');
  };
  mat.customProgramCacheKey = () => 'aaAlpha' + texSize + '_' + cutoff + (prev ? prev.toString() : '');
  mat.needsUpdate = true;
  return mat;
}

// ---------------- soft dust puffs (normal blending, unlike the additive sparkle particles)
class Puffs {
  constructor(scene, max = 192, color = 0xd8c6aa) {
    this.max = max; this.p = [];
    this.pos = new Float32Array(max * 3); this.sa = new Float32Array(max * 2);
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(this.pos, 3).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute('sa', new THREE.BufferAttribute(this.sa, 2).setUsage(THREE.DynamicDrawUsage));
    this.g = g;
    this.mat = new THREE.ShaderMaterial({
      uniforms: { uTex: { value: TEX.cloud }, uCol: { value: new THREE.Color(color) }, uPx: { value: 1 } }, transparent: true, depthWrite: false,
      vertexShader: 'attribute vec2 sa; uniform float uPx; varying float vA; void main(){ vA = sa.y; vec4 mv = modelViewMatrix * vec4(position, 1.0); gl_PointSize = sa.x * 260.0 * uPx / -mv.z; gl_Position = projectionMatrix * mv; }',
      fragmentShader: 'uniform sampler2D uTex; uniform vec3 uCol; varying float vA; void main(){ float a = texture2D(uTex, gl_PointCoord).a * vA; if (a < 0.004) discard; gl_FragColor = vec4(uCol, a); }',
    });
    this.pts = new THREE.Points(g, this.mat); this.pts.frustumCulled = false; this.pts.renderOrder = 2; scene.add(this.pts);
  }
  emit(at, n, o = {}) {
    const sp = o.speed ?? 1.2, sz = o.size ?? 0.5, life = o.life ?? 0.9, spread = o.spread ?? 0.25;
    for (let i = 0; i < n; i++) {
      if (this.p.length >= this.max) this.p.shift();
      const a = Math.random() * Math.PI * 2, v = sp * (0.4 + Math.random() * 0.6);
      this.p.push({ x: at.x + Math.cos(a) * spread * Math.random(), y: at.y + 0.05, z: at.z + Math.sin(a) * spread * Math.random(),
        vx: Math.cos(a) * v + (o.vx || 0), vy: (o.up ?? 0.6) * (0.5 + Math.random() * 0.8), vz: Math.sin(a) * v + (o.vz || 0),
        t: 0, life: life * (0.7 + Math.random() * 0.6), s0: sz * 0.45, s1: sz * (1.2 + Math.random() * 0.6), a: o.alpha ?? 0.5 });
    }
  }
  update(dt) {
    this.mat.uniforms.uPx.value = renderer.getPixelRatio();
    let n = 0;
    for (let i = this.p.length - 1; i >= 0; i--) { const q = this.p[i]; q.t += dt; if (q.t >= q.life) this.p.splice(i, 1); }
    for (const q of this.p) {
      const k = q.t / q.life, drag = Math.exp(-3 * dt);
      q.vx *= drag; q.vz *= drag; q.vy = q.vy * drag + 0.25 * dt;
      q.x += q.vx * dt; q.y += q.vy * dt; q.z += q.vz * dt;
      this.pos[n * 3] = q.x; this.pos[n * 3 + 1] = q.y; this.pos[n * 3 + 2] = q.z;
      this.sa[n * 2] = q.s0 + (q.s1 - q.s0) * Math.sqrt(k); this.sa[n * 2 + 1] = q.a * Math.min(1, k * 6) * (1 - k) * (1 - k);
      n++;
    }
    this.g.setDrawRange(0, n);
    this.g.attributes.position.needsUpdate = true; this.g.attributes.sa.needsUpdate = true;
  }
}

// ---------------- hooks called from 03_world.js (buildWorld / updateWorld)
function buildNatureExtras(scene) {}
function updateNatureExtras(dt) {}

// ============================================================================
//  vegetation builders (moved from 03_world.js): forests, lawn & encounter grass, rocks & flowers
// ============================================================================
// ---------------- foliage: leaf-card trees, fern pines and bushes (instanced, wind, translucency)
function leafTexture(kind) {
  const c = document.createElement('canvas'); c.width = c.height = 256; const g = c.getContext('2d');
  const rng = mulberry32(kind === 'pine' ? 77 : 33);
  if (kind === 'pine') {
    g.lineCap = 'round';
    for (let k = 0; k < 3; k++) {
      const cx = 64 + k * 64, wAt = (y) => { const t = (y - 8) / 240; return 3 + 21 * Math.sin(Math.PI * Math.min(1, t * 1.12)); };
      // a solid tapered core keeps the frond's body when the card shrinks into the distance
      g.fillStyle = 'rgb(150,150,150)'; g.beginPath(); g.moveTo(cx, 8);
      for (let y = 8; y <= 248; y += 8) g.lineTo(cx + wAt(y), y + 4);
      for (let y = 248; y >= 8; y -= 8) g.lineTo(cx - wAt(y), y + 4);
      g.closePath(); g.fill();
      for (let y = 12; y < 246; y += 3.5) {
        const t = (y - 10) / 236, L = 8 + 26 * Math.sin(Math.PI * Math.min(1, t * 1.15));
        for (const sd of [-1, 1]) {
          const v = 165 + (rng() * 90 | 0);
          g.strokeStyle = `rgb(${v},${v},${v})`; g.lineWidth = 3.4;
          g.beginPath(); g.moveTo(cx + sd * 2, y); g.lineTo(cx + sd * L, y + L * 0.5); g.stroke();
        }
      }
      g.strokeStyle = 'rgb(115,115,115)'; g.lineWidth = 4; g.beginPath(); g.moveTo(cx, 8); g.lineTo(cx, 248); g.stroke();
    }
  } else {
    for (let i = 0; i < 70; i++) {
      const a0 = rng() * Math.PI * 2, rr = Math.sqrt(rng()) * 96, x = 128 + Math.cos(a0) * rr, y = 128 + Math.sin(a0) * rr;
      const a = rng() * Math.PI * 2, L = 30 + rng() * 24, W = L * 0.44;
      const v = 140 + (rng() * 115 | 0);
      g.save(); g.translate(x, y); g.rotate(a);
      const grd = g.createLinearGradient(-W, 0, W, 0);
      grd.addColorStop(0, `rgb(${v * 0.62 | 0},${v * 0.62 | 0},${v * 0.62 | 0})`); grd.addColorStop(0.55, `rgb(${v},${v},${v})`); grd.addColorStop(1, `rgb(${v * 0.78 | 0},${v * 0.78 | 0},${v * 0.78 | 0})`);
      g.fillStyle = grd; g.beginPath(); g.moveTo(0, -L / 2); g.quadraticCurveTo(W, -L * 0.08, 0, L / 2); g.quadraticCurveTo(-W, -L * 0.08, 0, -L / 2); g.fill();
      g.strokeStyle = 'rgba(0,0,0,0.28)'; g.lineWidth = 1.3; g.beginPath(); g.moveTo(0, -L / 2); g.lineTo(0, L / 2); g.stroke();
      g.restore();
    }
  }
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 4; return t;
}

function foliageMaterial(tex) {
  const m = new THREE.MeshLambertMaterial({ map: tex, alphaTest: 0.42, side: THREE.DoubleSide });
  foliagePatch(m);
  return aaAlphaTest(m, 256, 0.42);
}

function foliagePatch(m) {
  m.onBeforeCompile = (sh) => {
    sh.uniforms.uTime = Shared.time;
    sh.vertexShader = 'uniform float uTime; attribute vec3 aCenter;\n' + sh.vertexShader
      .replace('#include <defaultnormal_vertex>', `vec3 cardW = (instanceMatrix * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
        vec3 transformedNormal = normalMatrix * normalize(cardW - aCenter + vec3(0.0, 0.25, 0.0));`)
      .replace('#include <begin_vertex>', `#include <begin_vertex>
        float wph = uTime * 1.5 + cardW.x * 0.31 + cardW.z * 0.23;
        transformed.x += sin(wph) * 0.06 + sin(wph * 2.3) * 0.02; transformed.y += cos(wph * 1.3) * 0.035;`);
    sh.fragmentShader = sh.fragmentShader
      .replace('#include <normal_fragment_begin>', 'vec3 normal = normalize( vNormal ); vec3 nonPerturbedNormal = normal;')
      .replace('#include <emissivemap_fragment>', `#include <emissivemap_fragment>
        #if NUM_DIR_LIGHTS > 0
          totalEmissiveRadiance += diffuseColor.rgb * directionalLights[0].color * 0.16 * max(dot(-normal, directionalLights[0].direction), 0.0);
        #endif
        totalEmissiveRadiance += diffuseColor.rgb * 0.08;`);
  };
  return m;
}
// trees: [{ x, y, z, s, r, kind: 'round' | 'pine' | 'bush', tint }]

function buildForest(parent, trees, opts = {}) {
  const g = new THREE.Group(); parent.add(g);
  const rng = mulberry32(opts.seed || 7);
  const leafTex = leafTexture('leaf'), pineTex = leafTexture('pine');
  const cards = [], needles = [], trunks = [];
  const greens = opts.greens || [0x4f9a3e, 0x5aa648, 0x3f8a3a, 0x6aaa4a, 0x5c9e42];
  for (const t of trees) {
    const s = t.s;
    if (t.kind === 'pine') {
      trunks.push({ x: t.x, y: t.y, z: t.z, s, r: t.r, pine: true });
      const tiers = 5;
      for (let k = 0; k < tiers; k++) {
        const h = (1.4 + k * 0.85) * s, R = (1.9 - k * 0.33) * s, n = 9 - k;
        for (let i = 0; i < n; i++) {
          const a = (i / n) * Math.PI * 2 + rng() * 0.4 + k;
          needles.push({ p: [t.x + Math.cos(a) * R * 0.45, t.y + h, t.z + Math.sin(a) * R * 0.45], yaw: -a + Math.PI / 2, tilt: 0.95, size: [R * 1.05, R * 1.25], c: [t.x, t.y + h - 0.6 * s, t.z], col: t.tint ?? [0x2f6b4a, 0x3a7a55, 0x2a5f44][(i + k) % 3] });
        }
      }
      needles.push({ p: [t.x, t.y + (1.4 + tiers * 0.85) * s, t.z], yaw: 0, tilt: 0, size: [0.7 * s, 1.2 * s], c: [t.x, t.y + 4 * s, t.z], col: t.tint ?? 0x3a7a55 });
    } else {
      const bush = t.kind === 'bush';
      if (!bush) trunks.push({ x: t.x, y: t.y, z: t.z, s, r: t.r });
      const top = bush ? 0.55 * s : 2.85 * s;
      const clumps = bush ? [[0, top, 0, 0.75]] : [[0, top + 0.35 * s, 0, 1.25], [0.85, top - 0.15 * s, 0.35, 0.95], [-0.75, top - 0.05 * s, -0.4, 0.95], [0.2, top + 0.2 * s, -0.85, 0.9], [-0.35, top - 0.3 * s, 0.75, 0.85]];
      const base = t.tint ?? greens[(rng() * greens.length) | 0];
      for (const [ox, oy, oz, cr] of clumps) {
        const C = [t.x + ox * s, t.y + oy, t.z + oz * s], R = cr * s * (bush ? 1 : 1.05);
        const n = bush ? 14 : 20;
        for (let i = 0; i < n; i++) {
          const th = rng() * Math.PI * 2, ph = Math.acos(rand(-0.55, 1)), rr = R * (0.45 + 0.55 * Math.cbrt(rng()));
          cards.push({ p: [C[0] + Math.sin(ph) * Math.cos(th) * rr, C[1] + Math.cos(ph) * rr * 0.85, C[2] + Math.sin(ph) * Math.sin(th) * rr], yaw: rng() * 6.28, tilt: rand(-1.2, 1.2), roll: rng() * 6.28, size: [1.15 * s * (0.8 + rng() * 0.5), 1.15 * s * (0.8 + rng() * 0.5)], c: C, col: base, jitter: rng() });
        }
      }
    }
  }
  const m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), e = new THREE.Euler(), v = new THREE.Vector3(), sc = new THREE.Vector3(), col = new THREE.Color();
  const makeCards = (list, tex, flat) => {
    if (!list.length) return null;
    const geo = new THREE.PlaneGeometry(1, 1);
    if (flat) geo.translate(0, -0.5, 0);
    const im = new THREE.InstancedMesh(geo, foliageMaterial(tex), list.length);
    const cen = new Float32Array(list.length * 3);
    list.forEach((c, i) => {
      e.set(c.tilt, c.yaw, c.roll || 0, flat ? 'YXZ' : 'XYZ');
      m4.compose(v.set(...c.p), q.setFromEuler(e), sc.set(c.size[0], c.size[1], 1));
      im.setMatrixAt(i, m4);
      col.setHex(c.col); const j = (c.jitter ?? 0.5) - 0.5; col.offsetHSL(j * 0.03, j * 0.12, j * 0.12); im.setColorAt(i, col);
      cen[i * 3] = c.c[0]; cen[i * 3 + 1] = c.c[1]; cen[i * 3 + 2] = c.c[2];
    });
    geo.setAttribute('aCenter', new THREE.InstancedBufferAttribute(cen, 3));
    im.instanceMatrix.needsUpdate = true; if (im.instanceColor) im.instanceColor.needsUpdate = true;
    im.castShadow = true; im.receiveShadow = true;
    im.customDepthMaterial = new THREE.MeshDepthMaterial({ depthPacking: THREE.RGBADepthPacking, map: tex, alphaTest: 0.42 });
    im.frustumCulled = false; g.add(im); return im;
  };
  makeCards(cards, leafTex, false);
  makeCards(needles, pineTex, true);
  if (trunks.length) {
    const tg = new THREE.CylinderGeometry(0.15, 0.3, 2.6, 8).translate(0, 1.3, 0);
    const b1 = new THREE.CylinderGeometry(0.05, 0.11, 1.2, 6).translate(0, 0.6, 0).rotateZ(0.9).translate(0.1, 1.75, 0);
    const b2 = new THREE.CylinderGeometry(0.05, 0.1, 1.0, 6).translate(0, 0.5, 0).rotateZ(-0.8).rotateY(2.1).translate(-0.05, 2.0, 0);
    const trunkGeo = mergeGeometries([tg.toNonIndexed(), b1.toNonIndexed(), b2.toNonIndexed()], false);
    const tm = new THREE.InstancedMesh(trunkGeo, M(0x5e4130), trunks.length);
    trunks.forEach((t, i) => { m4.compose(v.set(t.x, t.y - 0.1, t.z), q.setFromEuler(e.set(0, t.r, 0, 'XYZ')), sc.set(t.s, t.s * (t.pine ? 1.6 : 1), t.s)); tm.setMatrixAt(i, m4); });
    tm.castShadow = true; tm.receiveShadow = true; g.add(tm);
  }
  return g;
}

function buildTrees(scene) {
  const rng = mulberry32(1337);
  const list = [];
  const ok = (x, z, minGap) => {
    const h = groundY(x, z); if (h < 1.3 || h > 13) return false;
    if (pathDist(x, z) < 4.5) return false;
    for (const zz of ZONES) if (Math.hypot(x - zz.x, z - zz.z) < zz.r + 2.5) return false;
    if (Math.hypot(x - SITES.town.x, z - SITES.town.z) < 22) return false;
    if (Math.hypot(x - SITES.altar.x, z - SITES.altar.z) < 15) return false;
    for (const r of SITES.rifts) if (Math.hypot(x - r.x, z - r.z) < 12) return false;
    for (const t of list) if (Math.hypot(x - t.x, z - t.z) < minGap) return false;
    return true;
  };
  for (let k = 0; k < 2600 && list.length < 230; k++) {
    const x = (rng() - 0.5) * 190, z = (rng() - 0.5) * 190;
    if (!ok(x, z, 3.6)) continue;
    const s = 0.8 + rng() * 0.7;
    const isPine = z < -18 ? rng() < 0.75 : rng() < 0.18;
    let tint;
    if (!isPine && z > 20 && rng() < 0.32) tint = [0xf2a6c8, 0xf7bfd8, 0xffcadb][(rng() * 3) | 0];
    else if (!isPine && rng() < 0.07) tint = [0xd98a3a, 0xe0a040, 0xc8742e][(rng() * 3) | 0];
    list.push({ x, y: groundY(x, z), z, s, r: rng() * 6.28, kind: isPine ? 'pine' : 'round', tint });
    World.colliders.push({ x, z, r: 0.7 * s });
  }
  for (let k = 0; k < 1800 && list.filter((t) => t.kind === 'bush').length < 140; k++) {
    const x = (rng() - 0.5) * 180, z = (rng() - 0.5) * 180;
    if (!ok(x, z, 2.2)) continue;
    list.push({ x, y: groundY(x, z), z, s: 0.7 + rng() * 0.6, r: 0, kind: 'bush', tint: rng() < 0.15 ? 0x7aa84a : undefined });
  }
  buildForest(scene, list, { seed: 99 });
}


function buildRocksAndFlowers(scene) {
  const rng = mulberry32(99);
  const rocks = [];
  for (let k = 0; k < 900 && rocks.length < 70; k++) {
    const x = (rng() - 0.5) * 200, z = (rng() - 0.5) * 200, h = groundY(x, z);
    if (h < 0.4 || pathDist(x, z) < 3.5 || Math.hypot(x - SITES.town.x, z - SITES.town.z) < 16) continue;
    let bad = false; for (const zz of ZONES) if (Math.hypot(x - zz.x, z - zz.z) < zz.r) bad = true; if (bad) continue;
    const s = 0.35 + Math.pow(rng(), 2) * 1.8;
    rocks.push({ x, z, s, h, r: rng() * 6 });
    if (s > 0.9) World.colliders.push({ x, z, r: s * 0.8 });
  }
  buildRockField(scene, rocks.map((r) => ({ x: r.x, y: r.h - 0.06 * r.s, z: r.z, s: r.s, r: r.r, sy: 0.85 + (r.r % 1) * 0.3 })));
  // flowers: small petal flowers in loose drifts, bright enough to catch the dusk light
  const fl = [], fc = [0xffc6e0, 0xfff1a8, 0xd9c8ff, 0xffffff, 0xa8e6ff, 0xff9aa8];
  for (let k = 0; k < 4000 && fl.length < (isTouch ? 600 : 1500); k++) {
    const x = (rng() - 0.5) * 180, z = (rng() - 0.5) * 180, h = groundY(x, z);
    if (h < 1.1 || h > 9 || pathDist(x, z) < 2.4 || Math.hypot(x - SITES.town.x, z - SITES.town.z) < 10.5) continue;
    const col = fc[(rng() * fc.length) | 0], n = 1 + ((rng() * 4) | 0);
    for (let j = 0; j < n; j++) { const fx = x + (rng() - 0.5) * 1.2, fz = z + (rng() - 0.5) * 1.2; fl.push({ x: fx, y: groundY(fx, fz), z: fz, h: 0.18 + rng() * 0.18, s: 1.1 + rng() * 0.6, col }); }
  }
  buildFlowerField(scene, fl);
}


// ---------------- tall grass meadows: instanced blades with wind + player push
function buildGrass(scene, zones) {
  const blade = new THREE.BufferGeometry();
  blade.setAttribute('position', new THREE.BufferAttribute(new Float32Array([-0.07, 0, 0, 0.07, 0, 0, -0.05, 0.5, 0, 0.05, 0.5, 0, 0, 1, 0]), 3));
  blade.setIndex([0, 1, 2, 2, 1, 3, 2, 3, 4]);
  const U = { uTime: Shared.time, uPlayer: { value: new THREE.Vector3() }, uLow: { value: new THREE.Color(0x1f5a2c) }, uHigh: { value: new THREE.Color(0x9ad86a) }, uTint: { value: new THREE.Color(0xffc8a0) } };
  const mat = new THREE.ShaderMaterial({
    uniforms: THREE.UniformsUtils.merge([THREE.UniformsLib.fog]), side: THREE.DoubleSide, fog: true,
    vertexShader: `uniform float uTime; uniform vec3 uPlayer; varying float vH; varying float vV; ${FOG_V}
      void main(){
        vec3 p = position; vH = p.y;
        vec4 wp = modelMatrix * instanceMatrix * vec4(p, 1.0);
        vec3 base = (modelMatrix * instanceMatrix * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
        vV = fract(sin(dot(base.xz, vec2(12.9898, 78.233))) * 43758.5453);
        float k = p.y * p.y;
        float sway = sin(uTime * 1.7 + base.x * 0.32 + base.z * 0.25) * 0.22 + sin(uTime * 3.3 + base.x * 1.1) * 0.06;
        wp.x += sway * k; wp.z += sway * 0.4 * k;
        vec2 d = base.xz - uPlayer.xz; float dist = length(d);
        float push = (1.0 - smoothstep(0.0, 1.5, dist)) * k;
        wp.xz += normalize(d + 1e-4) * push * 0.75; wp.y -= push * 0.35;
        vec4 mvPosition = viewMatrix * wp; gl_Position = projectionMatrix * mvPosition;
        #include <fog_vertex>
      }`,
    fragmentShader: `uniform vec3 uLow, uHigh, uTint; varying float vH; varying float vV; ${FOG_F}
      void main(){ vec3 c = mix(uLow, uHigh * (0.8 + vV * 0.4), smoothstep(0.0, 1.0, vH)); c = mix(c, c * uTint * 1.15, smoothstep(0.6, 1.0, vH) * 0.5);
        gl_FragColor = vec4(c, 1.0);
        #include <fog_fragment>
      }`,
  });
  Object.assign(mat.uniforms, U);
  const dens = Settings.high ? 9 : 4.5;
  const list = [];
  for (const z of zones) {
    // encounter grass grows in bunches; shorter toward the rim so the patch reads as a soft-edged meadow
    const n = Math.floor((Math.PI * z.r * z.r * dens) / 8);
    const pts = grassClumps(Math.random, n, () => {
      const a = Math.random() * Math.PI * 2, rr = Math.sqrt(Math.random()) * z.r;
      const edge = 1 - smooth(z.r * 0.7, z.r, rr);
      return { x: z.x + Math.cos(a) * rr, y: 0, z: z.z + Math.sin(a) * rr, h: (1.0 + Math.random() * 0.6) * (0.4 + edge * 0.6) };
    });
    for (const q of pts) list.push([q.x, q.z, q.h]);
  }
  const im = new THREE.InstancedMesh(blade, mat, list.length);
  const m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), e = new THREE.Euler(), v = new THREE.Vector3(), sc = new THREE.Vector3();
  list.forEach(([x, z, h], i) => { m4.compose(v.set(x, groundY(x, z) - 0.05, z), q.setFromEuler(e.set(rand(-0.15, 0.15), rand(0, 6.28), rand(-0.15, 0.15))), sc.set(1.1, h, 1)); im.setMatrixAt(i, m4); });
  im.frustumCulled = false; im.receiveShadow = false;
  scene.add(im);
  if (Settings.high) {
    // lawn: tufts of blades scattered over the open meadows (not on paths, plazas or encounter grass)
    const rng = mulberry32(4242);
    const ok = (x, z, h) => {
      if (h < 1.05 || h > 9.5 || pathDist(x, z) < 2.4) return false;
      if (Math.hypot(x - SITES.town.x, z - SITES.town.z) < 10.5 || Math.hypot(x - SITES.altar.x, z - SITES.altar.z) < 10.5) return false;
      for (const zz of zones) if (Math.hypot(x - zz.x, z - zz.z) < zz.r) return false;
      for (const r of SITES.rifts) if (Math.hypot(x - r.x, z - r.z) < 15) return false;
      return true;
    };
    const spots = grassClumps(rng, isTouch ? 2200 : 6500, () => {
      for (let t = 0; t < 12; t++) { const x = (rng() - 0.5) * 176, z = (rng() - 0.5) * 176, h = groundY(x, z); if (ok(x, z, h)) return { x, y: h, z, h: 0.3 + rng() * 0.32 }; }
      return null;
    }).filter((p) => ok(p.x, p.z, groundY(p.x, p.z)));
    spots.forEach((p) => { p.y = groundY(p.x, p.z); });
    buildGrassField(scene, spots, mat);
  }
  return { mesh: im, U: mat.uniforms };
}

