// ============================================================================
//  world: the island of the boundary — terrain, sea, cracked sky, meadows, rifts, altar
// ============================================================================
const GLSL_NOISE = `
  float hash12(vec2 p){ vec3 p3 = fract(vec3(p.xyx) * .1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
  float vnoise(vec2 p){ vec2 i = floor(p), f = fract(p); vec2 u = f*f*(3.0-2.0*f);
    return mix(mix(hash12(i), hash12(i+vec2(1,0)), u.x), mix(hash12(i+vec2(0,1)), hash12(i+vec2(1,1)), u.x), u.y); }
`;

// ---------------------------------------------------------------- authored ground / water textures (tools/tex/terrain_*.py)
const GROUND_LAYERS = ['grass', 'dirt', 'rock', 'sand', 'forest'];
registerAssets({ textures: Object.assign({ water_normal: { file: 'tex/terrain/water_normal.png' } },
  ...GROUND_LAYERS.flatMap((L) => ['albedo', 'normal', 'orm'].map((s) => ({
    [`ground_${L}_${s}`]: { file: `tex/terrain/ground_${L}_${s}.jpg`, lo: `tex/terrain/ground_${L}_${s}_512.jpg`, srgb: s === 'albedo' } })))) });

// ---------------------------------------------------------------- aerial perspective for every material
// Three's fog chunks are extended once: looking toward the sun the haze takes the sun's in-scattered colour, and an
// exponential height fog (integrated along the view ray) thickens the air near sea level. The extra uniforms hold
// shared plain objects (UniformsUtils.clone keeps those by reference) so all programs see live values; they are
// switched on only while the island scene renders (World.scene.onBeforeRender), so other scenes keep classic fog.
const FogAtmo = { dir: { x: -0.86, y: 0.4, z: 0.3, w: 0 }, sun: { r: 1, g: 0.72, b: 0.5 }, height: { x: 0, y: 0, z: 0.16, w: 0 } };
(function patchFogChunks() {
  const C = THREE.ShaderChunk;
  if (C.fog_fragment.includes('fogSunDir')) return;
  C.fog_pars_vertex = C.fog_pars_vertex.replace('varying float vFogDepth;', 'varying float vFogDepth;\n\tvarying vec3 vFogWP;');
  C.fog_vertex = C.fog_vertex.replace('vFogDepth = - mvPosition.z;',
    'vFogDepth = - mvPosition.z;\n\tvFogWP = vec3( dot( viewMatrix[ 0 ].xyz, mvPosition.xyz ), dot( viewMatrix[ 1 ].xyz, mvPosition.xyz ), dot( viewMatrix[ 2 ].xyz, mvPosition.xyz ) );');
  C.fog_pars_fragment = C.fog_pars_fragment.replace('varying float vFogDepth;',
    'varying float vFogDepth;\n\tvarying vec3 vFogWP;\n\tuniform vec4 fogSunDir;\n\tuniform vec3 fogSunCol;\n\tuniform vec4 fogHeight;');
  C.fog_fragment = C.fog_fragment.replace('gl_FragColor.rgb = mix( gl_FragColor.rgb, fogColor, fogFactor );', `vec3 fogC = fogColor;
	if ( fogSunDir.w > 0.0 ) {
		float fogL = length( vFogWP );
		vec3 fogV = vFogWP / max( fogL, 1e-3 );
		float fogRy = clamp( fogHeight.z * fogV.y * fogL, -20.0, 60.0 );
		float fogI = fogHeight.x * exp( - fogHeight.z * ( cameraPosition.y - fogHeight.y ) ) * fogL * ( abs( fogRy ) > 1e-4 ? ( 1.0 - exp( - fogRy ) ) / fogRy : 1.0 );
		fogFactor = 1.0 - ( 1.0 - fogFactor ) * exp( - min( fogI, fogHeight.w ) );
		float fogS = max( dot( fogV, fogSunDir.xyz ), 0.0 );
		fogC = mix( fogColor, fogSunCol, clamp( ( pow( fogS, 6.0 ) * 0.7 + pow( fogS, 40.0 ) * 0.45 ) * fogSunDir.w, 0.0, 1.0 ) );
	}
	gl_FragColor.rgb = mix( gl_FragColor.rgb, fogC, fogFactor );`);
  const mk = () => ({ fogSunDir: { value: FogAtmo.dir }, fogSunCol: { value: FogAtmo.sun }, fogHeight: { value: FogAtmo.height } });
  Object.assign(THREE.UniformsLib.fog, mk());
  for (const k in THREE.ShaderLib) { const u = THREE.ShaderLib[k].uniforms; if (u && u.fogColor) Object.assign(u, mk()); }
})();

// ---------------------------------------------------------------- ground: splat map + height-blended PBR terrain
// The splat map covers the terrain square (world XZ) with two RGBA8 textures (0.59 m/texel on PC, 1.2 m on phones):
//   S0: r dirt (paths, trodden ground) · g forest litter · b rock/stone (flat) · a lush meadow
//   S1: r contact darkening (AO) · g marsh mud · b dry grass · a sand
// Slope rock, beach sand, the wet swash band and void-rift corruption are resolved per pixel in the shader.
const Ground = { res: 0, d0: null, d1: null, t0: null, t1: null, pending: [], arrays: null, U: null, riftT: [1, 1, 1] };
const GROUND_CH = { dirt: [0, 0], forest: [0, 1], rock: [0, 2], stone: [0, 2], lush: [0, 3], dark: [1, 0], marsh: [1, 1], mud: [1, 1], dry: [1, 2], sand: [1, 3] };

// Grounding helper (any file may call it, any time; calls before the terrain exists are queued):
//   groundStamp(x, z, r, { dark: 0.6, dirt: 0.5 }, { rz, rot, soft, noise })
// pulls each named splat channel toward its value (0..1) with a soft, noise-ragged falloff: full at the centre,
// nothing at radius r. Channels: dark (contact shadow / AO under props, walls, trunks), dirt (bare trodden soil),
// forest (leaf & needle litter), rock|stone, sand, lush (deep meadow green), marsh|mud (wet earth), dry (straw grass).
// A value of 0 clears a channel ({ dirt: 0 } re-grasses). rz + rot make it an ellipse (rot in radians around Y);
// soft (0.05..1, default 0.5) is the fraction of the radius used by the falloff; noise (default 0.35) roughens the edge.
function groundStamp(x, z, r, ch, o = {}) {
  if (!Ground.d0) { Ground.pending.push([x, z, r, ch, o]); return; }
  const R = Ground.res, S = World.SIZE, c = S / R;
  const rz = o.rz || r, rot = o.rot || 0, soft = clamp(o.soft ?? 0.5, 0.05, 1), nz = o.noise ?? 0.35;
  const ca = Math.cos(rot), sa = Math.sin(rot), rm = Math.max(r, rz) * (1 + nz * 0.5);
  const j0 = Math.max(0, Math.floor((x - rm + S / 2) / c)), j1 = Math.min(R - 1, Math.ceil((x + rm + S / 2) / c));
  const i0 = Math.max(0, Math.floor((z - rm + S / 2) / c)), i1 = Math.min(R - 1, Math.ceil((z + rm + S / 2) / c));
  const keys = Object.keys(ch).filter((k) => GROUND_CH[k]);
  for (let i = i0; i <= i1; i++) for (let j = j0; j <= j1; j++) {
    const px = -S / 2 + (j + 0.5) * c - x, pz = -S / 2 + (i + 0.5) * c - z;
    const u = (px * ca - pz * sa) / r, v = (px * sa + pz * ca) / rz;
    const d = Math.hypot(u, v) + (vnoise((x + px) * 0.9 + 17.3, (z + pz) * 0.9 - 4.1) - 0.5) * nz;
    const f = 1 - smooth(1 - soft, 1, d);
    if (f <= 0) continue;
    const k4 = (i * R + j) * 4;
    for (const k of keys) {
      const [t, cc] = GROUND_CH[k], D = t ? Ground.d1 : Ground.d0, idx = k4 + cc;
      D[idx] = Math.round(D[idx] + (clamp(ch[k], 0, 1) * 255 - D[idx]) * f);
    }
  }
  Ground.t0.needsUpdate = Ground.t1.needsUpdate = true;
}
// What the ground is made of at a point (0..1 per channel, plus slope rock and beach sand) — e.g. to keep grass
// cards off paths and rock, or to pick footstep sounds.
function groundAt(x, z) {
  const o = { dirt: 0, forest: 0, rock: 0, lush: 0, dark: 0, marsh: 0, dry: 0, sand: 0 };
  if (Ground.d0) {
    const R = Ground.res, S = World.SIZE, j = clamp(Math.floor((x + S / 2) / S * R), 0, R - 1), i = clamp(Math.floor((z + S / 2) / S * R), 0, R - 1), k = (i * R + j) * 4;
    for (const n in o) { const [t, c] = GROUND_CH[n]; o[n] = (t ? Ground.d1 : Ground.d0)[k + c] / 255; }
  }
  const y = groundY(x, z), e = 0.6, gx = (groundY(x + e, z) - groundY(x - e, z)) / (2 * e), gz = (groundY(x, z + e) - groundY(x, z - e)) / (2 * e);
  const ny = 1 / Math.sqrt(1 + gx * gx + gz * gz);
  o.rock = Math.max(o.rock, smooth(0.85, 0.7, ny));
  o.sand = Math.max(o.sand, 1 - smooth(0.5, 1.05, y));
  return o;
}

function buildSplat() {
  const R = Ground.res = Settings.high ? 512 : 256, S = World.SIZE, c = S / R;
  const d0 = Ground.d0 = new Uint8Array(R * R * 4), d1 = Ground.d1 = new Uint8Array(R * R * 4);
  const T = SITES.town, A = SITES.altar, B8 = (v) => Math.round(clamp(v, 0, 1) * 255);
  const east = ZONES[2], west = ZONES[3];
  for (let i = 0; i < R; i++) {
    const z = -S / 2 + (i + 0.5) * c;
    for (let j = 0; j < R; j++) {
      const x = -S / 2 + (j + 0.5) * c, k = (i * R + j) * 4;
      if (Math.hypot(x, z) > 114) continue;                               // open sea: nothing to paint
      const n = fbm(x * 0.09 + 3.3, z * 0.09 + 8.1, 3), n2 = vnoise(x * 0.45 + 1.7, z * 0.45 - 3.1), n3 = vnoise(x * 0.033 - 5.1, z * 0.033 + 2.2);
      // paths: the width wanders and the verge is ragged at two scales, with worn patches spilling into the grass
      const pd = pathDist(x, z) + (n - 0.5) * 1.4 + (n2 - 0.5) * 0.7;
      let dirt = 1 - smooth(1.3, 3.0, pd);
      dirt = Math.max(dirt, (1 - smooth(2.0, 5.2, pd)) * 0.4 * smooth(0.4, 0.75, n));
      // village: packed earth around the plaza, patchy wear across the village green
      const dt = Math.hypot(x - T.x, z - T.z) + (n2 - 0.5) * 1.5;
      dirt = Math.max(dirt, 1 - smooth(10.2, 12.8, dt), (1 - smooth(13, 25, dt)) * 0.4 * smooth(0.5, 0.78, n));
      // altar: weathered stone apron around the platform, trodden earth beyond
      const da = Math.hypot(x - A.x, z - A.z) + (n2 - 0.5) * 1.2;
      let rock = 1 - smooth(9.0, 10.9, da);
      dirt = Math.max(dirt, (1 - smooth(10.5, 13.5, da)) * 0.55);
      // rifts: torn rock at the tear, scoured earth around it
      for (const r of SITES.rifts) {
        const dr = Math.hypot(x - r.x, z - r.z) + (n2 - 0.5) * 1.6;
        rock = Math.max(rock, (1 - smooth(2.2, 4.6, dr)) * 0.85);
        dirt = Math.max(dirt, 1 - smooth(4.0, 8.0, dr));
      }
      // north woods: leaf & needle litter in drifts (trees add their own via groundStamp)
      const forest = smooth(-20, -38, z) * smooth(0.35, 0.62, n * 0.7 + n3 * 0.3) * 0.9;
      let lush = 0;
      for (const zz of ZONES) { const d = Math.hypot(x - zz.x, z - zz.z); if (d < zz.r + 3) lush = Math.max(lush, 1 - smooth(zz.r - 1.5, zz.r + 2.5, d + (n2 - 0.5) * 2)); }
      const marsh = (1 - smooth(5, 13, Math.hypot(x - west.x, z - west.z) + (n - 0.5) * 6)) * smooth(0.25, 0.55, n2 * 0.5 + n * 0.5);
      const dry = (1 - smooth(6, 17, Math.hypot(x - east.x, z - east.z) + (n - 0.5) * 5)) * 0.85 + smooth(0.62, 0.8, n3) * 0.35;
      d0[k] = B8(dirt); d0[k + 1] = B8(forest); d0[k + 2] = B8(rock); d0[k + 3] = B8(lush);
      d1[k] = 0; d1[k + 1] = B8(marsh); d1[k + 2] = B8(dry); d1[k + 3] = 0;
    }
  }
  const mk = (d) => { const t = new THREE.DataTexture(d, R, R, THREE.RGBAFormat); t.magFilter = THREE.LinearFilter; t.minFilter = THREE.LinearMipmapLinearFilter; t.generateMipmaps = true; t.needsUpdate = true; return t; };
  Ground.t0 = mk(d0); Ground.t1 = mk(d1);
  const q = Ground.pending.splice(0); for (const a of q) groundStamp(...a);
}

// pack the five authored PBR sets into two texture arrays: A = albedo.rgb + height, N = normal.xy + AO + roughness
// (two samplers instead of fifteen; WebGL2 only — otherwise the vertex-colour terrain is used)
function buildGroundArrays() {
  if (!renderer.capabilities.isWebGL2) return null;
  const sets = GROUND_LAYERS.map((L) => pbrSet('ground_' + L));
  if (sets.some((s) => !s || !s.normal || !s.orm || !s.albedo.image || !s.normal.image || !s.orm.image)) return null;
  try {
    const size = Math.min(...sets.map((s) => s.albedo.image.width)), L = sets.length, px = size * size;
    const cv = document.createElement('canvas'); cv.width = cv.height = size;
    const ctx = cv.getContext('2d', { willReadFrequently: true });
    const read = (t) => { ctx.clearRect(0, 0, size, size); ctx.drawImage(t.image, 0, 0, size, size); return ctx.getImageData(0, 0, size, size).data; };
    const A = new Uint8Array(px * 4 * L), Nn = new Uint8Array(px * 4 * L), mean = [];
    for (let l = 0; l < L; l++) {
      const a = read(sets[l].albedo), nm = read(sets[l].normal), o = read(sets[l].orm);
      let r = 0, g = 0, b = 0;
      for (let y = 0; y < size; y++) {
        const src = (size - 1 - y) * size * 4, dst = l * px * 4 + y * size * 4;   // flip rows: v grows like an image texture's
        for (let x = 0; x < size * 4; x += 4) {
          const s = src + x, d = dst + x;
          A[d] = a[s]; A[d + 1] = a[s + 1]; A[d + 2] = a[s + 2]; A[d + 3] = o[s + 2];
          Nn[d] = nm[s]; Nn[d + 1] = nm[s + 1]; Nn[d + 2] = o[s]; Nn[d + 3] = o[s + 1];
          r += a[s]; g += a[s + 1]; b += a[s + 2];
        }
      }
      mean.push(new THREE.Vector3(r / px / 255, g / px / 255, b / px / 255));
    }
    const mk = (data) => {
      const t = new THREE.DataArrayTexture(data, size, size, L);
      t.format = THREE.RGBAFormat; t.type = THREE.UnsignedByteType; t.wrapS = t.wrapT = THREE.RepeatWrapping;
      t.magFilter = THREE.LinearFilter; t.minFilter = THREE.LinearMipmapLinearFilter; t.generateMipmaps = true;
      t.anisotropy = Settings.high ? 8 : 2; t.needsUpdate = true; return t;
    };
    return { A: mk(A), N: mk(Nn), mean, size };
  } catch (e) { console.warn('ground arrays failed, vertex-colour terrain used', e); return null; }
}

function groundMaterial(arr) {
  const U = Ground.U = {
    tGA: { value: arr.A }, tGN: { value: arr.N }, tS0: { value: Ground.t0 }, tS1: { value: Ground.t1 },
    uMean: { value: arr.mean },
    // texture repeats per metre: grass 2.6 m, dirt 3 m, rock 6 m (triplanar), sand 4 m, forest litter 3 m
    uScale: { value: [1 / 2.6, 1 / 3.0, 1 / 6.0, 1 / 4.0, 1 / 3.0] },
    uRift: { value: SITES.rifts.map((r) => new THREE.Vector4(r.x, r.z, 1, 0)) },
    uTime: Shared.time, uGrassTint: { value: new THREE.Vector3(1.3, 1.75, 0.98) }, uNormStr: { value: 1.0 },
  };
  const m = new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 1, metalness: 0, envMapIntensity: 0.5 });
  m.defines = Object.assign({}, m.defines, { GROUND_HQ: Settings.high ? 1 : 0 });   // keep STANDARD
  m.onBeforeCompile = (sh) => {
    Object.assign(sh.uniforms, U);
    sh.vertexShader = 'varying vec3 vTW; varying vec3 vTNw;\n' + sh.vertexShader.replace('#include <worldpos_vertex>',
      '#include <worldpos_vertex>\n vTW = (modelMatrix * vec4(transformed, 1.0)).xyz; vTNw = normalize(mat3(modelMatrix) * objectNormal);');
    sh.fragmentShader = GROUND_FRAG_HEAD + sh.fragmentShader
      .replace('#include <map_fragment>', GROUND_FRAG_MAIN)
      .replace('#include <roughnessmap_fragment>', '#include <roughnessmap_fragment>\n roughnessFactor = gRough;')
      .replace('#include <normal_fragment_maps>', '#include <normal_fragment_maps>\n normal = normalize((viewMatrix * vec4(gWN, 0.0)).xyz);')
      .replace('#include <emissivemap_fragment>', '#include <emissivemap_fragment>\n totalEmissiveRadiance += gEmis;')
      .replace('#include <aomap_fragment>', '#include <aomap_fragment>\n reflectedLight.indirectDiffuse *= gAO; reflectedLight.indirectSpecular *= mix(1.0, gAO, 0.7);');
  };
  m.customProgramCacheKey = () => 'ground-v1-' + (Settings.high ? 'hq' : 'lq');
  return m;
}

const GROUND_FRAG_HEAD = `
uniform sampler2D tS0, tS1;
uniform sampler2DArray tGA, tGN;
uniform vec3 uMean[5];
uniform float uScale[5];
uniform vec4 uRift[3];
uniform float uTime, uNormStr;
uniform vec3 uGrassTint;
varying vec3 vTW; varying vec3 vTNw;
${GLSL_NOISE}
vec3 gLin(vec3 c) { return c * (c * (c * 0.305306011 + 0.682171111) + 0.012522878); }
void gPaint(inout float W[5], int L, float a) { a = clamp(a, 0.0, 1.0); for (int i = 0; i < 5; i++) W[i] *= 1.0 - a; W[L] += a; }
`;

const GROUND_FRAG_MAIN = `
vec3 gWN; float gRough, gAO; vec3 gEmis = vec3(0.0);
{
  vec3 P = vTW; vec2 xz = P.xz;
  vec3 Ng = normalize(vTNw);
  float dist = length(P - cameraPosition);
  vec3 dPx = dFdx(P), dPy = dFdy(P);
  vec2 dX = dPx.xz, dY = dPy.xz;
  vec2 suv = (xz + 150.0) / 300.0;
  vec4 s0 = texture2D(tS0, suv), s1 = texture2D(tS1, suv);
  float m1 = vnoise(xz * 0.021 + 3.1), m2 = vnoise(xz * 0.083 + 7.7), m3 = vnoise(xz * 0.37 + 1.3);
  // ---- layer weights, painted in order (later wins): grass < forest litter < dirt < rock < sand
  float wet = 1.0 - smoothstep(-0.12, 0.3, P.y + sin(uTime * 0.55 + xz.x * 0.045 + xz.y * 0.03) * 0.07 + (m3 - 0.5) * 0.14);
  float sandW = max(1.0 - smoothstep(0.5, 1.05, P.y + (m2 - 0.5) * 0.5 + (m3 - 0.5) * 0.12), s1.a);
  float rockW = max(s0.b, smoothstep(0.85, 0.7, Ng.y + (m2 - 0.5) * 0.1 + (m3 - 0.5) * 0.04));
  float W[5]; W[0] = 1.0; W[1] = 0.0; W[2] = 0.0; W[3] = 0.0; W[4] = 0.0;
  float hf = (vnoise(xz * 1.9 + 4.2) - 0.5) * 0.7 + (vnoise(xz * 5.3 - 1.7) - 0.5) * 0.35;
  float edgeR = s0.r + hf * 4.0 * s0.r * (1.0 - s0.r);
  float edgeF = s0.g + hf * 3.0 * s0.g * (1.0 - s0.g);
  gPaint(W, 4, edgeF);
  gPaint(W, 1, edgeR);
  gPaint(W, 2, rockW);
  gPaint(W, 3, sandW);
  // ---- sample the active layers (two scales on PC to break tiling) and height-blend them
  vec4 LA[5]; vec4 LN[5]; float V[5]; float vmax = -9.0;
  vec3 rockWN = Ng;
  mat2 rot = mat2(0.8, -0.6, 0.6, 0.8);
  for (int L = 0; L < 5; L++) {
    LA[L] = vec4(0.0); LN[L] = vec4(0.5, 0.5, 1.0, 0.9); V[L] = -9.0;
    if (W[L] > 0.004) {
      float s = uScale[L], fl = float(L);
      vec4 a, n;
      if (L == 2) {
        // rock: triplanar, whiteout-blended world normals
        vec3 bt = pow(abs(Ng), vec3(4.0)); bt /= bt.x + bt.y + bt.z;
        a = vec4(0.0); n = vec4(0.0); vec3 wn = vec3(0.0);
        if (bt.y > 0.02) { vec4 aa = textureGrad(tGA, vec3(P.xz * s, fl), dPx.xz * s, dPy.xz * s), nn = textureGrad(tGN, vec3(P.xz * s, fl), dPx.xz * s, dPy.xz * s);
          vec2 t = (nn.xy * 2.0 - 1.0) * uNormStr; a += aa * bt.y; n += nn * bt.y; wn += vec3(t.x + Ng.x, Ng.y, t.y + Ng.z) * bt.y; }
        if (bt.x > 0.02) { vec4 aa = textureGrad(tGA, vec3(P.zy * s, fl), dPx.zy * s, dPy.zy * s), nn = textureGrad(tGN, vec3(P.zy * s, fl), dPx.zy * s, dPy.zy * s);
          vec2 t = (nn.xy * 2.0 - 1.0) * uNormStr; a += aa * bt.x; n += nn * bt.x; wn += vec3(Ng.x, t.y + Ng.y, t.x + Ng.z) * bt.x; }
        if (bt.z > 0.02) { vec4 aa = textureGrad(tGA, vec3(P.xy * s, fl), dPx.xy * s, dPy.xy * s), nn = textureGrad(tGN, vec3(P.xy * s, fl), dPx.xy * s, dPy.xy * s);
          vec2 t = (nn.xy * 2.0 - 1.0) * uNormStr; a += aa * bt.z; n += nn * bt.z; wn += vec3(t.x + Ng.x, t.y + Ng.y, Ng.z) * bt.z; }
        rockWN = normalize(wn);
      } else {
        vec2 uv = xz * s;
        a = textureGrad(tGA, vec3(uv, fl), dX * s, dY * s);
        n = textureGrad(tGN, vec3(uv, fl), dX * s, dY * s);
#if GROUND_HQ
        float s2 = s * 0.61;
        vec2 uv2 = rot * xz * s2 + vec2(0.37, 0.71) * fl;
        vec2 gx2 = rot * dX * s2, gy2 = rot * dY * s2;
        vec4 a2 = textureGrad(tGA, vec3(uv2, fl), gx2, gy2), n2 = textureGrad(tGN, vec3(uv2, fl), gx2, gy2);
        float k = clamp(0.12 + 0.5 * m2 + smoothstep(10.0, 60.0, dist) * 0.2, 0.0, 0.85);
        a = mix(a, a2, k); n = mix(n, n2, k);
        float kc = 1.0 + 0.6 * k * (1.0 - k);                 // averaging two tiles flattens contrast: restore it
        a.rgb = uMean[L] + (a.rgb - uMean[L]) * kc; a.a = 0.5 + (a.a - 0.5) * kc;
        n.xy = 0.5 + (n.xy - 0.5) * kc;
#endif
      }
      LA[L] = a; LN[L] = n;
      V[L] = W[L] + (a.a - 0.5) * 0.9;
      vmax = max(vmax, V[L]);
    }
  }
  float Bw[5]; float bs = 0.0;
  for (int L = 0; L < 5; L++) { Bw[L] = W[L] > 0.004 ? max(V[L] - vmax + 0.16, 0.0) : 0.0; bs += Bw[L]; }
  // ---- regional colour: lush meadows deeper, north cooler, highlands and the ember hills drier, marsh olive
  float mb = 0.84 + 0.24 * m1 + 0.1 * (m2 - 0.5);
  vec3 tg = uGrassTint;
  tg *= mix(vec3(1.0), vec3(0.8, 0.96, 0.74), s0.a * 0.85);
  tg *= mix(vec3(1.0), vec3(0.86, 0.97, 1.04), smoothstep(-20.0, -45.0, P.z) * 0.7);
  float dryG = clamp(s1.b + smoothstep(6.0, 12.0, P.y) * 0.5 + (m2 - 0.6) * 0.5, 0.0, 1.0);
  tg = mix(tg, vec3(1.3, 1.1, 0.6), dryG * 0.5);
  tg *= mix(vec3(1.0), vec3(0.72, 0.8, 0.55), s1.g * 0.75);
  tg *= mix(vec3(1.0), vec3(1.06, 1.02, 0.86), smoothstep(0.55, 0.85, m2) * 0.5);
  vec3 tdirt = mix(vec3(1.0), vec3(1.08, 0.94, 0.84), s1.b) * mix(vec3(1.0), vec3(0.62, 0.62, 0.6), s1.g);
  vec3 trock = mix(vec3(1.0), vec3(0.96, 0.94, 1.05), s0.b);
  vec3 alb = vec3(0.0), meanC = vec3(0.0); float rough = 0.0, ao = 0.0; vec2 tn = vec2(0.0);
  for (int L = 0; L < 5; L++) {
    float b = Bw[L] / max(bs, 1e-4);
    if (b > 0.0) {
      vec3 tint = L == 0 ? tg : L == 1 ? tdirt : L == 2 ? trock : L == 4 ? vec3(1.25, 1.2, 1.1) : vec3(1.0);
      alb += gLin(clamp(LA[L].rgb, 0.0, 1.0)) * tint * b;
      meanC += gLin(uMean[L]) * tint * b;
      rough += LN[L].a * b; ao += LN[L].b * b;
      if (L != 2) tn += (LN[L].xy * 2.0 - 1.0) * b;
    }
    Bw[L] = b;
  }
  alb *= mb; meanC *= mb;
  // ---- distance: fade detail into the layer averages (no tiling or shimmer far away)
  float fd = smoothstep(55.0, 190.0, dist);
  alb = mix(alb, meanC, fd * 0.6);
  tn *= uNormStr * (1.0 - fd * 0.85);
  // ---- shoreline: wet swash band (dark, glossy, smooth) and a damp fringe above it
  float damp = (1.0 - smoothstep(0.25, 0.85, P.y + (m3 - 0.5) * 0.25)) * (1.0 - wet);
  alb *= mix(1.0, 0.52, wet) * (1.0 - 0.18 * damp);
  rough = mix(rough, 0.14, wet * 0.9);
  rough *= 1.0 - 0.35 * s1.g;
  tn *= 1.0 - 0.65 * wet;
#if GROUND_HQ
  if (P.y < 0.06) {     // caustics on the shallow sea floor
    vec2 cp = xz * 0.6;
    float c1 = vnoise(cp + vec2(uTime * 0.33, uTime * 0.21)), c2 = vnoise(cp * 1.37 - vec2(uTime * 0.27, -uTime * 0.3) + 4.0);
    float ca = pow(1.0 - abs(c1 - c2), 9.0);
    alb *= 1.0 + ca * 1.5 * smoothstep(0.06, -0.35, P.y) * exp(P.y * 0.3);
  }
#endif
  // ---- contact darkening painted by groundStamp
  alb *= 1.0 - 0.5 * s1.r; ao *= 1.0 - 0.6 * s1.r;
  // ---- void-rift corruption: drained, violet-stained earth with faintly glowing veins (heals when a rift closes)
  float corr = 0.0;
  for (int i = 0; i < 3; i++) { float d = length(xz - uRift[i].xy) + (m3 - 0.5) * 3.0 + (m2 - 0.5) * 5.0; corr = max(corr, uRift[i].z * (1.0 - smoothstep(5.0, 17.0, d))); }
  if (corr > 0.001) {
    float lum = dot(alb, vec3(0.3, 0.59, 0.11));
    alb = mix(alb, lum * vec3(0.7, 0.5, 1.0) * 0.85, corr * 0.72);
    rough = mix(rough, 0.5, corr * 0.35);
    float vein = 1.0 - abs(vnoise(xz * 0.7 + 2.0) * 2.0 - 1.0);
    vein *= 1.0 - abs(vnoise(xz * 2.1 + 5.0) * 2.0 - 1.0) * 0.6;
    gEmis = vec3(0.55, 0.12, 1.15) * pow(vein, 16.0) * corr * corr * (0.65 + 0.35 * sin(uTime * 1.7 + m2 * 6.0)) * 0.75;
  }
  diffuseColor.rgb = alb * mix(1.0, ao, 0.3);
  gRough = clamp(rough, 0.05, 1.0); gAO = clamp(ao, 0.0, 1.0);
  float bR = Bw[2];
  vec3 wnP = normalize(vec3(tn.x / max(1.0 - bR, 0.05) + Ng.x, Ng.y, tn.y / max(1.0 - bR, 0.05) + Ng.z));
  gWN = normalize(mix(wnP, rockWN, bR));
}
`;

const SITES = {
  town: { x: 0, z: 50 },
  spawn: { x: 0, z: 63 },
  altar: { x: 0, z: -6 },
  rifts: [
    { id: 'east', x: 60, z: 6, name: '동쪽 균열', gx: 53.5, gz: 6.5 },
    { id: 'west', x: -60, z: 2, name: '서쪽 균열', gx: -53.5, gz: 2.5 },
    { id: 'north', x: 4, z: -64, name: '북쪽 균열', gx: 3.5, gz: -57.5 },
  ],
};
const PATHS = [
  [[0, 68], [0, 50], [0, 32], [2, 14], [0, -6]],
  [[0, 32], [20, 26], [42, 14], [60, 6]],
  [[0, 32], [-20, 26], [-42, 12], [-60, 2]],
  [[0, -6], [3, -26], [3, -46], [4, -64]],
];
const ZONES = [
  { x: -14, z: 22, r: 8.5, pool: 'south', name: '남쪽 들판' },
  { x: 14, z: 20, r: 8, pool: 'south', name: '남쪽 들판' },
  { x: 40, z: 25, r: 9, pool: 'east', name: '불씨 언덕' },
  { x: -38, z: 23, r: 9, pool: 'west', name: '번개 습지' },
  { x: -13, z: -40, r: 9, pool: 'north', name: '그림자 숲길' },
  { x: 17, z: -46, r: 8, pool: 'north', name: '그림자 숲길' },
  { x: 17, z: -12, r: 6.5, pool: 'altar', name: '제단 비탈' },
  { x: -15, z: -1, r: 6, pool: 'altar', name: '제단 비탈' },
];

function segDist(px, pz, ax, az, bx, bz) {
  const vx = bx - ax, vz = bz - az, wx = px - ax, wz = pz - az;
  const t = clamp((wx * vx + wz * vz) / (vx * vx + vz * vz), 0, 1);
  return Math.hypot(px - (ax + vx * t), pz - (az + vz * t));
}
function pathDist(x, z) {
  let d = 1e9;
  for (const P of PATHS) for (let i = 0; i < P.length - 1; i++) d = Math.min(d, segDist(x, z, P[i][0], P[i][1], P[i + 1][0], P[i + 1][1]));
  return d;
}
function coastR(a) { return 90 + 7 * Math.sin(a * 3 + 1.3) + 4 * Math.sin(a * 7 + 0.4) + 2.5 * Math.sin(a * 13 + 2.1); }
function rawHeight(x, z) {
  const r = Math.hypot(x, z), a = Math.atan2(z, x);
  const m = 1 - smooth(coastR(a) - 20, coastR(a) + 3, r);
  let h = -3.4 + m * 4.8;
  h += (fbm(x * 0.028 + 11.3, z * 0.028 - 7.1, 4) - 0.45) * 5.0 * m;
  const g = (cx, cz, s, amp) => amp * Math.exp(-((x - cx) ** 2 + (z - cz) ** 2) / (2 * s * s)) * m;
  h += g(SITES.altar.x, SITES.altar.z, 15, 7.5);
  h += g(38, -36, 11, 11) + g(-40, -32, 11, 8) + g(-30, 64, 9, 5) + g(62, 40, 10, 6) + g(-64, 40, 9, 4);
  return h;
}
const FLATS = [];
function initFlats() {
  FLATS.length = 0;
  FLATS.push({ x: SITES.town.x, z: SITES.town.z + 4, r0: 15, r1: 25, h: 1.6 });
  FLATS.push({ x: SITES.altar.x, z: SITES.altar.z, r0: 9.5, r1: 15, h: rawHeight(SITES.altar.x, SITES.altar.z) });
  for (const r of SITES.rifts) FLATS.push({ x: r.x, z: r.z, r0: 7, r1: 13, h: Math.max(rawHeight(r.x, r.z), 1.5) });
}
function heightAt(x, z) {
  let h = rawHeight(x, z);
  const pd = pathDist(x, z);
  if (pd < 5) { const w = 1 - smooth(2.5, 5, pd); h = lerp(h, Math.max(h, 1.15), w); }
  for (const f of FLATS) {
    const d = Math.hypot(x - f.x, z - f.z);
    if (d < f.r1) h = lerp(h, f.h, 1 - smooth(f.r0, f.r1, d));
  }
  return h;
}

const World = {
  scene: null, camera: null, N: 200, SIZE: 300, grid: null,
  colliders: [], interact: [], npcs: [], rifts: {}, markers: [], zones: ZONES,
  camYaw: 0, camDist: 12, camPos: new THREE.Vector3(), camLook: new THREE.Vector3(), cine: null,
  heal: 0, healTarget: 0, dawn: 0, dawnTarget: 0, t: 0,
};

function groundY(x, z) {
  const W = World, N = W.N, S = W.SIZE, c = S / N;
  const fx = clamp((x + S / 2) / c, 0, N - 1e-3), fz = clamp((z + S / 2) / c, 0, N - 1e-3);
  const i = Math.floor(fz), j = Math.floor(fx), u = fx - j, v = fz - i, R = N + 1, g = W.grid;
  return lerp(lerp(g[i * R + j], g[i * R + j + 1], u), lerp(g[(i + 1) * R + j], g[(i + 1) * R + j + 1], u), v);
}

function buildWorld() {
  initFlats();
  const W = World;
  const scene = W.scene = new THREE.Scene();
  const cam = W.camera = new THREE.PerspectiveCamera(52, innerWidth / innerHeight, 0.1, 1600);
  Cams.push(cam);
  scene.fog = new THREE.Fog(0x6a4a7a, 60, 330);
  // aerial perspective (see patchFogChunks): sun in-scatter + height fog only while the island renders
  W.fogSun = 0.85; W.fogHeight = Settings.high ? 0.0065 : 0.005;
  scene.onBeforeRender = () => { FogAtmo.dir.w = W.fogSun; FogAtmo.height.x = W.fogHeight; FogAtmo.height.w = 1.4; };
  scene.onAfterRender = () => { FogAtmo.dir.w = 0; FogAtmo.height.x = 0; };

  // ---------------- lights
  W.hemi = new THREE.HemisphereLight(0x9fb2e6, 0x6a5838, 0.95); scene.add(W.hemi);
  W.sunDir = new THREE.Vector3(-0.86, 0.4, 0.3).normalize();
  const sun = W.sun = new THREE.DirectionalLight(0xffb98a, 2.7);
  sun.castShadow = true; sun.shadow.mapSize.set(isTouch ? 1024 : 2048, isTouch ? 1024 : 2048);
  const sc = sun.shadow.camera; sc.left = -34; sc.right = 34; sc.top = 34; sc.bottom = -34; sc.near = 1; sc.far = 160;
  sun.shadow.bias = -0.0006; sun.shadow.normalBias = 0.04;
  scene.add(sun); scene.add(sun.target);
  W.rim = new THREE.DirectionalLight(0x8fb0ff, 0.6); W.rim.position.set(30, 20, 40); scene.add(W.rim);

  // ---------------- terrain heights
  const N = W.N, S = W.SIZE, R = N + 1;
  W.grid = new Float32Array(R * R);
  const noiseV = new Float32Array(R * R), pdV = new Float32Array(R * R);
  for (let i = 0; i <= N; i++) for (let j = 0; j <= N; j++) {
    const x = -S / 2 + j * S / N, z = -S / 2 + i * S / N;
    W.grid[i * R + j] = heightAt(x, z);
    noiseV[i * R + j] = fbm(x * 0.09 + 3.3, z * 0.09 + 8.1, 3);
    pdV[i * R + j] = pathDist(x, z);
  }
  const geo = new THREE.PlaneGeometry(S, S, N, N); geo.rotateX(-Math.PI / 2);
  const pos = geo.attributes.position;
  for (let k = 0; k < pos.count; k++) pos.setY(k, W.grid[k]);
  geo.computeVertexNormals();
  const col = new Float32Array(pos.count * 3);
  geo.setAttribute('color', new THREE.BufferAttribute(col, 3));
  W.terrainGeo = geo; W._noiseV = noiseV; W._pdV = pdV;
  recolorTerrain();
  // PBR ground: splat map + five authored material sets, height-blended (vertex colours stay as the fallback)
  buildSplat();
  Ground.arrays = buildGroundArrays();
  let tmat;
  if (Ground.arrays) tmat = groundMaterial(Ground.arrays);
  else {
    tmat = new THREE.MeshLambertMaterial({ vertexColors: true });
    tmat.onBeforeCompile = (sh) => {
      sh.vertexShader = 'varying vec3 vTW;\n' + sh.vertexShader.replace('#include <begin_vertex>', '#include <begin_vertex>\n vTW = (modelMatrix * vec4(position, 1.0)).xyz;');
      sh.fragmentShader = 'varying vec3 vTW;\n' + GLSL_NOISE + sh.fragmentShader.replace('#include <color_fragment>', `#include <color_fragment>
        {
          float n1 = vnoise(vTW.xz * 0.33), n2 = vnoise(vTW.xz * 1.6 + 7.0), n3 = vnoise(vTW.xz * 5.5 + 3.0), n4 = vnoise(vTW.xz * 17.0);
          diffuseColor.rgb *= 0.84 + 0.2 * n1 + 0.1 * (n2 - 0.5) + 0.08 * (n3 - 0.5) + 0.05 * (n4 - 0.5);
          float lum = dot(diffuseColor.rgb, vec3(0.3, 0.59, 0.11));
          diffuseColor.rgb = mix(diffuseColor.rgb, diffuseColor.rgb * vec3(1.08, 1.0, 0.86), smoothstep(0.55, 0.8, n2) * 0.5);
          diffuseColor.rgb = mix(vec3(lum), diffuseColor.rgb, 1.12);
        }`);
    };
  }
  const terrain = new THREE.Mesh(geo, tmat);
  terrain.receiveShadow = true; scene.add(terrain); W.terrain = terrain;

  // height texture for the sea shader
  const HT = 256, hd = new Uint8Array(HT * HT);
  for (let i = 0; i < HT; i++) for (let j = 0; j < HT; j++) {
    const x = -S / 2 + (j + 0.5) * S / HT, z = -S / 2 + (i + 0.5) * S / HT;
    hd[i * HT + j] = Math.round(clamp((groundY(x, z) + 8) / 12, 0, 1) * 255);
  }
  const htex = new THREE.DataTexture(hd, HT, HT, THREE.RedFormat); htex.magFilter = htex.minFilter = THREE.LinearFilter; htex.needsUpdate = true;

  // ---------------- sea: sky reflection with Fresnel, authored normal map scrolled in two directions at two scales,
  // depth absorption, sun glint, swash foam at the waterline. ~4 texture reads per pixel, so it stays cheap on phones.
  W.skyU = makeSkyUniforms(); W.skyU.uHaze.value = 1;
  const wtex = assetTex('water_normal');
  W.waterU = {
    uTime: Shared.time, uH: { value: htex }, uWN: { value: wtex },
    uTop: W.skyU.uTop, uMid: W.skyU.uMid, uHor: W.skyU.uHor, uSunDir: W.skyU.uSunDir, uSunCol: W.skyU.uSunCol, uSunAmt: W.skyU.uSunAmt,
    uFogCol: W.skyU.uFogCol, uFogSun: W.skyU.uFogSun, uHaze: W.skyU.uHaze,
    uDeep: { value: new THREE.Color(0x0b2a46) }, uShallow: { value: new THREE.Color(0x2a9f9a) }, uFoam: { value: new THREE.Color(0xf2f4f6) },
    uSky: { value: new THREE.Color(0xb48ad0) },
  };
  const water = new THREE.Mesh(new THREE.PlaneGeometry(1400, 1400, 1, 1).rotateX(-Math.PI / 2), new THREE.ShaderMaterial({
    uniforms: THREE.UniformsUtils.merge([THREE.UniformsLib.fog]), transparent: true, fog: true, defines: wtex ? { WATER_TEX: 1 } : {},
    vertexShader: `varying vec3 vW; ${FOG_V}
      void main(){ vec4 w = modelMatrix*vec4(position,1.0); vW = w.xyz; vec4 mvPosition = viewMatrix*w; gl_Position = projectionMatrix*mvPosition;
        #include <fog_vertex>
      }`,
    fragmentShader: `uniform float uTime; uniform sampler2D uH, uWN; uniform vec3 uDeep, uShallow, uFoam, uSky; ${SKY_DECL} varying vec3 vW;
      ${GLSL_NOISE}
      ${SKY_FN}
      ${FOG_F}
      void main(){
        vec2 uv = (vW.xz + 150.0) / 300.0; float h = -8.0;
        if (uv.x > 0.0 && uv.y > 0.0 && uv.x < 1.0 && uv.y < 1.0) h = texture2D(uH, uv).r * 12.0 - 8.0;
        float depth = clamp(-h, 0.0, 8.0), t = uTime;
        vec3 toC = cameraPosition - vW; float dist = length(toC); vec3 V = toC / dist;
#ifdef WATER_TEX
        vec4 w1 = texture2D(uWN, vW.xz * 0.075 + vec2(t * 0.012, t * 0.007));
        vec4 w2 = texture2D(uWN, mat2(0.8, -0.6, 0.6, 0.8) * vW.xz * 0.027 - vec2(t * 0.006, -t * 0.0085));
        vec2 nxy = (w1.xy * 2.0 - 1.0) * 0.8 + (w2.xy * 2.0 - 1.0) * 1.1;
        float lace = texture2D(uWN, vW.xz * 0.21 + vec2(t * 0.018, -t * 0.011)).b;
#else
        vec2 p = vW.xz * 0.16;
        float n1 = vnoise(p + vec2(t*0.09, t*0.05)), n2 = vnoise(p*2.3 - vec2(t*0.07, -t*0.1)), n3 = vnoise(p*5.1 + vec2(-t*0.15, t*0.12));
        vec2 nxy = vec2((n1-0.5)*1.1 + (n3-0.5)*0.5, (n2-0.5)*1.1 - (n3-0.5)*0.4);
        float lace = vnoise(vW.xz * 1.3 + t * 0.2);
#endif
        float chop = 0.45 + 0.55 * smoothstep(0.1, 2.8, depth);               // shallows are calmer
        nxy *= (1.0 - smoothstep(50.0, 420.0, dist) * 0.8) * chop;
        vec3 N = normalize(vec3(nxy.x * 0.42, 1.0, nxy.y * 0.42));
        float ndv = max(dot(N, V), 0.0);
        float F = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);
        vec3 R = reflect(-V, N); R.y = abs(R.y);
        vec3 refl = skyGrad(R);
        float sdR = max(dot(R, uSunDir), 0.0);
        vec3 glint = uSunCol * (pow(sdR, 1400.0) * 70.0 + pow(sdR, 120.0) * 1.6 + pow(sdR, 16.0) * 0.12) * uSunAmt;
        // water body: absorption with depth, a little sky-tinted scattering
        float absb = 1.0 - exp(-depth * 0.5);
        vec3 body = mix(uShallow, uDeep, absb);
        body = mix(body, uSky * 0.4, 0.12) * (0.75 + 0.25 * max(dot(vec3(0.0, 1.0, 0.0), uSunDir), 0.0));
        vec3 col = mix(body, refl, F) + glint;
        // swash: foam breaks along the waterline and in bands that run up the beach
        float shore = 1.0 - smoothstep(0.0, 1.4, depth);
        float wave = sin(depth * 5.0 - t * 1.4 + vnoise(vW.xz * 0.22) * 6.0) * 0.5 + 0.5;
        float fa = shore * (0.25 + 0.75 * wave * wave) + (1.0 - smoothstep(0.05, 0.3, depth));
        float foam = smoothstep(1.05 - fa, 1.25 - fa, lace * 0.75 + 0.3);
        col = mix(col, uFoam * (0.85 + 0.25 * max(uSunDir.y, 0.0)), foam * 0.85);
        float a = mix(0.3, 0.97, smoothstep(0.0, 2.6, depth));
        a = max(max(a, foam * 0.9), clamp(F * 1.3, 0.0, 1.0));
        gl_FragColor = vec4(col, a);
        #include <fog_fragment>
      }`,
  }));
  Object.assign(water.material.uniforms, W.waterU);
  water.position.y = 0; scene.add(water); W.water = water;
  // dark sea floor so deep water reads properly at distance
  const floor = new THREE.Mesh(new THREE.PlaneGeometry(1400, 1400).rotateX(-Math.PI / 2), new THREE.MeshBasicMaterial({ color: 0x081a36 }));
  floor.position.y = -7.5; scene.add(floor);

  // ---------------- sky
  W.sky = makeSky(W.skyU); scene.add(W.sky);

  // ---------------- vegetation & props
  buildTrees(scene);
  buildRocksAndFlowers(scene);
  buildNatureExtras(scene);          // 03c_nature.js: extra props/animated life (ferns, logs, butterflies...)
  W.grass = buildGrass(scene, ZONES);
  W.fireflies = buildFireflies(scene);
  buildTown(scene);
  buildAltar(scene);
  for (const r of SITES.rifts) buildRift(scene, r);
  W.fx = new Particles(scene, 1600);
  W.dust = new Puffs(scene, 160);
  buildLegendSites();

  // ---------------- player & follower
  W.player = buildPerson({ accent: 0x8b5cff, hair: 0x25223a, pin: 0xffd98a, eye: 0x24245a, eye2: 0x7aa4ff });
  W.player.root.position.set(SITES.spawn.x, groundY(SITES.spawn.x, SITES.spawn.z), SITES.spawn.z);
  W.player.root.rotation.y = Math.PI;
  scene.add(W.player.root);
  W.follower = null;
  W.camYaw = 0;
  snapCamera();
}

function riftCorruption(x, z) {
  let c = 0;
  for (const r of SITES.rifts) {
    if (S.flags['closed_' + r.id]) continue;
    c = Math.max(c, 1 - smooth(5, 17, Math.hypot(x - r.x, z - r.z)));
  }
  return c;
}
function recolorTerrain(immediate) {
  // PBR ground: corruption is computed per pixel from the rift uniforms; closing a rift heals it over a few seconds
  SITES.rifts.forEach((r, i) => {
    Ground.riftT[i] = S.flags['closed_' + r.id] ? 0 : 1;
    if (immediate && Ground.U) Ground.U.uRift.value[i].z = Ground.riftT[i];
  });
  const W = World, geo = W.terrainGeo, pos = geo.attributes.position, nrm = geo.attributes.normal, col = geo.attributes.color;
  const C = (h) => new THREE.Color(h);
  const SAND = C(0xe9d3a0), WET = C(0xb79e72), G1 = C(0x5aa64a), G2 = C(0x86c45c), G3 = C(0x3d8645), NORTH = C(0x47905a),
    ROCK = C(0x8f877c), DIRT = C(0xc99d68), LUSH = C(0x2f7a3e), CORR = C(0x3e2a62), STONE = C(0xcfc6b6), ALT = C(0xb7b0c8), HIGH = C(0xa5c47a);
  const c = new THREE.Color();
  for (let k = 0; k < pos.count; k++) {
    const x = pos.getX(k), y = pos.getY(k), z = pos.getZ(k), n = W._noiseV[k], ny = nrm.getY(k);
    c.copy(G1).lerp(G2, smooth(0.45, 0.75, n)).lerp(G3, smooth(0.45, 0.2, n) * 0.8);
    if (z < -20) c.lerp(NORTH, smooth(-20, -45, z) * 0.6);
    if (y > 6) c.lerp(HIGH, smooth(6, 12, y) * 0.5);
    for (const zz of ZONES) { const d = Math.hypot(x - zz.x, z - zz.z); if (d < zz.r + 2) c.lerp(LUSH, (1 - smooth(zz.r - 1, zz.r + 2, d)) * 0.75); }
    const pd = W._pdV[k]; if (pd < 3.6) c.lerp(DIRT, (1 - smooth(1.7, 3.6, pd)) * (0.85 + n * 0.15));
    const dt = Math.hypot(x - SITES.town.x, z - SITES.town.z); if (dt < 10) c.lerp(STONE, 1 - smooth(8.5, 10, dt));
    const da = Math.hypot(x - SITES.altar.x, z - SITES.altar.z); if (da < 10.5) c.lerp(ALT, 1 - smooth(9, 10.5, da));
    if (ny < 0.84) c.lerp(ROCK, smooth(0.84, 0.7, ny));
    if (y < 1.0) c.lerp(SAND, smooth(1.0, 0.45, y));
    if (y < 0.1) c.lerp(WET, smooth(0.1, -0.6, y));
    const cr = riftCorruption(x, z); if (cr > 0) c.lerp(CORR, cr * (0.75 + n * 0.25));
    col.setXYZ(k, c.r, c.g, c.b);
  }
  col.needsUpdate = true;
}

function makeSkyUniforms() {
  return {
    uTime: Shared.time,
    uTop: { value: new THREE.Color(0x0c0a2a) }, uMid: { value: new THREE.Color(0x4a2a6a) }, uHor: { value: new THREE.Color(0xe0728a) },
    uSunDir: { value: new THREE.Vector3(-0.86, 0.4, 0.3).normalize() }, uMoonDir: { value: new THREE.Vector3(0.55, 0.42, -0.72).normalize() },
    uCrackDir: { value: new THREE.Vector3(0.08, 0.5, -1).normalize() }, uCrack: { value: 1 }, uStars: { value: 1 }, uCloud: { value: 1 }, uSunAmt: { value: 1 },
    // sun colour (disc, glow, cloud light) and the horizon haze that matches the scene fog (uHaze 0 = no haze band)
    uSunCol: { value: new THREE.Color(0xffd2a0) }, uFogCol: { value: new THREE.Color(0x9a96b0) }, uFogSun: { value: new THREE.Color(0xffc49a) }, uHaze: { value: 0 },
  };
}
// shared sky gradient (sky dome + water reflections): Rayleigh-like air-mass gradient (deep zenith, paler and warmer
// toward the horizon, warmest under the sun, cooler opposite it), Mie glow around the sun, and the fog-matched haze
const SKY_DECL = `uniform vec3 uTop, uMid, uHor, uSunDir, uSunCol, uFogCol, uFogSun; uniform float uSunAmt, uHaze;`;
const SKY_FN = `
  vec3 skyHaze(vec3 d) {
    float s = max(dot(d, uSunDir), 0.0);
    return mix(uFogCol, uFogSun, clamp(pow(s, 6.0) * 0.7 + pow(s, 40.0) * 0.45, 0.0, 1.0));
  }
  vec3 skyGrad(vec3 d) {
    float y = d.y, yy = max(y, 0.0), mu = dot(d, uSunDir);
    vec3 hd = normalize(vec3(d.x, 0.0, d.z) + 1e-5), sd = normalize(vec3(uSunDir.x, 0.0, uSunDir.z) + 1e-5);
    float az = dot(hd, sd) * 0.5 + 0.5;
    float am = 1.0 - exp(-0.09 / (yy + 0.035));                      // relative air mass: 0.08 zenith .. 0.92 horizon
    vec3 col = mix(uTop, uMid, smoothstep(0.0, 0.32, am));
    vec3 horC = mix(mix(uHor, uMid * 1.05, 0.45) * vec3(1.02, 0.94, 1.04), uHor * 1.06, az);
    col = mix(col, horC, smoothstep(0.25, 0.92, am));
    float m = max(mu, 0.0);
    col += uSunCol * (pow(m, 5.0) * 0.22 + pow(m, 40.0) * 0.38 + pow(m, 350.0) * 1.1) * uSunAmt * (0.55 + 0.45 * am);
    col = mix(col, skyHaze(d), uHaze * (1.0 - smoothstep(0.0, 0.14, y)) * 0.85);
    col = mix(col, uHaze > 0.0 ? skyHaze(d) : uHor * 0.45, smoothstep(0.0, -0.08, y));
    return col;
  }
`;
function makeSky(U) {
  const g = new THREE.Group();
  if (!U.uSunCol) Object.assign(U, { uSunCol: { value: new THREE.Color(0xffd2a0) }, uFogCol: { value: new THREE.Color(0x9a96b0) }, uFogSun: { value: new THREE.Color(0xffc49a) }, uHaze: { value: 0 } });
  const mat = new THREE.ShaderMaterial({
    uniforms: U, side: THREE.BackSide, depthWrite: false, fog: false, defines: { SKY_HQ: Settings.high ? 1 : 0 },
    vertexShader: `varying vec3 vDir; void main(){ vDir = position; vec4 p = projectionMatrix * modelViewMatrix * vec4(position,1.0); gl_Position = p.xyww; }`,
    fragmentShader: `${SKY_DECL} uniform vec3 uMoonDir, uCrackDir; uniform float uTime, uCrack, uStars, uCloud; varying vec3 vDir;
      ${GLSL_NOISE}
      ${SKY_FN}
      float cfbm(vec2 p, int oct){ float s = 0.0, a = 0.5, t = 0.0; for (int i = 0; i < 6; i++) { if (i >= oct) break; s += a * vnoise(p); t += a; p = mat2(1.6, -1.2, 1.2, 1.6) * p + 3.7; a *= 0.5; } return s / t; }
      vec2 crackLine(vec2 q, float L, float w, float seed){
        float along = q.y, across = q.x;
        float jag = (vnoise(vec2(along*9.0, seed))-0.5)*0.09 + (vnoise(vec2(along*27.0, seed+7.7))-0.5)*0.035;
        float ww = w * (1.0 - smoothstep(0.0, L, abs(along)));
        float d = abs(across - jag);
        float inside = step(d, ww) * step(abs(along), L);
        float glow = exp(-max(d - ww, 0.0) * 55.0) * (1.0 - smoothstep(L*0.75, L*1.1, abs(along)));
        return vec2(inside, glow);
      }
      void main(){
        vec3 d = normalize(vDir); float y = d.y;
        vec3 col = skyGrad(d);
        float mu = dot(d, uSunDir);
        // sun disc with limb darkening (HDR: feeds the bloom and the PBR environment map)
        float sr = 0.0105, ang = acos(clamp(mu, -1.0, 1.0));
        float disc = 1.0 - smoothstep(sr * 0.8, sr, ang);
        col += uSunCol * disc * (0.45 + 0.55 * sqrt(max(1.0 - (ang / sr) * (ang / sr), 0.0))) * 16.0 * uSunAmt * smoothstep(-0.02, 0.02, y);
        float md = dot(d, uMoonDir);
        float moon = smoothstep(0.99935, 0.99955, md);
        vec3 mc = vec3(0.92, 0.9, 1.0) * (0.85 + 0.15 * vnoise(d.xz * 900.0));
        col = mix(col, mc * 1.4, moon * uStars);
        col += vec3(0.5, 0.45, 0.8) * pow(max(md, 0.0), 220.0) * 0.6 * uStars;
        if (y > 0.0 && uCloud > 0.001) {
          vec3 hd = normalize(vec3(d.x, 0.0, d.z) + 1e-5), sd = normalize(vec3(uSunDir.x, 0.0, uSunDir.z) + 1e-5);
          float az = dot(hd, sd) * 0.5 + 0.5;
          // cumulus deck projected on a plane, domain-warped, lit from the sun with a self-shadow probe
          vec2 cp = d.xz / (y + 0.12) * 1.3 + vec2(uTime * 0.011, uTime * 0.004);
          vec2 q = cp + (vec2(vnoise(cp * 0.55 + 1.7), vnoise(cp * 0.55 + 9.2)) - 0.5) * 1.1;
          float cn = cfbm(q, SKY_HQ == 1 ? 6 : 3);
          float cov = smoothstep(0.45, 0.72, cn) * smoothstep(0.0, 0.07, y) * (1.0 - smoothstep(0.55, 0.95, y));
          float thick = smoothstep(0.52, 0.86, cn);
          vec2 sdir = normalize(uSunDir.xz + 1e-4) * 0.45;
#if SKY_HQ == 1
          float sh = smoothstep(0.42, 0.8, cfbm(q + sdir, 3));
#else
          float sh = thick * 0.8;
#endif
          vec3 amb = uTop * 0.45 + uMid * 0.55;
          vec3 lit = uHor * (0.75 + 0.5 * az) + uSunCol * 0.42;
          vec3 cc = mix(lit, amb * 0.82, clamp(sh * 0.8 + thick * 0.3, 0.0, 1.0));
          cc += uSunCol * cov * (1.0 - thick) * pow(max(mu, 0.0), 5.0) * 2.4 * uSunAmt;   // silver lining toward the sun
          cc = mix(cc, col, (1.0 - smoothstep(0.0, 0.22, y)) * 0.5);                          // distant cloud sinks into haze
          col = mix(col, cc, cov * min(uCloud, 1.0) * 0.94);
          // high cirrus streaks
          vec2 cq = d.xz / (y + 0.35) * vec2(0.55, 2.4) + vec2(uTime * 0.004, 0.0);
          float ci = smoothstep(0.56, 0.86, vnoise(cq) * 0.6 + vnoise(cq * 2.7 + 3.1) * 0.4) * smoothstep(0.06, 0.35, y) * (1.0 - cov);
          col = mix(col, mix(amb * 1.1, lit, 0.65), ci * 0.32 * min(uCloud, 1.0));
        }
        vec3 c = normalize(uCrackDir);
        vec3 tX = normalize(cross(vec3(0.0, 1.0, 0.0), c)); vec3 tY = cross(c, tX);
        float dc = dot(d, c);
        if (dc > 0.2 && uCrack > 0.001) {
          vec2 q = vec2(dot(d, tX), dot(d, tY)) / dc;
          float L = 0.62 * uCrack, w = 0.085 * min(uCrack, 1.5);
          vec2 a = crackLine(q, L, w, 3.1);
          vec2 qb = mat2(0.77, -0.64, 0.64, 0.77) * (q - vec2(0.02, 0.18 * uCrack)); qb.y -= L * 0.32;
          vec2 b = crackLine(qb, L * 0.34, w * 0.6, 11.0);
          vec2 qc = mat2(0.8, 0.6, -0.6, 0.8) * (q + vec2(0.0, 0.22 * uCrack)); qc.y += L * 0.28;
          vec2 e = crackLine(qc, L * 0.3, w * 0.5, 19.0);
          float inside = max(a.x, max(b.x, e.x)); float glow = max(a.y, max(b.y * 0.8, e.y * 0.8));
          vec3 voidc = vec3(0.008, 0.0, 0.02) + vec3(0.3, 0.06, 0.55) * pow(vnoise(q * 16.0 + uTime * 0.25), 3.0);
          col = mix(col, voidc, inside);
          col += vec3(1.25, 0.32, 2.3) * glow * (1.0 - inside) * min(uCrack, 1.6) * 0.85;
          col += vec3(0.35, 0.08, 0.6) * exp(-length(vec2(q.x * 1.7, q.y * 0.75)) * 2.6) * 0.55 * min(uCrack, 1.5);
        }
        gl_FragColor = vec4(col, 1.0);
      }`,
  });
  const dome = new THREE.Mesh(new THREE.SphereGeometry(700, 48, 24), mat); dome.frustumCulled = false; dome.renderOrder = -10; g.add(dome);
  // stars
  const n = 1800, sp = new Float32Array(n * 3), ss = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    let x, yy, z; do { x = rand(-1, 1); yy = rand(0.04, 1); z = rand(-1, 1); } while (x * x + yy * yy + z * z > 1);
    const l = Math.hypot(x, yy, z); sp[i * 3] = x / l * 650; sp[i * 3 + 1] = yy / l * 650; sp[i * 3 + 2] = z / l * 650; ss[i] = Math.random();
  }
  const sg = new THREE.BufferGeometry(); sg.setAttribute('position', new THREE.BufferAttribute(sp, 3)); sg.setAttribute('seed', new THREE.BufferAttribute(ss, 1));
  const stars = new THREE.Points(sg, new THREE.ShaderMaterial({
    uniforms: { uTime: U.uTime, uStars: U.uStars, uTex: { value: TEX.dot } }, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, fog: false,
    vertexShader: `attribute float seed; uniform float uTime; varying float vA; void main(){ vec3 p = position; float h = normalize(p).y;
      vA = smoothstep(0.08, 0.35, h) * (0.55 + 0.45 * sin(uTime * (1.0 + seed * 3.0) + seed * 40.0)) * (0.35 + seed * 0.65);
      vec4 mv = modelViewMatrix * vec4(p, 1.0); gl_PointSize = 1.5 + seed * 2.6; gl_Position = projectionMatrix * mv; gl_Position.z = gl_Position.w * 0.9999; }`,
    fragmentShader: `uniform sampler2D uTex; uniform float uStars; varying float vA; void main(){ float a = texture2D(uTex, gl_PointCoord).a * vA * uStars; gl_FragColor = vec4(vec3(0.9, 0.92, 1.2) * a * 1.6, 1.0); }`,
  }));
  stars.frustumCulled = false; stars.renderOrder = -9; g.add(stars);
  // clouds
  g.userData.clouds = [];
  for (let i = 0; i < 16; i++) {
    const a = rand(0, Math.PI * 2), el = rand(0.04, 0.2), dist = 560;
    const sm = new THREE.SpriteMaterial({ map: TEX.cloud, color: new THREE.Color(0xf0a6c0), transparent: true, opacity: rand(0.18, 0.34), depthWrite: false, fog: false });
    const spr = new THREE.Sprite(sm);
    spr.position.set(Math.cos(a) * dist * Math.cos(el), Math.sin(el) * dist, Math.sin(a) * dist * Math.cos(el));
    spr.scale.set(rand(160, 280), rand(50, 90), 1); spr.renderOrder = -8; g.add(spr); g.userData.clouds.push(spr);
  }
  return g;
}

function buildFireflies(scene) {
  const n = 420, pos = new Float32Array(n * 3), seed = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    let x, z, h; do { x = rand(-85, 85); z = rand(-85, 85); h = groundY(x, z); } while (h < 0.8);
    pos[i * 3] = x; pos[i * 3 + 1] = h + rand(0.4, 3.2); pos[i * 3 + 2] = z; seed[i] = Math.random();
  }
  const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.BufferAttribute(pos, 3)); g.setAttribute('seed', new THREE.BufferAttribute(seed, 1));
  const U = { uTime: Shared.time, uTex: { value: TEX.dot }, uColor: { value: new THREE.Color(0xd8ff8a) } };
  const p = new THREE.Points(g, new THREE.ShaderMaterial({
    uniforms: U, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
    vertexShader: `attribute float seed; uniform float uTime; varying float vA; void main(){ vec3 p = position;
      p.x += sin(uTime * 0.5 + seed * 30.0) * 1.2; p.y += sin(uTime * 0.8 + seed * 50.0) * 0.5; p.z += cos(uTime * 0.45 + seed * 20.0) * 1.2;
      vA = pow(0.5 + 0.5 * sin(uTime * (1.5 + seed * 2.0) + seed * 60.0), 3.0);
      vec4 mv = modelViewMatrix * vec4(p, 1.0); gl_PointSize = 120.0 * (0.6 + seed * 0.6) / -mv.z; gl_Position = projectionMatrix * mv; }`,
    fragmentShader: `uniform sampler2D uTex; uniform vec3 uColor; varying float vA; void main(){ float a = texture2D(uTex, gl_PointCoord).a * vA; gl_FragColor = vec4(uColor * a * 2.6, 1.0); }`,
  }));
  p.frustumCulled = false; scene.add(p); return p;
}

// ---------------- town (cottages, lanterns, plaza and fountain live in 03b_town.js)
function buildTown(scene) {
  World.spinners = [];
  TownKit = StaticKit(); TownSmoke = [];
  const T = SITES.town;
  // contact grounding under the cottages: trodden earth at the walls and a soft occlusion skirt (foundation 5.6 x 4.8)
  for (const [hx, hz, hr, hs] of [[T.x - 13, T.z - 3, Math.PI / 2, 1], [T.x + 13, T.z - 4, -Math.PI / 2, 0.95], [T.x - 12, T.z + 11, Math.PI * 0.85, 0.9], [T.x + 12, T.z + 10, -Math.PI * 0.85, 0.9], [T.x + 10, T.z - 15, -Math.PI * 0.2, 0.85]]) {
    groundStamp(hx, hz, 2.8 * hs + 2.6, { dirt: 0.75 }, { rz: 2.4 * hs + 2.4, rot: hr, soft: 0.6, noise: 0.5 });
    groundStamp(hx, hz, 2.8 * hs + 1.3, { dark: 0.6 }, { rz: 2.4 * hs + 1.3, rot: hr, soft: 0.4, noise: 0.2 });
  }
  house(scene, T.x - 13, T.z - 3, Math.PI / 2, 0xf3e6d2, 0x4e5aa8, 1, { crystal: true, shutter: 0x3f6aa8 });
  house(scene, T.x + 13, T.z - 4, -Math.PI / 2, 0xf0dcc8, 0xc4584a, 0.95, { shutter: 0x4f7a5a });
  house(scene, T.x - 12, T.z + 11, Math.PI * 0.85, 0xe8e0d0, 0x4f8a5a, 0.9, { shutter: 0x9a5a3a });
  house(scene, T.x + 12, T.z + 10, -Math.PI * 0.85, 0xf3e6d2, 0x8a5aa8, 0.9, { shutter: 0x3f6aa8 });
  house(scene, T.x + 10, T.z - 15, -Math.PI * 0.2, 0xe8e0d0, 0xc4584a, 0.85, { shutter: 0x4f7a5a });
  const { f, cr } = buildFountain(scene);
  World.spinners.push(cr); World.fountainCrystal = cr; World.fountain = f;
  buildPlaza(scene);
  // lanterns along the paths
  for (const P of PATHS) for (let i = 0; i < P.length - 1; i++) {
    const [ax, az] = P[i], [bx, bz] = P[i + 1], L = Math.hypot(bx - ax, bz - az), n = Math.floor(L / 13);
    for (let k = 1; k <= n; k++) {
      const t = k / (n + 1), x = lerp(ax, bx, t), z = lerp(az, bz, t), nx = -(bz - az) / L, nz = (bx - ax) / L, side = k % 2 ? 1 : -1;
      const lx = x + nx * 3 * side, lz = z + nz * 3 * side;
      if (Math.hypot(lx - T.x, lz - T.z) < 14) continue;
      lantern(scene, lx, lz);
      groundStamp(lx, lz, 1.0, { dark: 0.5, dirt: 0.35 }, { soft: 0.75 });
    }
  }
  buildTownExtras(scene, TownKit);    // 03b_town.js: extra village props merged into the same kit
  TownKit.build(scene);
  World.smoke = buildSmoke(scene, TownSmoke);
  // starter pedestals
  World.pedestals = [];
  [[-3.4, 57.6], [0, 58.4], [3.4, 57.6]].forEach(([x, z], i) => {
    const y = groundY(x, z);
    groundStamp(x, z, 1.6, { dark: 0.55, dirt: 0.5 }, { soft: 0.6 });
    const g = grp(scene, [x, y, z]);
    part(GEO.cyl, M(0xcfc6b6), g, [0, 0.25, 0], [0.85, 0.5, 0.85]);
    part(GEO.torus, E([0xff8a4c, 0x5cb8ff, 0x6fdc78][i], 2.2), g, [0, 0.51, 0], [0.8, 0.8, 1], [Math.PI / 2, 0, 0]);
    g.traverse((o) => { if (o.isMesh && !o.material.isMeshBasicMaterial) { o.castShadow = true; o.receiveShadow = true; } });
    World.colliders.push({ x, z, r: 0.9 });
    World.pedestals.push({ x, z, y: y + 0.52, g, rig: null, sp: STARTERS[i] });
  });
}

// ---------------- the altar of origin
function buildAltar(scene) {
  const A = SITES.altar, y = groundY(A.x, A.z);
  groundStamp(A.x, A.z, 9.7, { dark: 0.55 }, { soft: 0.16, noise: 0.08 });
  for (let i = 0; i < 8; i++) { const a = (i / 8) * Math.PI * 2 + 0.2; groundStamp(A.x + Math.cos(a) * 7.2, A.z + Math.sin(a) * 7.2, 1.6, { dark: 0.6 }, { soft: 0.6 }); }
  const g = grp(scene, [A.x, y, A.z]);
  const ST = M(0x9a94ab), ST2 = M(0x7f7992);
  part(GEO.cyl, ST, g, [0, 0.2, 0], [8.4, 0.6, 8.4]);
  part(GEO.cyl, ST2, g, [0, 0.62, 0], [5.8, 0.5, 5.8]);
  part(GEO.cyl, ST, g, [0, 1.25, 0], [1.1, 1.3, 1.1]);
  const runes = part(GEO.ring, E(0x9b6bff, 1.6), g, [0, 0.88, 0], [5.2, 5.2, 3], [Math.PI / 2, 0, 0]);
  const runes2 = part(GEO.ring, E(0x9b6bff, 1.3), g, [0, 0.51, 0], [7.6, 7.6, 3], [Math.PI / 2, 0, 0]);
  World.altarRunes = [runes, runes2];
  World.sockets = [];
  for (let i = 0; i < 3; i++) {
    const a = (i / 3) * Math.PI * 2 + Math.PI / 2;
    const s = part(GEO.sphere, M(0x2a2238), g, [Math.cos(a) * 0.55, 2.0, Math.sin(a) * 0.55], 0.2);
    World.sockets.push(s);
  }
  for (let i = 0; i < 8; i++) {
    const a = (i / 8) * Math.PI * 2 + 0.2, broken = i % 3 === 1;
    const h = broken ? 2.2 : 5.2;
    const cx = Math.cos(a) * 7.2, cz = Math.sin(a) * 7.2, COL = texMat('plaster', 0xcfc8de);
    part(flutedColumnGeo(), COL, g, [cx, h / 2 + 0.4, cz], [0.5, h, 0.5]).receiveShadow = true;
    part(GEO.box, ST2, g, [cx, 0.6, cz], [1.3, 0.4, 1.3], [0, -a, 0]);
    part(GEO.torusFat, ST, g, [cx, 0.86, cz], [0.5, 0.5, 0.42], [Math.PI / 2, 0, 0]);
    if (!broken) {
      part(GEO.torusFat, ST, g, [cx, h + 0.22, cz], [0.47, 0.47, 0.36], [Math.PI / 2, 0, 0]);
      part(new THREE.CylinderGeometry(1, 0.62, 1, 24), ST, g, [cx, h + 0.36, cz], [0.62, 0.3, 0.62]);
      part(GEO.box, ST2, g, [cx, h + 0.62, cz], [1.25, 0.24, 1.25], [0, -a, 0]);
    } else {
      // jagged break and a levitating drum held by the rift
      part(GEO.cone6, ST, g, [cx, h + 0.55, cz], [0.42, 0.5, 0.42], [0.2, a, 0.1]);
      part(flutedColumnGeo(), COL, g, [cx, h + 2.2, cz], [0.5, 1.2, 0.5], [0.3, 0, 0.2]);
    }
    World.colliders.push({ x: A.x + Math.cos(a) * 7.2, z: A.z + Math.sin(a) * 7.2, r: 0.75 });
  }
  World.colliders.push({ x: A.x, z: A.z, r: 1.4 });
  const fl = grp(g, [0, 0, 0]);
  for (let i = 0; i < 7; i++) {
    const a = (i / 7) * Math.PI * 2, R = 10 + (i % 3) * 2;
    const rk = grp(fl, [Math.cos(a) * R, 5 + (i % 3) * 2.5, Math.sin(a) * R]);
    part(rockGeometry(i), rockMaterial(), rk, [0, 0, 0], [1.1, 0.95, 1.0], [Math.PI, i, 0]);
    part(GEO.cone6, E(0xb48cff, 1.8), rk, [0, -0.7, 0], [0.18, 0.7, 0.18], [Math.PI, 0, 0]);
    rk.userData.ph = i;
  }
  World.floaters = fl;
  const beam = new THREE.Mesh(new THREE.CylinderGeometry(1.4, 2.2, 120, 24, 1, true), new THREE.MeshBasicMaterial({ color: new THREE.Color(3, 2.5, 1.4), transparent: true, opacity: 0, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide }));
  beam.position.set(0, 60, 0); g.add(beam); World.altarBeam = beam;
  g.traverse((o) => { if (o.isMesh && o.material.isMeshToonMaterial) { o.castShadow = true; o.receiveShadow = true; } });
  World.altar = g; World.altarY = y;
  const pl = new THREE.PointLight(0xb48cff, 26, 22, 1.5); pl.position.set(A.x, y + 3, A.z); scene.add(pl); World.altarLight = pl;
}

// ---------------- void rifts
function buildRift(scene, R) {
  const y = groundY(R.x, R.z);
  groundStamp(R.x, R.z, 3.4, { dark: 0.45 }, { soft: 0.7 });
  const g = grp(scene, [R.x, y, R.z]);
  const U = { uTime: Shared.time, uOpen: { value: 1 } };
  const tear = new THREE.Mesh(new THREE.PlaneGeometry(5.2, 9), new THREE.ShaderMaterial({
    uniforms: U, transparent: true, depthWrite: false, side: THREE.DoubleSide,
    vertexShader: `varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }`,
    fragmentShader: `uniform float uTime, uOpen; varying vec2 vUv;
      ${GLSL_NOISE}
      void main(){
        vec2 p = vUv * 2.0 - 1.0;
        float jag = (vnoise(vec2(p.y * 6.0, uTime * 0.4)) - 0.5) * 0.32 + (vnoise(vec2(p.y * 17.0, 3.0)) - 0.5) * 0.14;
        float halfW = 0.36 * (1.0 - pow(abs(p.y), 1.7)) * uOpen;
        float d = abs(p.x - jag * 0.6) - halfW;
        if (d > 0.5 || uOpen < 0.01) discard;
        float edge = exp(-max(d, 0.0) * 13.0);
        vec2 sw = vec2(p.x * 3.0 + sin(p.y * 4.0 + uTime) * 0.6, p.y * 3.0 - uTime * 0.6);
        vec3 inside = vec3(0.01, 0.0, 0.03) + vec3(0.32, 0.06, 0.6) * pow(vnoise(sw * 2.0), 3.0) + vec3(0.9, 0.3, 1.5) * pow(vnoise(sw * 5.0 + 10.0), 8.0);
        vec3 col; float a;
        if (d < 0.0) { col = inside + vec3(1.0, 0.35, 2.0) * smoothstep(-0.07, 0.0, d) * 2.4; a = 1.0; }
        else { col = vec3(1.1, 0.3, 2.2) * edge * 2.2; a = edge * (1.0 - smoothstep(0.7, 1.0, abs(p.y))); }
        gl_FragColor = vec4(col, a);
      }`,
  }));
  tear.position.y = 4.4; g.add(tear);
  const shards = grp(g, [0, 4.2, 0]);
  for (let i = 0; i < 9; i++) {
    const a = (i / 9) * Math.PI * 2, rr = 2.8 + (i % 3) * 0.6;
    const s = part(GEO.octa, voidMat(0xb055ff, 2.2), shards, [Math.cos(a) * rr, Math.sin(a * 2) * 2, Math.sin(a) * rr], [0.16, 0.38, 0.16], [a, 0, a * 0.5]);
    s.userData.ph = i;
  }
  // inward particles
  const n = 160, pos = new Float32Array(n * 3), ph = new Float32Array(n);
  for (let i = 0; i < n; i++) { const a = Math.random() * Math.PI * 2, el = rand(-1, 1), rr = rand(5, 9); pos[i * 3] = Math.cos(a) * rr; pos[i * 3 + 1] = el * 5; pos[i * 3 + 2] = Math.sin(a) * rr; ph[i] = Math.random(); }
  const pg = new THREE.BufferGeometry(); pg.setAttribute('position', new THREE.BufferAttribute(pos, 3)); pg.setAttribute('ph', new THREE.BufferAttribute(ph, 1));
  const pU = { uTime: Shared.time, uTex: { value: TEX.dot }, uOpen: U.uOpen };
  const pts = new THREE.Points(pg, new THREE.ShaderMaterial({
    uniforms: pU, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
    vertexShader: `attribute float ph; uniform float uTime, uOpen; varying float vA; void main(){ float k = fract(uTime * 0.28 + ph); vec3 p = mix(position, vec3(0.0), k * k);
      vA = sin(k * 3.14159) * uOpen; vec4 mv = modelViewMatrix * vec4(p, 1.0); gl_PointSize = 90.0 * (0.5 + ph) / -mv.z; gl_Position = projectionMatrix * mv; }`,
    fragmentShader: `uniform sampler2D uTex; varying float vA; void main(){ float a = texture2D(uTex, gl_PointCoord).a * vA; gl_FragColor = vec4(vec3(0.85, 0.3, 1.6) * a * 1.8, 1.0); }`,
  }));
  pts.position.y = 4.4; pts.frustumCulled = false; g.add(pts);
  const light = new THREE.PointLight(0xb055ff, 40, 24, 1.4); light.position.y = 4; g.add(light);
  const bloom = grp(g, [0, 0, 0]); bloom.visible = false;
  part(GEO.cyl, M(0xcfc6b6), bloom, [0, 0.2, 0], [0.9, 0.4, 0.9]);
  const bc = part(GEO.octa, E(0xffd98a, 3), bloom, [0, 1.6, 0], [0.35, 0.6, 0.35]);
  World.colliders.push({ x: R.x, z: R.z, r: 2.4 });
  World.rifts[R.id] = { R, g, tear, U, shards, pts, light, bloom, bc, open: 1 };
}

function placeRiftState() {
  for (const r of SITES.rifts) {
    const o = World.rifts[r.id], closed = !!S.flags['closed_' + r.id];
    o.open = closed ? 0 : 1; o.U.uOpen.value = o.open;
    o.tear.visible = o.pts.visible = o.shards.visible = !closed; o.light.intensity = closed ? 0 : 40; o.bloom.visible = closed;
  }
  for (let i = 0; i < 3; i++) World.sockets[i].material = i < fragCount() ? E(0xffd98a, 3) : M(0x2a2238);
  const done = !!S.flags.ending;
  World.altarRunes.forEach((r) => (r.material = (fragCount() >= 3 || done) ? E(0xffd27a, 1.5) : E(0x9b6bff, 1.6)));
  World.altarLight.color.setHex(fragCount() >= 3 || done ? 0xffd27a : 0xb48cff);
  World.healTarget = S.flags.awakened && !done ? 0.35 : fragCount() / 3; World.heal = World.healTarget;
  World.dawnTarget = done ? 1 : 0; World.dawn = World.dawnTarget;
  recolorTerrain(true);
  refreshWorldEnv();
}
function fragCount() { return SITES.rifts.reduce((s, r) => s + (S.flags['closed_' + r.id] ? 1 : 0), 0); }

// ---------------- atmosphere: lerp between corrupted dusk, healed sunset, and dawn
const ATMOS = {
  dark:  { top: 0x1a2550, mid: 0x5462a0, hor: 0xffad78, fog: 0x8f8fa8, sun: 0xffcf9a, hemiS: 0xb4c0dc, hemiG: 0x7a6440, sea: 0x7fa0cc, cloud: 0xffcfb0, sunI: 3.3, stars: 0.75 },
  heal:  { top: 0x23407e, mid: 0x6d8cc8, hor: 0xffc48c, fog: 0xa8b0c4, sun: 0xffdcb0, hemiS: 0xc4d0ec, hemiG: 0x7a6644, sea: 0x8fb4dc, cloud: 0xffdcc0, sunI: 3.5, stars: 0.5 },
  dawn:  { top: 0x3274c0, mid: 0x9cc0ec, hor: 0xffe0b4, fog: 0xc8d4e8, sun: 0xfff0d8, hemiS: 0xdce8ff, hemiG: 0x7a6a50, sea: 0xa8d0f4, cloud: 0xffffff, sunI: 3.7, stars: 0 },
};
function applyAtmos() {
  const W = World, a = ATMOS.dark, b = ATMOS.heal, d = ATMOS.dawn, h = W.heal, k = W.dawn;
  const mix = (key) => new THREE.Color(a[key]).lerp(new THREE.Color(b[key]), h).lerp(new THREE.Color(d[key]), k);
  const num = (key) => lerp(lerp(a[key], b[key], h), d[key], k);
  W.skyU.uTop.value.copy(mix('top')); W.skyU.uMid.value.copy(mix('mid')); W.skyU.uHor.value.copy(mix('hor'));
  W.skyU.uStars.value = num('stars');
  const fogC = mix('fog'), sunC = mix('sun');
  W.scene.fog.color.copy(fogC);
  W.skyU.uFogCol.value.copy(fogC);
  W.skyU.uSunCol.value.copy(sunC);
  W.skyU.uFogSun.value.copy(mix('hor')).lerp(sunC, 0.35);
  const fs = W.skyU.uFogSun.value; FogAtmo.sun.r = fs.r; FogAtmo.sun.g = fs.g; FogAtmo.sun.b = fs.b;
  W.sun.color.copy(sunC); W.sun.intensity = num('sunI');
  W.hemi.color.copy(mix('hemiS')); W.hemi.groundColor.copy(mix('hemiG'));
  W.waterU.uSky.value.copy(mix('sea'));
  const cc = mix('cloud'); for (const c of W.sky.userData.clouds) c.material.color.copy(cc);
  if (!W.crackOverride) W.skyU.uCrack.value = S.flags.ending ? 0 : S.flags.awakened ? 2.2 : (1 - h * 0.65);
  const sd = W.sunDir.clone(); sd.y = lerp(0.32, 0.5, k); sd.normalize(); W.skyU.uSunDir.value.copy(sd);
  FogAtmo.dir.x = sd.x; FogAtmo.dir.y = sd.y; FogAtmo.dir.z = sd.z;
}

// ---------------- markers (floating diamonds over objectives)
function buildMarker(color) {
  const g = new THREE.Group();
  part(GEO.octa, E(color, 2.6), g, [0, 0, 0], [0.5, 0.9, 0.5]);
  part(GEO.torus, E(color, 1.8), g, [0, 0, 0], [0.9, 0.9, 1], [Math.PI / 2, 0, 0]);
  World.scene.add(g); return g;
}
function refreshMarkers() {
  for (const m of World.markers) World.scene.remove(m.g);
  World.markers = [];
  const add = (x, z, y, color, label) => { const g = buildMarker(color); g.position.set(x, y, z); World.markers.push({ g, y, x, z, color, label }); };
  if (!S.party.length) { add(0, 55, groundY(0, 55) + 4.2, 0xffd98a, '장로 무연'); return; }
  for (const r of SITES.rifts) if (!S.flags['closed_' + r.id]) add(r.x, r.z, groundY(r.x, r.z) + 12, 0xc77dff, r.name);
  if (fragCount() >= 3 && !S.flags.ending) add(SITES.altar.x, SITES.altar.z, World.altarY + 9, 0xffd98a, '근원의 제단');
  const LC = { asterion: 0x8fe0ff, abyssea: 0x4ff0ff, danha: 0xffa860, limina: 0xffffff };
  for (const sp in LC) if (legendPresent(sp)) { const st = World.legendSites[sp]; add(st.x, st.z, st.y + 9, LC[sp], st.name); }
}

// ---------------- camera
function snapCamera() {
  const W = World, p = W.player.root.position;
  const d = W.camDist, h = d * 0.5 + 1.5;
  W.camPos.set(p.x + Math.sin(W.camYaw) * d, p.y + h, p.z + Math.cos(W.camYaw) * d);
  W.camLook.set(p.x, p.y + 1.3, p.z);
  W.camera.position.copy(W.camPos); W.camera.lookAt(W.camLook);
}

function updateWorld(dt, controllable) {
  const W = World; W.t += dt;
  const P = W.player;
  let moving = 0;
  if (controllable) {
    const ax = Input.axis();
    W.camYaw -= Input.dragDX * 0.006; Input.dragDX = 0;
    W.camDist = clamp(W.camDist + Input.zoom, 6.5, 19); Input.zoom = 0;
    if (Input.keys.KeyQ) W.camYaw += dt * 1.8; if (Input.keys.KeyR) W.camYaw -= dt * 1.8;
    const mag = Math.hypot(ax.x, ax.y);
    W.sprint = !!ax.run && mag > 0.5;
    if (mag > 0.08) {
      const fx = -Math.sin(W.camYaw), fz = -Math.cos(W.camYaw), rx = Math.cos(W.camYaw), rz = -Math.sin(W.camYaw);
      let dx = rx * ax.x + fx * ax.y, dz = rz * ax.x + fz * ax.y; const l = Math.hypot(dx, dz); dx /= l; dz /= l;
      const sp = (ax.run ? 10.5 : 6) * Math.min(1, mag);
      const p = P.root.position, ox = p.x, oz = p.z;
      const [nx, nz] = tryMove(p.x, p.z, dx * sp * dt, dz * sp * dt);
      p.x = nx; p.z = nz;
      const moved = Math.hypot(nx - ox, nz - oz);
      P.root.rotation.y = dampAngle(P.root.rotation.y, Math.atan2(dx, dz), 14, dt);
      moving = clamp(moved / dt / 6, 0, 1.4);
      W.stepAcc = (W.stepAcc || 0) + moved;
      if (W.stepAcc > (ax.run ? 2.4 : 1.7)) {
        W.stepAcc = 0;
        // footstep surface: cobbles on the plaza, rustle in the tall grass, soft earth elsewhere
        const onPlaza = Math.hypot(p.x - SITES.town.x, p.z - SITES.town.z) < 9.6;
        const inGrass = !onPlaza && ZONES.some((zn) => Math.hypot(p.x - zn.x, p.z - zn.z) < zn.r);
        Snd.fx(onPlaza ? 'stepStone' : inGrass ? 'stepGrass' : 'step');
        if (ax.run && mag > 0.5) W.dust.emit(p, 3, { speed: 0.9, size: 0.55, life: 0.8, spread: 0.2, vx: -dx * 1.2, vz: -dz * 1.2, up: 0.5, alpha: 0.42 });
      }
      onPlayerMoved(moved);
    }
  } else { Input.dragDX = 0; Input.zoom = 0; }
  P.moving = damp(P.moving, moving, 10, dt);
  // speed feel: the lens widens a touch while sprinting
  const fovT = 52 + (W.sprint && moving > 0.8 ? 5 : 0);
  if (Math.abs(W.camera.fov - fovT) > 0.01) { W.camera.fov = damp(W.camera.fov, fovT, 3.5, dt); W.camera.updateProjectionMatrix(); }
  P.root.position.y = damp(P.root.position.y, groundY(P.root.position.x, P.root.position.z), 20, dt);
  rigUpdate(P, dt);

  // follower spirit
  const F = W.follower;
  if (F) {
    const p = P.root.position, back = P.root.rotation.y + Math.PI;
    const tx = p.x + Math.sin(back) * 1.9 + Math.cos(back) * 0.9, tz = p.z + Math.cos(back) * 1.9 - Math.sin(back) * 0.9;
    const fp = F.root.position, dx = tx - fp.x, dz = tz - fp.z, dist = Math.hypot(dx, dz);
    if (dist > 12) { fp.x = tx; fp.z = tz; }
    const k = dist > 0.25 ? 1 : 0;
    fp.x = damp(fp.x, tx, 4.5, dt); fp.z = damp(fp.z, tz, 4.5, dt);
    fp.y = damp(fp.y, groundY(fp.x, fp.z), 12, dt);
    if (dist > 0.3) F.root.rotation.y = dampAngle(F.root.rotation.y, Math.atan2(dx, dz), 8, dt);
    else F.root.rotation.y = dampAngle(F.root.rotation.y, Math.atan2(p.x - fp.x, p.z - fp.z), 3, dt);
    F.moving = damp(F.moving, k * clamp(dist / 2, 0, 1), 8, dt);
    rigUpdate(F, dt);
  }
  // npcs
  for (const n of W.npcs) {
    const p = P.root.position, np = n.rig.root.position, d = Math.hypot(p.x - np.x, p.z - np.z);
    const want = d < 7 ? Math.atan2(p.x - np.x, p.z - np.z) : n.face;
    n.rig.root.rotation.y = dampAngle(n.rig.root.rotation.y, want, 4, dt);
    rigUpdate(n.rig, dt);
    if (n.pet) { n.pet.root.rotation.y = dampAngle(n.pet.root.rotation.y, want, 3, dt); rigUpdate(n.pet, dt); }
  }
  for (const pd of W.pedestals) if (pd.rig) { rigUpdate(pd.rig, dt); if (!pd.chosen) pd.rig.root.rotation.y = dampAngle(pd.rig.root.rotation.y, Math.atan2(P.root.position.x - pd.x, P.root.position.z - pd.z), 3, dt); }
  if (W.extraRigs) for (const r of W.extraRigs) rigUpdate(r, dt);

  // props
  for (const s of W.spinners) s.rotation.y += dt * 1.2;
  if (W.fountainCrystal) W.fountainCrystal.position.y = 2.9 + Math.sin(W.t * 2) * 0.15;
  for (const id in W.rifts) {
    const o = W.rifts[id];
    o.tear.rotation.y = Math.atan2(W.camera.position.x - o.g.position.x, W.camera.position.z - o.g.position.z);
    o.shards.rotation.y += dt * 0.4;
    for (const s of o.shards.children) { s.rotation.x += dt; s.position.y = Math.sin(W.t * 1.2 + s.userData.ph) * 2; }
    o.light.intensity = o.open * (36 + Math.sin(W.t * 5) * 6);
    if (o.bloom.visible) { o.bc.rotation.y += dt * 1.5; o.bc.position.y = 1.6 + Math.sin(W.t * 2) * 0.12; }
  }
  if (W.floaters) { W.floaters.rotation.y += dt * 0.08; for (const c of W.floaters.children) c.position.y = 5 + (c.userData.ph % 3) * 2.5 + Math.sin(W.t * 0.8 + c.userData.ph) * 0.6; }
  for (const m of W.markers) { m.g.position.y = m.y + Math.sin(W.t * 2) * 0.4; m.g.rotation.y += dt * 1.5; }
  updateWorldLegends(dt);
  W.grass.U.uPlayer.value.copy(P.root.position);
  W.heal = damp(W.heal, W.healTarget, 1.2, dt); W.dawn = damp(W.dawn, W.dawnTarget, 0.6, dt);
  if (Ground.U) Ground.U.uRift.value.forEach((v, i) => { v.z = damp(v.z, Ground.riftT[i], 0.45, dt); });
  applyAtmos();
  W.fx.update(dt); W.dust.update(dt);
  updateNatureExtras(dt);             // 03c_nature.js
  updateTownExtras(dt);               // 03b_town.js

  // camera
  const p = P.root.position;
  if (W.cine) {
    W.camPos.lerp(W.cine.pos, 1 - Math.exp(-(W.cine.k || 2.5) * dt));
    W.camLook.lerp(W.cine.look, 1 - Math.exp(-(W.cine.k || 2.5) * dt));
  } else {
    const d = W.camDist, h = d * 0.48 + 1.4;
    const want = new THREE.Vector3(p.x + Math.sin(W.camYaw) * d, p.y + h, p.z + Math.cos(W.camYaw) * d);
    const gy = groundY(want.x, want.z) + 1.2; if (want.y < gy) want.y = gy;
    W.camPos.lerp(want, 1 - Math.exp(-7 * dt));
    W.camLook.lerp(new THREE.Vector3(p.x, p.y + 1.3, p.z), 1 - Math.exp(-10 * dt));
  }
  W.camera.position.copy(W.camPos); W.camera.lookAt(W.camLook);
  if (W.shake > 0) { W.shake = Math.max(0, W.shake - dt); const s = W.shake * 0.5; W.camera.position.x += rand(-s, s); W.camera.position.y += rand(-s, s); }
  W.sky.position.copy(W.camera.position);
  sunShafts(W.camera, W.skyU.uSunDir.value, 0.8);
  W.sun.position.copy(p).addScaledVector(W.skyU.uSunDir.value, 70); W.sun.target.position.copy(p);
}

function walkable(x, z) { return groundY(x, z) > 0.3 && Math.hypot(x, z) < 140; }
function tryMove(px, pz, dx, dz) {
  let nx = px + dx, nz = pz + dz;
  if (!walkable(nx, nz)) {
    if (walkable(px + dx, pz)) nz = pz; else if (walkable(px, pz + dz)) nx = px; else return [px, pz];
  }
  for (const c of World.colliders) {
    const ddx = nx - c.x, ddz = nz - c.z; if (Math.abs(ddx) > c.r + 1 || Math.abs(ddz) > c.r + 1) continue;
    const d = Math.hypot(ddx, ddz), R = c.r + 0.38;
    if (d < R && d > 1e-4) { nx = c.x + ddx / d * R; nz = c.z + ddz / d * R; }
  }
  if (!walkable(nx, nz)) return [px, pz];
  return [nx, nz];
}
function zoneAt(x, z) { for (const zz of ZONES) if (Math.hypot(x - zz.x, z - zz.z) < zz.r * 0.92) return zz; return null; }

function setFollower(sp) {
  const W = World;
  if (W.follower) disposeRig(W.follower);
  W.follower = null;
  if (!sp) return;
  const r = makeSpiritModel(sp);
  const sc = SPECIES[sp].legend ? 0.42 : 0.8;
  r.root.scale.setScalar(sc);
  const p = W.player.root.position;
  r.root.position.set(p.x + 1.5, p.y, p.z + 1.5);
  W.scene.add(r.root); W.follower = r;
}
function addNpc(def) {
  const rig = buildPerson(def.look);
  const y = groundY(def.x, def.z);
  rig.root.position.set(def.x, y, def.z); rig.root.rotation.y = def.face || 0;
  World.scene.add(rig.root);
  const n = Object.assign({ rig, face: def.face || 0 }, def);
  if (def.pet) {
    n.pet = makeSpiritModel(def.pet); n.pet.root.scale.setScalar(0.7);
    const px = def.x + Math.cos(def.face || 0) * 1.3, pz = def.z - Math.sin(def.face || 0) * 1.3;
    n.pet.root.position.set(px, groundY(px, pz), pz); World.scene.add(n.pet.root);
  }
  World.npcs.push(n);
  World.colliders.push({ x: def.x, z: def.z, r: 0.5 });
  return n;
}

// ---------------- legend sites: where the four new legends live in the overworld
function findShore(x0, z0, dx, dz) {
  const l = Math.hypot(dx, dz); dx /= l; dz /= l;
  let x = x0, z = z0;
  for (let i = 0; i < 240; i++) { if (groundY(x, z) < 0.45) break; x += dx * 0.5; z += dz * 0.5; }
  return { x, z, dx, dz };
}
function peakNear(cx, cz, R = 8) {
  let best = { x: cx, z: cz, y: groundY(cx, cz) };
  for (let a = 0; a < 24; a++) for (let r = 0; r <= R; r += 1) {
    const x = cx + Math.cos(a / 24 * Math.PI * 2) * r, z = cz + Math.sin(a / 24 * Math.PI * 2) * r, y = groundY(x, z);
    if (y > best.y) best = { x, z, y };
  }
  return best;
}
function sunShafts(cam, dir, strength) {
  const p = cam.position.clone().addScaledVector(dir, 500).project(cam);
  const fwd = new THREE.Vector3(); cam.getWorldDirection(fwd);
  const facing = fwd.dot(dir);
  let s = strength * smooth(0.05, 0.45, facing);
  const off = Math.max(Math.abs(p.x), Math.abs(p.y));
  s *= 1 - smooth(1.0, 1.6, off);
  Post.U.uSun.value.set((p.x + 1) / 2, (p.y + 1) / 2, Settings.high ? s : 0);
}
function buildLegendSites() {
  const W = World;
  const pk = peakNear(38, -36, 9);
  const west = findShore(SITES.rifts[1].x, SITES.rifts[1].z, -1, 0.05);
  const south = findShore(0, 62, 0, 1);
  const hill = peakNear(62, 40, 8);
  W.legendSites = {
    asterion: { x: pk.x, z: pk.z, y: pk.y, name: '별빛 봉우리' },
    abyssea: { x: west.x + 4.5, z: west.z, y: groundY(west.x + 4.5, west.z), name: '고래울음 바위', sea: { x: west.x - 24, z: west.z, tx: 0, tz: 1 }, close: { x: west.x - 8, z: west.z } },
    danha: { x: hill.x, z: hill.z, y: hill.y, name: '해돋이 언덕' },
    limina: { x: south.x, z: south.z - 4, y: groundY(south.x, south.z - 4), name: '경계의 모래톱', sea: { x: south.x, z: south.z + 22 } },
  };
  // the dawn shrine stone on the sunrise hill
  groundStamp(hill.x, hill.z, 2.2, { dark: 0.55, dirt: 0.6 }, { soft: 0.6 });
  const sh = grp(W.scene, [hill.x, hill.y, hill.z]);
  part(GEO.cyl, M(0xa8a2b8), sh, [0, 0.3, 0], [1.3, 0.6, 1.3]);
  part(GEO.box, M(0x8e88a0), sh, [0, 1.3, 0], [0.7, 1.6, 0.5]);
  W.dawnStone = part(GEO.octa, E(0xffa860, 2.2), sh, [0, 2.6, 0], [0.32, 0.55, 0.32]);
  W.colliders.push({ x: hill.x, z: hill.z, r: 1.2 });
  // the whale rock on the west cliff
  groundStamp(west.x + 6.5, west.z + 2.5, 3.6, { rock: 0.55, dirt: 0.4 }, { soft: 0.6 });
  groundStamp(west.x + 6.5, west.z + 2.5, 2.7, { dark: 0.6 }, { soft: 0.45 });
  const wr = grp(W.scene, [west.x + 6.5, groundY(west.x + 6.5, west.z + 2.5) - 0.12, west.z + 2.5]);
  part(rockGeometry(2), rockMaterial(), wr, [0, 0.35, 0], [2.0, 2.2, 1.5], [0, 0.6, 0]).receiveShadow = true;
  part(rockGeometry(4), rockMaterial(), wr, [0.9, 1.75, 0.2], [1.0, 1.2, 0.9], [0, 2.1, 0]).receiveShadow = true;
  part(GEO.cone6, E(0x5ff4ff, 1.6), wr, [-0.6, 2.0, 0.3], [0.15, 0.5, 0.15]);
  W.colliders.push({ x: west.x + 6.5, z: west.z + 2.5, r: 1.8 });
  W.legends = {};
}
function legendUnlocked(sp) {
  if (sp === 'asterion') return fragCount() >= 1;
  if (sp === 'abyssea') return fragCount() >= 2;
  if (sp === 'danha') return !!S.flags.ending;
  if (sp === 'limina') return !!(S.dex.caught.nihilos && S.dex.caught.ensia);
  return false;
}
function legendPresent(sp) { return legendUnlocked(sp) && !S.dex.caught[sp]; }
function refreshWorldLegends() {
  const W = World;
  for (const sp of ['asterion', 'abyssea', 'danha', 'limina']) {
    const want = legendPresent(sp), have = W.legends[sp];
    if (want && !have) {
      const site = W.legendSites[sp], r = makeSpiritModel(sp);
      const L = { sp, rig: r, site, mode: 'idle', t: Math.random() * 10 };
      if (sp === 'asterion') {
        r.root.scale.setScalar(0.8); r.root.position.set(site.x, site.y, site.z);
        r.root.rotation.y = Math.atan2(-site.x, -site.z);
        const beam = new THREE.Mesh(new THREE.CylinderGeometry(0.9, 1.6, 140, 20, 1, true), new THREE.MeshBasicMaterial({ color: new THREE.Color(0.6, 1.1, 1.6), transparent: true, opacity: 0.16, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide }));
        beam.position.set(site.x, site.y + 70, site.z); W.scene.add(beam); L.extra = [beam];
      }
      if (sp === 'abyssea') r.root.scale.setScalar(1.35);
      if (sp === 'danha') r.root.scale.setScalar(2.2);
      if (sp === 'limina') r.root.scale.setScalar(1.7);
      W.scene.add(r.root); W.legends[sp] = L;
    } else if (!want && have) {
      disposeRig(have.rig); for (const x of have.extra || []) W.scene.remove(x);
      delete W.legends[sp];
    }
  }
}
function updateWorldLegends(dt) {
  const W = World;
  for (const sp in W.legends) {
    const L = W.legends[sp], r = L.rig, s = L.site; L.t += dt;
    if (L.mode === 'idle') {
      if (sp === 'abyssea') {
        const T = 15, k = (L.t % T) / 4.5;
        if (k < 1) {
          r.root.visible = true;
          const ox = s.sea.x, oz = s.sea.z + lerp(-14, 14, k), y = -10 + Math.sin(k * Math.PI) * 13;
          const prevY = r.root.position.y;
          r.root.position.set(ox, y, oz); r.root.rotation.set(-Math.atan2(y - prevY, 28 * dt / 4.5 + 1e-4) * 0.6, 0, 0);
          if ((k > 0.14 && k < 0.2) || (k > 0.8 && k < 0.86)) W.fx.burst(new THREE.Vector3(ox, 0.3, oz), 6, { color: [0xdff8ff, 0x7fdcff], speed: 6, up: 4, grav: 9, size: 0.7, life: 1.1, drag: 0.5, intensity: 1.1 });
          if (k > 0.14 && k < 0.16 && !L.sang) { L.sang = true; if (Math.hypot(W.player.root.position.x - ox, W.player.root.position.z - oz) < 70) Snd.fx('whale'); }
        } else { r.root.visible = false; L.sang = false; }
      } else if (sp === 'danha') {
        const a = L.t * 0.11, R = 72;
        r.root.position.set(Math.cos(a) * R, 46 + Math.sin(a * 2) * 4, Math.sin(a) * R);
        r.root.rotation.set(0, Math.atan2(-Math.sin(a), Math.cos(a)), -0.35);
        if (Math.random() < 0.5) W.fx.emit({ x: r.root.position.x + rand(-2, 2), y: r.root.position.y + rand(1, 4), z: r.root.position.z + rand(-2, 2), vy: -rand(0.5, 2), color: [0xff8a3d, 0xffd25a][Math.random() < 0.5 ? 0 : 1], size: 1.1, life: 2.2, intensity: 1.4 });
      } else if (sp === 'limina') {
        const t = L.t * 0.28;
        const x = s.sea.x + Math.sin(t) * 16, z = s.sea.z + Math.sin(t * 2) * 6, y = 6 + Math.sin(t * 1.7) * 1.2;
        const nx = s.sea.x + Math.sin(t + 0.05) * 16, nz = s.sea.z + Math.sin((t + 0.05) * 2) * 6;
        r.root.position.set(x, y, z); r.root.rotation.set(0, Math.atan2(nx - x, nz - z), -Math.cos(t) * 0.3);
      }
    }
    rigUpdate(r, dt);
  }
  if (W.dawnStone) { W.dawnStone.rotation.y += dt; W.dawnStone.material = W.legends.danha ? E(0xffa860, 3) : E(0x8e88a0, 0.6); }
}
// title teaser: the boundary manta gliding over the island
function updateTitleRig(dt, on) {
  const W = World;
  if (on && !W.titleRig) { W.titleRig = makeSpiritModel('limina'); W.titleRig.root.scale.setScalar(2.6); W.scene.add(W.titleRig.root); W.titleT = 0; }
  if (!on && W.titleRig) { disposeRig(W.titleRig); W.titleRig = null; return; }
  if (!W.titleRig) return;
  W.titleT += dt;
  const a = W.titleT * 0.09 + 2.4, R = 46;
  const r = W.titleRig;
  r.root.position.set(Math.cos(a) * R, 30 + Math.sin(a * 2) * 3, Math.sin(a) * R - 8);
  r.root.rotation.set(0, Math.atan2(-Math.sin(a), Math.cos(a)), 0.32);
  rigUpdate(r, dt);
}

// reflections for PBR materials (the dragons) follow the current sky
function refreshWorldEnv() {
  applyAtmos();
  if (World.env) World.env.dispose();
  World.env = envFromSky(World.skyU); World.scene.environment = World.env.texture;
}
