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
