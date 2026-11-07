// ============================================================================
//  nature kit shared by the island and the battle arenas.
//  Authored assets (tools/tex/vegetation_*.py, tools/blender/vegetation_*.py): Blender trees with branching trunks,
//  bark PBR and leaf-cluster cards (2 LODs), bushes, ferns, granite boulders and pebbles, and a ground-cover atlas
//  (lawn, wild grass, tussock, reeds, clover, plantain, moss, leaf litter, four flowering plants).
//  Every builder keeps the older procedural path as a fallback (file://, missing files).
// ============================================================================
registerAssets({
  textures: Object.assign({},
    ...['foliage', 'cover'].flatMap((n) => ['albedo', 'alpha', 'normal'].map((s) => ({ [`${n}_${s}`]: { file: `tex/vegetation/${n}_${s}.jpg`, lo: `tex/vegetation/${n}_${s}_512.jpg`, srgb: s === 'albedo' } }))),
    ...['bark_oak', 'bark_birch', 'bark_pine', 'rock_granite'].flatMap((n) => ['albedo', 'normal', 'orm'].map((s) => ({ [`${n}_${s}`]: { file: `tex/vegetation/${n}_${s}.jpg`, lo: `tex/vegetation/${n}_${s}_512.jpg`, srgb: s === 'albedo' } })))),
  models: { veg_trees: 'models/vegetation/trees.glb', veg_rocks: 'models/vegetation/rocks.glb' },
});

const Veg = {
  geo: null, mats: {}, forests: [], cover: [], pendingCover: null, trees: [], rocks: [], grid: null, t: 0,
  lodDist: 46, coverDist: 60,
  U: { uPlayer: { value: new THREE.Vector3(1e5, 0, 1e5) }, uFade: { value: new THREE.Vector2(44, 60) } },
};

// glTF meshes -> plain Float32 geometries (quantized normals / colours expanded), COLOR_0 renamed aVeg
// (R ambient occlusion, G sway weight, B phase, A leaf flutter), uv flipped to match flipY-loaded atlases.
function vegGeos() {
  if (Veg.geo) return Veg.geo;
  const G = {};
  for (const key of ['veg_trees', 'veg_rocks']) {
    const gl = assetGltf(key); if (!gl) continue;
    gl.scene.updateMatrixWorld(true);
    gl.scene.traverse((o) => {
      if (!o.isMesh) return;
      const src = o.geometry, g = new THREE.BufferGeometry();
      for (const name in src.attributes) {
        const a = src.attributes[name], n = a.count, s = a.itemSize, arr = new Float32Array(n * s);
        for (let i = 0; i < n; i++) {
          arr[i * s] = a.getX(i); if (s > 1) arr[i * s + 1] = a.getY(i); if (s > 2) arr[i * s + 2] = a.getZ(i); if (s > 3) arr[i * s + 3] = a.getW(i);
        }
        if (name === 'uv') for (let i = 0; i < n; i++) arr[i * 2 + 1] = 1 - arr[i * 2 + 1];
        g.setAttribute(name === 'color' ? 'aVeg' : name, new THREE.BufferAttribute(arr, s));
      }
      if (!g.attributes.aVeg) { const v = new Float32Array(g.attributes.position.count * 4); for (let i = 0; i < v.length; i += 4) { v[i] = 1; v[i + 2] = 0.5; } g.setAttribute('aVeg', new THREE.BufferAttribute(v, 4)); }
      if (src.index) g.setIndex(new THREE.BufferAttribute(src.index.array.slice(), 1));
      g.applyMatrix4(o.matrixWorld);
      g.computeBoundingBox(); g.computeBoundingSphere();
      G[o.name] = g;
    });
  }
  return (Veg.geo = G);
}
const vegHasTrees = () => !!(vegGeos().oak_a_wood && assetTex('foliage_albedo') && assetTex('foliage_alpha'));
const vegHasCover = () => !!(assetTex('cover_albedo') && assetTex('cover_alpha'));
const vegHasRocks = () => !!(vegGeos().rock_0 && pbrSet('rock_granite'));

// ---------------- shader patches: wind / AO / tint / translucency for trees, cover cards and rocks
//  kind: 'leaf' | 'wood' | 'depth' (leaf shadow caster) | 'cover' | 'rock'
function vegPatch(mat, kind, o = {}) {
  const U = { uWind: { value: o.wind ?? 1 }, uTrans: { value: o.trans ?? 1 }, uMoss: { value: o.moss ?? 0.8 } };
  mat.userData.vegU = U;
  const prev = mat.onBeforeCompile, prevKey = mat.customProgramCacheKey();
  const tree = kind === 'leaf' || kind === 'wood' || kind === 'depth';
  mat.onBeforeCompile = (sh, r) => {
    if (prev) prev(sh, r);
    Object.assign(sh.uniforms, U, { uTime: Shared.time, uPlayer: Veg.U.uPlayer, uFade: Veg.U.uFade });
    let v = sh.vertexShader, f = sh.fragmentShader;
    v = `attribute vec4 aVeg; varying float vAO; varying float vVegH; uniform float uTime, uWind; uniform vec3 uPlayer; uniform vec2 uFade;
      #ifdef VEG_TINT
        attribute vec4 aTint; varying vec4 vTint;
      #endif
      #ifdef VEG_RECT
        attribute vec4 aRect;
      #endif
      ` + v;
    if (tree) {
      v = v.replace('#include <begin_vertex>', `#include <begin_vertex>
        vAO = aVeg.r; vVegH = aVeg.g;
        #ifdef VEG_TINT
          vTint = aTint;
        #endif
        #ifdef USE_INSTANCING
          vec3 vegI = instanceMatrix[3].xyz;
        #else
          vec3 vegI = vec3(0.0);
        #endif
        float vegPh = aVeg.b * 6.2831 + vegI.x * 0.13 + vegI.z * 0.17;
        float vegG = 0.55 + 0.45 * sin(uTime * 0.37 + vegI.x * 0.021 + vegI.z * 0.017);
        float vegW = aVeg.g * aVeg.g;
        vec2 vegS = vec2(sin(uTime * 0.83 + vegI.x * 0.05) + 0.35 * sin(uTime * 1.9 + vegPh * 0.3), cos(uTime * 0.71 + vegI.z * 0.05)) * vegW * 0.12 * uWind * vegG;
        transformed.xz += vegS; transformed.y -= dot(vegS, vegS) * 0.6;
        transformed += vec3(sin(uTime * 2.3 + vegPh), sin(uTime * 1.9 + vegPh * 1.3) * 0.6, cos(uTime * 2.1 + vegPh)) * aVeg.g * 0.02 * uWind * vegG;
        #ifdef VEG_FLUTTER
          transformed += objectNormal * sin(uTime * 7.0 + vegPh * 3.0 + position.y * 3.0) * aVeg.a * 0.035 * uWind * (0.5 + vegG);
        #endif`);
    }
    if (kind === 'cover') {
      v = v.replace('#include <uv_vertex>', `#include <uv_vertex>
        #ifdef VEG_RECT
          #ifdef USE_MAP
            vMapUv = aRect.xy + vMapUv * aRect.zw;
          #endif
          #ifdef USE_ALPHAMAP
            vAlphaMapUv = aRect.xy + vAlphaMapUv * aRect.zw;
          #endif
          #ifdef USE_NORMALMAP
            vNormalMapUv = aRect.xy + vNormalMapUv * aRect.zw;
          #endif
        #endif`)
        .replace('#include <begin_vertex>', `#include <begin_vertex>
          vAO = aVeg.r; vVegH = aVeg.g;
          vec3 vegB = (modelMatrix * vec4(instanceMatrix[3].xyz, 1.0)).xyz;
          float vegF = 1.0 - smoothstep(uFade.x, uFade.y, distance(cameraPosition.xz, vegB.xz));
          transformed.y *= vegF; transformed.xz *= mix(0.35, 1.0, vegF);
          #ifdef VEG_TINT
            vTint = aTint;
          #endif`)
        .replace('#include <project_vertex>', `
          vec4 vegWp = modelMatrix * instanceMatrix * vec4(transformed, 1.0);
          {
            float k = aVeg.g * aTint.a, hgt = length(instanceMatrix[1].xyz);
            float gust = sin(uTime * 0.6 + vegB.x * 0.05 + vegB.z * 0.04) * 0.5 + 0.5;
            vec2 sway = vec2(sin(uTime * 1.6 + vegB.x * 0.3 + vegB.z * 0.22) * 0.13 + sin(uTime * 3.1 + vegB.x * 1.1 + aVeg.b * 6.0) * 0.04,
                             cos(uTime * 1.3 + vegB.z * 0.27) * 0.06) * (0.55 + gust * 0.9);
            vegWp.xz += sway * k * hgt;
            vec2 d = vegB.xz - uPlayer.xz; float dist = length(d);
            float push = (1.0 - smoothstep(0.0, 1.3, dist)) * k;
            vegWp.xz += normalize(d + 1e-4) * push * 0.55 * hgt; vegWp.y -= push * 0.3 * hgt;
          }
          vec4 mvPosition = viewMatrix * vegWp;
          gl_Position = projectionMatrix * mvPosition;`);
    }
    if (kind === 'rock') {
      v = 'varying float vRockY;\n' + v.replace('tpW = (modelMatrix * vec4(transformed, 1.0)).xyz; tpNw = normalize(mat3(modelMatrix) * objectNormal);', `
        #ifdef USE_INSTANCING
          tpW = (modelMatrix * instanceMatrix * vec4(transformed, 1.0)).xyz; tpNw = normalize(mat3(modelMatrix) * mat3(instanceMatrix) * objectNormal);
        #else
          tpW = (modelMatrix * vec4(transformed, 1.0)).xyz; tpNw = normalize(mat3(modelMatrix) * objectNormal);
        #endif`).replace('#include <begin_vertex>', '#include <begin_vertex>\n vAO = aVeg.r; vVegH = aVeg.g; vRockY = position.y;');
    }
    // ---- fragment
    f = `varying float vAO; varying float vVegH; uniform float uTrans, uMoss;
      #ifdef VEG_TINT
        varying vec4 vTint;
      #endif
      ` + (kind === 'rock' ? 'varying float vRockY;\n' : '') + f;
    if (kind === 'leaf' || kind === 'cover') {
      f = f.replace('#include <normal_fragment_begin>', THREE.ShaderChunk.normal_fragment_begin.replace('normal *= faceDirection;', ''))
        .replace('#include <color_fragment>', `#include <color_fragment>
          #ifdef VEG_TINT
            ${kind === 'leaf' ? '{ float l = dot(diffuseColor.rgb, vec3(0.3, 0.59, 0.11)); diffuseColor.rgb = mix(diffuseColor.rgb, l * vTint.rgb * 2.4, vTint.a); }' : 'diffuseColor.rgb *= vTint.rgb;'}
          #endif
          diffuseColor.rgb *= ${kind === 'leaf' ? '0.28 + 0.72 * vAO' : '0.66 + 0.34 * vAO'};`)
        .replace('#include <emissivemap_fragment>', `#include <emissivemap_fragment>
          #if NUM_DIR_LIGHTS > 0
          {
            vec3 vegL = directionalLights[0].direction, vegV = normalize(vViewPosition);
            float back = pow(max(dot(-vegV, vegL), 0.0), 3.0), thru = max(dot(-normal, vegL), 0.0);
            totalEmissiveRadiance += diffuseColor.rgb * directionalLights[0].color * (back * 0.5 + thru * 0.2) * uTrans * (0.25 + 0.75 * vAO);
          }
          #endif`);
    }
    if (kind === 'wood' || kind === 'rock') {
      f = f.replace('#include <aomap_fragment>', `#include <aomap_fragment>
        reflectedLight.indirectDiffuse *= vAO; reflectedLight.indirectSpecular *= vAO; reflectedLight.directDiffuse *= mix(1.0, vAO, ${kind === 'wood' ? '0.55' : '0.35'});`);
    }
    if (kind === 'rock') {
      f = f.replace('#include <color_fragment>', `{
          float up = normalize(tpNw).y;
          float moss = smoothstep(0.45, 0.82, up * 0.85 + (0.55 - tpOrm.b) * 0.55 + (vAO - 0.75) * 0.5) * uMoss;
          vec3 mossC = mix(vec3(0.075, 0.12, 0.03), vec3(0.2, 0.26, 0.07), tpAl.g * 1.4);
          diffuseColor.rgb = mix(diffuseColor.rgb, mossC, moss);
          diffuseColor.rgb *= 0.88 + 0.3 * (vVegH - 0.5);                                   // edge wear on ridges
          float soil = 1.0 - smoothstep(-0.2, 0.2, vRockY);                                 // soil splashed on the foot
          diffuseColor.rgb = mix(diffuseColor.rgb, diffuseColor.rgb * vec3(0.5, 0.42, 0.33), soil * 0.75);
        }
        #include <color_fragment>`);
    }
    sh.vertexShader = v; sh.fragmentShader = f;
  };
  mat.customProgramCacheKey = () => prevKey + '|veg:' + kind;
  mat.needsUpdate = true;
  return mat;
}

function vegMat(key, make) { return Veg.mats[key] || (Veg.mats[key] = make()); }
function vegLeafMat(species, o = {}) {
  return vegMat('leaf_' + species, () => {
    const a = assetTex('foliage_albedo'), al = assetTex('foliage_alpha'), n = assetTex('foliage_normal');
    const m = new THREE.MeshLambertMaterial({ map: a, alphaMap: al, normalMap: Settings.high ? n : null, normalScale: new THREE.Vector2(0.55, 0.55), alphaTest: 0.45, side: THREE.DoubleSide });
    m.defines = { VEG_TINT: 1, VEG_FLUTTER: 1 };
    aaAlphaTest(m, (a.image && a.image.width) || 1024, 0.45);
    return vegPatch(m, 'leaf', o);
  });
}
function vegLeafDepth(species, o = {}) {
  return vegMat('leafd_' + species, () => {
    const m = new THREE.MeshDepthMaterial({ depthPacking: THREE.RGBADepthPacking, alphaMap: assetTex('foliage_alpha'), alphaTest: 0.5 });
    return vegPatch(m, 'depth', o);
  });
}
function vegBarkMat(bark, o = {}) {
  return vegMat('bark_' + bark, () => {
    const set = pbrSet(bark);
    const m = new THREE.MeshStandardMaterial({ color: o.color ?? 0xffffff, roughness: 1, metalness: 0, envMapIntensity: 0.5 });
    if (set) { m.map = set.albedo; m.normalMap = set.normal; m.normalScale = new THREE.Vector2(1.1, 1.1); m.roughnessMap = set.orm; m.aoMap = set.orm; m.aoMapIntensity = 0.9; }
    else m.color.setHex(bark === 'bark_birch' ? 0xe6e0d4 : bark === 'bark_pine' ? 0x6a4030 : 0x5e5048);
    return vegPatch(m, 'wood', o);
  });
}
function vegCoverMat() {
  return vegMat('cover', () => {
    const a = assetTex('cover_albedo');
    const m = new THREE.MeshLambertMaterial({ map: a, alphaMap: assetTex('cover_alpha'), normalMap: Settings.high ? assetTex('cover_normal') : null, normalScale: new THREE.Vector2(0.4, 0.4), alphaTest: 0.42, side: THREE.DoubleSide });
    m.defines = { VEG_TINT: 1, VEG_RECT: 1 };
    aaAlphaTest(m, (a.image && a.image.width) || 1024, 0.42);
    vegPatch(m, 'cover', { trans: 0.7 });
    m.receiveShadow = true;
    return m;
  });
}
function vegRockMat(o = {}) {
  return vegMat('rock' + (o.key || ''), () => {
    const m = new THREE.MeshStandardMaterial({ color: o.color ?? 0xffffff, roughness: 1, metalness: 0, envMapIntensity: 0.55 });
    triplanarPBR(m, pbrSet('rock_granite'), o.scale ?? 0.42, { normalStrength: 1.25 });
    return vegPatch(m, 'rock', o);
  });
}

// shallow geometry clone sharing the vertex buffers (each InstancedMesh needs its own per-instance attributes)
function vegShare(geo) {
  const g = new THREE.BufferGeometry();
  for (const k in geo.attributes) g.setAttribute(k, geo.attributes[k]);
  g.setIndex(geo.index); g.boundingBox = geo.boundingBox; g.boundingSphere = geo.boundingSphere;
  return g;
}
// list: [{ m: Matrix4, tint?: [r,g,b,a], rect?: [u,v,du,dv], col?: Color }]
function vegInstanced(geo, mat, list, o = {}) {
  const g = vegShare(geo), n = list.length;
  const im = new THREE.InstancedMesh(g, mat, Math.max(1, n));
  const tint = new Float32Array(Math.max(1, n) * 4), rect = o.rect ? new Float32Array(Math.max(1, n) * 4) : null;
  const m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), e = new THREE.Euler(), v = new THREE.Vector3(), sc = new THREE.Vector3();
  list.forEach((it, i) => {
    const p = it.p;
    im.setMatrixAt(i, it.m || m4.compose(v.set(p[0], p[1], p[2]), q.setFromEuler(e.set(p[7] || 0, p[3], p[8] || 0, 'YXZ')), sc.set(p[4], p[5], p[6])));
    if (it.col) im.setColorAt(i, it.col);
    tint.set(it.tint || [1, 1, 1, 0], i * 4);
    if (rect) rect.set(it.rect || [0, 0, 1, 1], i * 4);
  });
  im.count = n;
  g.setAttribute('aTint', new THREE.InstancedBufferAttribute(tint, 4));
  if (rect) g.setAttribute('aRect', new THREE.InstancedBufferAttribute(rect, 4));
  im.instanceMatrix.needsUpdate = true; if (im.instanceColor) im.instanceColor.needsUpdate = true;
  if (n) im.computeBoundingSphere();
  im.castShadow = !!o.cast; im.receiveShadow = o.receive !== false;
  im.userData.noGroundAO = true;
  return im;
}

// ---------------- rocks: Blender granite boulders (triplanar PBR, baked AO, moss on top, soil on the foot);
// procedural noise-displaced icosphere as the fallback.  rockGeometry(i) / rockMaterial() are also used by the
// altar floaters, the whale rock and the battle plinths.
function rockGeometry(i) {
  i = ((i % 5) + 5) % 5;
  if (vegHasRocks()) return vegGeos()['rock_' + i];
  return rockGeometryProc(i);
}
function rockMaterial() {
  return vegHasRocks() ? vegRockMat() : rockMaterialProc();
}

// ---------------- rocks: noise-displaced icosphere, flat underside, moss on top
const _rockGeo = [];
function rockGeometryProc(i) {
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
function rockMaterialProc() {
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
      m4.compose(v.set(r.x, r.y, r.z), q.setFromEuler(e.set(r.tx || 0, r.r, r.tz || 0, 'YXZ')), sc.set(r.s, r.s * (r.sy || 1), r.s));
      im.setMatrixAt(i, m4);
      c.setHex(tint ?? 0xffffff).multiplyScalar(0.88 + ((i * 37) % 10) / 40); im.setColorAt(i, c);
    });
    im.castShadow = im.receiveShadow = true; im.userData.noGroundAO = true; parent.add(im); out.push(im);
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
// flowers: [{ x, y, z, h, col }] (procedural petal flowers)
function buildFlowerFieldProc(parent, flowers) {
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
// With the cover atlas, most spots become textured grass tufts (tinted from the material's tip colour, so a purple
// rift arena stays purple) and only a quarter stay as blades.
function buildGrassField(parent, spots, mat) {
  if (vegHasCover() && spots.length) {
    const ref = new THREE.Color(0x9fd870), hc = (mat.uniforms && mat.uniforms.uHigh && mat.uniforms.uHigh.value) || ref;
    const tint = [clamp(hc.r / ref.r, 0.3, 2.5) * 0.92, clamp(hc.g / ref.g, 0.3, 2.5) * 1.1, clamp(hc.b / ref.b, 0.3, 2.5) * 0.8];
    const list = [];
    for (let i = 0; i < spots.length; i += 4) {
      const s = spots[i], h = 0.18 + s.h * 0.55, j = ((i * 37) % 11) / 11 - 0.5;
      list.push({ p: [s.x, s.y - 0.03, s.z, i * 2.399, h * (1.6 + (j + 0.5) * 0.5), h, h * 1.7], rect: COVER_RECT[i % 13 === 0 ? 'tuss' : 'lawn'],
        tint: [tint[0] * (1 + j * 0.12), tint[1] * (1 + j * 0.06), tint[2] * (1 + j * 0.1), 0.7] });
    }
    const tm = vegInstanced(vegTuft(), vegCoverMat(), list, { rect: true });
    tm.frustumCulled = false; parent.add(tm);
    spots = spots.filter((_, i) => i % 4 === 1);
  }
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

// flowers: [{ x, y, z, h, col, s }] -> flowering-plant cards from the cover atlas (species picked from the colour),
// or the procedural petal flowers when the atlas is missing
function buildFlowerField(parent, flowers) {
  if (!vegHasCover() || !flowers.length) return buildFlowerFieldProc(parent, flowers);
  const c = new THREE.Color(), hsl = {};
  const list = flowers.map((f, i) => {
    c.setHex(f.col ?? 0xffffff).getHSL(hsl);
    const sp = hsl.s < 0.3 && hsl.l > 0.7 ? 'daisy' : hsl.h > 0.1 && hsl.h < 0.2 ? 'butter' : hsl.h > 0.55 && hsl.h < 0.8 ? 'bell' : 'pink';
    const s = f.s || 1, H = (0.3 + (f.h || 0.25) * 0.6) * s * 0.9, Wd = H * 0.5;
    const tint = sp === 'pink' && (hsl.h < 0.05 || hsl.h > 0.95) && hsl.l < 0.75 ? [1.15, 0.75, 0.8, 0.9] : [1, 1, 1, 0.9];
    return { m: vegM4(f.x, f.y - 0.02, f.z, i * 2.399, Wd, H, Wd), rect: COVER_RECT[sp], tint };
  });
  const im = vegInstanced(vegTuft(), vegCoverMat(), list, { rect: true, cast: false });
  parent.add(im);
  return [im];
}

// ============================================================================
//  legacy leaf-card foliage (fallback when the authored models are missing) and the encounter-grass blades
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

function buildForestLegacy(parent, trees, opts = {}) {
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

// ---------------- tall grass meadows: instanced blades with wind + player push
function buildGrassBlades(scene, zones) {
  const cards0 = vegHasCover();
  const blade = new THREE.BufferGeometry();
  blade.setAttribute('position', new THREE.BufferAttribute(new Float32Array([-0.07, 0, 0, 0.07, 0, 0, -0.05, 0.5, 0, 0.05, 0.5, 0, 0, 1, 0]), 3));
  blade.setIndex([0, 1, 2, 2, 1, 3, 2, 3, 4]);
  const U = { uTime: Shared.time, uPlayer: { value: new THREE.Vector3() }, uLow: { value: new THREE.Color(cards0 ? 0x0e2814 : 0x1f5a2c) }, uHigh: { value: new THREE.Color(cards0 ? 0x4a7430 : 0x9ad86a) }, uTint: { value: new THREE.Color(0xffc8a0) } };
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
  const cards = vegHasCover(), dens = (Settings.high ? 9 : 4.5) * (cards ? 0.18 : 1);
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
  if (Settings.high && !cards) {
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


// ============================================================================
//  trees & bushes: Blender models (tools/blender/vegetation_trees.py), instanced per variant with two LODs.
//  trees: [{ x, y, z, s, r, kind, tint }]
//    kind: 'oak' | 'birch' | 'cherry' | 'fir' (= 'pine') | 'bush' | 'round' (oak or birch; pink tint -> cherry)
//    tint: optional hex; recolours the leaves (autumn, rift purple). opts: { seed, lod, ground, center, lodDist }
// ============================================================================
const VEG_SPECIES = {
  oak:    { vars: ['oak_a', 'oak_b'], bark: 'bark_oak', wind: 1.0, R: 2.7, dens: 0.9, collide: 0.62 },
  birch:  { vars: ['birch_a', 'birch_b'], bark: 'bark_birch', wind: 1.35, R: 1.9, dens: 0.6, collide: 0.42 },
  cherry: { vars: ['cherry_a'], bark: 'bark_oak', wind: 0.9, R: 3.0, dens: 0.75, collide: 0.55 },
  fir:    { vars: ['fir_a', 'fir_b'], bark: 'bark_pine', wind: 0.55, R: 2.3, dens: 1.0, collide: 0.58 },
  bush:   { vars: ['bush_a', 'bush_b'], bark: 'bark_oak', wind: 0.8, R: 1.0, dens: 0.55, collide: 0 },
};
const _vm4 = new THREE.Matrix4(), _vq = new THREE.Quaternion(), _ve = new THREE.Euler(), _vv = new THREE.Vector3(), _vs = new THREE.Vector3();
function vegM4(x, y, z, ry, sx, sy, sz, tx = 0, tz = 0) {
  return new THREE.Matrix4().compose(_vv.set(x, y, z), _vq.setFromEuler(_ve.set(tx, ry, tz, 'YXZ')), _vs.set(sx, sy, sz));
}
function vegIsPink(hex) { const c = new THREE.Color(hex), h = {}; c.getHSL(h); return (h.h > 0.85 || h.h < 0.02) && h.l > 0.6; }
function vegSpeciesOf(t, rng) {
  const k = t.kind;
  if (k === 'pine' || k === 'fir') return 'fir';
  if (k === 'birch' || k === 'oak' || k === 'cherry' || k === 'bush') return k;
  if (t.tint !== undefined && vegIsPink(t.tint)) return 'cherry';
  return rng() < 0.3 ? 'birch' : 'oak';
}

function buildForest(parent, trees, opts = {}) {
  if (!vegHasTrees()) {
    // legacy cards: map the new kinds onto the old ones
    return buildForestLegacy(parent, trees.map((t) => (t.kind === 'fir' ? { ...t, kind: 'pine' } : t.kind === 'oak' || t.kind === 'birch' ? { ...t, kind: 'round' }
      : t.kind === 'cherry' ? { ...t, kind: 'round', tint: t.tint ?? 0xf7bfd8 } : t)), opts);
  }
  const G = vegGeos(), rng = mulberry32(opts.seed || 7);
  const g = new THREE.Group(); g.name = 'forest'; parent.add(g);
  const groups = {};                                     // variant -> instances
  const col = new THREE.Color(), tc = new THREE.Color();
  for (const t of trees) {
    const sp = vegSpeciesOf(t, rng), S = VEG_SPECIES[sp];
    t.sp = sp;
    const vname = sp === 'bush' ? (t.tint === undefined && rng() < 0.35 ? 'bush_b' : 'bush_a') : S.vars[(rng() * S.vars.length) | 0];
    const s = t.s * (sp === 'fir' ? 0.92 : sp === 'birch' ? 0.95 : 1);
    let tint = [1, 1, 1, 0];
    if (t.tint !== undefined && sp !== 'cherry') { tc.setHex(t.tint); tint = [tc.r, tc.g, tc.b, sp === 'bush' && !vegIsPink(t.tint) && tc.g > tc.r ? 0.35 : 0.82]; }
    const j = rng();
    col.setRGB(0.92 + j * 0.14, 0.94 + rng() * 0.1, 0.9 + rng() * 0.12);          // per-tree leaf colour drift
    // lean a little with the slope, sink the root flare
    const it = { x: t.x, z: t.z, m: vegM4(t.x, t.y - 0.04 * s, t.z, t.r || 0, s, s, s, (rng() - 0.5) * 0.05, (rng() - 0.5) * 0.05), tint, col: col.clone(), sp, s };
    (groups[vname] || (groups[vname] = [])).push(it);
    if (opts.ground) {
      // contact: dark root collar, litter under the crown, a soft canopy shadow on the grass
      const R = S.R * s;
      groundStamp(t.x, t.z, 0.75 * s + 0.35, { dark: 0.55 }, { soft: 0.75 });
      if (sp !== 'bush') {
        groundStamp(t.x, t.z, R * 0.95, { dark: 0.2 }, { soft: 0.9, noise: 0.5 });
        groundStamp(t.x, t.z, R * (sp === 'fir' ? 1.0 : 0.85), { forest: sp === 'fir' ? 0.8 : sp === 'birch' ? 0.35 : 0.55 }, { soft: 0.85, noise: 0.75 });
      } else groundStamp(t.x, t.z, 0.9 * s, { forest: 0.3 }, { soft: 0.8, noise: 0.6 });
    }
  }
  const forest = { g, sets: [], lod: !!opts.lod, cx: 1e9, cz: 1e9, t: 0 };
  for (const vname in groups) {
    const list = groups[vname], S = VEG_SPECIES[list[0].sp];
    const set = { list, meshes: [] };
    for (const lod of [0, 1]) {
      const sfx = lod ? '_lod1' : '';
      const wood = G[vname + '_wood' + sfx], leaf = G[vname + '_leaf' + sfx];
      if (!wood || !leaf) continue;
      const mw = vegInstanced(wood, vegBarkMat(S.bark), list, { cast: true });
      const ml = vegInstanced(leaf, vegLeafMat(list[0].sp, { wind: S.wind }), list, { cast: true });
      ml.customDepthMaterial = vegLeafDepth(list[0].sp, { wind: S.wind });
      if (lod === 1) { mw.castShadow = false; ml.castShadow = !opts.lod; }
      set.meshes.push([mw, ml]);
      g.add(mw, ml);
    }
    forest.sets.push(set);
  }
  // static LOD (battle arenas): far trees use LOD1 once; the island re-partitions as the camera moves
  const c = opts.center || { x: 0, z: 0 }, ld = opts.lodDist ?? 30;
  vegPartition(forest, c.x, c.z, opts.lod ? Veg.lodDist : ld);
  if (opts.lod) Veg.forests.push(forest);
  g.userData.vegForest = forest;
  return g;
}
// split each variant's instances into near (LOD0) and far (LOD1) by distance to (cx, cz)
function vegPartition(forest, cx, cz, dist) {
  forest.cx = cx; forest.cz = cz;
  const d2 = dist * dist;
  for (const set of forest.sets) {
    if (set.meshes.length < 2) continue;
    const [m0w, m0l] = set.meshes[0], [m1w, m1l] = set.meshes[1];
    let n0 = 0, n1 = 0;
    for (const it of set.list) {
      const near = (it.x - cx) ** 2 + (it.z - cz) ** 2 < d2 * (it.sp === 'bush' ? 0.45 : 1);
      const [mw, ml, k] = near ? [m0w, m0l, n0++] : [m1w, m1l, n1++];
      for (const m of [mw, ml]) {
        m.setMatrixAt(k, it.m); m.setColorAt(k, it.col);
        m.geometry.attributes.aTint.array.set(it.tint, k * 4);
      }
    }
    for (const [m, n] of [[m0w, n0], [m0l, n0], [m1w, n1], [m1l, n1]]) {
      m.count = n; m.visible = n > 0;
      m.instanceMatrix.needsUpdate = true; if (m.instanceColor) m.instanceColor.needsUpdate = true; m.geometry.attributes.aTint.needsUpdate = true;
      if (n) m.computeBoundingSphere();
    }
  }
}
function vegShade(x, z) {                               // 0..1 canopy cover from the island's trees
  const G = Veg.grid; if (!G) return 0;
  const cx = Math.floor(x / 8), cz = Math.floor(z / 8);
  let s = 0;
  for (let i = -1; i <= 1; i++) for (let j = -1; j <= 1; j++) {
    const L = G.get((cx + i) * 1000 + (cz + j)); if (!L) continue;
    for (const t of L) { const d = Math.hypot(x - t.x, z - t.z); if (d < t.R) s = Math.max(s, (1 - d / t.R) * t.dens); }
  }
  return s;
}
function vegIndexTrees(list) {
  Veg.trees = list; Veg.grid = new Map();
  for (const t of list) {
    const sp = t.sp || vegSpeciesOf(t, () => 0.5), S = VEG_SPECIES[sp];
    const e = { x: t.x, z: t.z, R: S.R * t.s * 0.95, dens: S.dens, sp, s: t.s };
    t.sp = sp;
    const key = Math.floor(t.x / 8) * 1000 + Math.floor(t.z / 8);
    (Veg.grid.get(key) || Veg.grid.set(key, []).get(key)).push(e);
  }
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
  // groves: a woodland density field (dense north woods, scattered copses, open meadows between)
  const grove = (x, z) => clamp(smooth(0.44, 0.66, fbm(x * 0.022 + 7.1, z * 0.022 - 3.3, 3)) * 0.85 + smooth(-14, -34, z) * 0.7, 0, 1);
  for (let k = 0; k < 9000 && list.length < 250; k++) {
    const x = (rng() - 0.5) * 190, z = (rng() - 0.5) * 190, gd = grove(x, z);
    if (rng() > 0.08 + gd) continue;                                   // a few solitary trees in the open
    if (!ok(x, z, 3.0 + (1 - gd) * 3.0)) continue;
    const north = z < -18, r0 = rng();
    let kind = north ? (r0 < 0.66 ? 'fir' : r0 < 0.86 ? 'birch' : 'oak') : (r0 < 0.14 ? 'fir' : r0 < 0.4 ? 'birch' : 'oak'), tint;
    if (kind === 'oak' && z > 20 && rng() < 0.38) kind = 'cherry';
    else if (kind === 'oak' && rng() < 0.08) tint = [0xd98a3a, 0xe0a040, 0xc8742e][(rng() * 3) | 0];
    const s = 0.8 + rng() * 0.7;
    list.push({ x, y: groundY(x, z), z, s, r: rng() * 6.28, kind, tint });
    World.colliders.push({ x, z, r: VEG_SPECIES[kind].collide * s + 0.1 });
  }
  // bushes: woodland edges, path verges and the odd shrub in the open
  let nb = 0;
  for (let k = 0; k < 6000 && nb < 170; k++) {
    const x = (rng() - 0.5) * 180, z = (rng() - 0.5) * 180, gd = grove(x, z), pd = pathDist(x, z);
    const edge = gd > 0.12 && gd < 0.62 ? 0.55 : 0.08, verge = pd > 4.5 && pd < 7.5 ? 0.35 : 0;
    if (rng() > edge + verge) continue;
    if (!ok(x, z, 2.2)) continue;
    list.push({ x, y: groundY(x, z), z, s: 0.7 + rng() * 0.6, r: rng() * 6.28, kind: 'bush', tint: rng() < 0.12 ? 0x7aa84a : undefined });
    nb++;
  }
  Veg.lodDist = Settings.high ? 40 : 24;
  buildForest(scene, list, { seed: 99, lod: true, ground: true });
  vegIndexTrees(list);
}

// ============================================================================
//  ground cover: lawn tufts, wild grass, tussocks, reeds, flowers in drifts, ferns, clover / plantain / moss /
//  leaf-litter patches and pebbles, placed by ecology rules (paths, canopy shade, rocks, trunks, marsh, beach).
//  Instanced per 24 m chunk; chunks beyond Veg.coverDist are hidden and cards shrink into the ground before that.
// ============================================================================
const _cr = (x0, y0, x1, y1) => [(x0 + 2) / 1024, 1 - (y1 - 2) / 1024, (x1 - x0 - 4) / 1024, (y1 - y0 - 4) / 1024];
const COVER_RECT = {
  lawn: _cr(0, 0, 512, 256), wild: _cr(0, 256, 256, 768), tuss: _cr(256, 256, 512, 768), fern: _cr(512, 0, 768, 512), reed: _cr(768, 0, 1024, 512),
  clover: _cr(512, 512, 768, 768), rosette: _cr(768, 512, 1024, 768), daisy: _cr(0, 768, 128, 1024), butter: _cr(128, 768, 256, 1024),
  bell: _cr(256, 768, 384, 1024), pink: _cr(384, 768, 512, 1024), moss: _cr(512, 768, 768, 1024), leafbed: _cr(768, 768, 1024, 1024),
};
// three crossed vertical cards (base at y = 0, 1 x 1), normals bent up so the clump lights like a soft mound
let _tuft = null, _flat = null;
function vegTuft() {
  if (_tuft) return _tuft;
  const P = [], N = [], UV = [], A = [], I = [];
  for (let q = 0; q < 3; q++) {
    const a = (q / 3) * Math.PI + 0.3, cx = Math.cos(a) * 0.5, cz = Math.sin(a) * 0.5, nx = -Math.sin(a), nz = Math.cos(a);
    const b = P.length / 3;
    const sg = q === 1 ? -1 : 1;                                       // each card leans out of the clump: reads as a fan from above
    for (const [u, v] of [[0, 0], [1, 0], [1, 1], [0, 1]]) {
      const lean = v * 0.14, tilt = v * 0.3 * sg;
      P.push((u * 2 - 1) * cx * (1 + lean) + nx * tilt, v * 0.96, (u * 2 - 1) * cz * (1 + lean) + nz * tilt);
      const n = new THREE.Vector3(nx * 0.3 * sg, 1, nz * 0.3 * sg).normalize(); N.push(n.x, n.y, n.z);
      UV.push(u, v); A.push(0.42 + 0.58 * Math.pow(v, 0.7), v * v, q / 3, 0);
    }
    I.push(b, b + 1, b + 2, b, b + 2, b + 3);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(P, 3)); g.setAttribute('normal', new THREE.Float32BufferAttribute(N, 3));
  g.setAttribute('uv', new THREE.Float32BufferAttribute(UV, 2)); g.setAttribute('aVeg', new THREE.Float32BufferAttribute(A, 4)); g.setIndex(I);
  g.computeBoundingBox(); g.computeBoundingSphere();
  return (_tuft = g);
}
// ground patch: 1 x 1 quad on XZ, slightly domed, normals up
function vegFlat() {
  if (_flat) return _flat;
  const g = new THREE.PlaneGeometry(1, 1, 2, 2).rotateX(-Math.PI / 2);
  const p = g.attributes.position, A = [];
  for (let i = 0; i < p.count; i++) { const r = Math.hypot(p.getX(i), p.getZ(i)); p.setY(i, 0.025 * (1 - r * 1.4)); A.push(0.78 + 0.22 * (1 - r), 0, 0.5, 0); }
  g.computeVertexNormals();
  const n = g.attributes.normal; for (let i = 0; i < n.count; i++) n.setXYZ(i, 0, 1, 0);
  g.setAttribute('aVeg', new THREE.Float32BufferAttribute(A, 4));
  g.computeBoundingBox(); g.computeBoundingSphere();
  return (_flat = g);
}

function buildGroundCover(scene) {
  const t0 = performance.now();
  const hi = Settings.high, D = hi ? 1 : 0.4;
  const G = vegGeos(), rng = mulberry32(4242);
  const CH = 24, chunks = new Map();
  const chunk = (x, z) => {
    const key = Math.floor(x / CH) * 1000 + Math.floor(z / CH);
    let c = chunks.get(key);
    if (!c) chunks.set(key, (c = { x: (Math.floor(x / CH) + 0.5) * CH, z: (Math.floor(z / CH) + 0.5) * CH, tuft: [], flat: [], fern_a: [], fern_b: [], pebble_0: [], pebble_1: [] }));
    return c;
  };
  const T = SITES.town, A = SITES.altar, big = World.colliders.filter((c) => c.r > 1.1);
  const blocked = (x, z) => {
    if (Math.hypot(x - T.x, z - T.z) < 10.5 || Math.hypot(x - A.x, z - A.z) < 10.5) return true;
    for (const r of SITES.rifts) if (Math.hypot(x - r.x, z - r.z) < 9) return true;
    for (const c of big) if (Math.abs(x - c.x) < c.r && Math.abs(z - c.z) < c.r && Math.hypot(x - c.x, z - c.z) < c.r * 0.92) return true;   // houses, big rocks, props
    return false;
  };
  const inZone = (x, z, pad = 0) => { for (const zz of ZONES) if (Math.hypot(x - zz.x, z - zz.z) < zz.r + pad) return true; return false; };
  const slopeTilt = (x, z) => { const e = 0.5, gx = (groundY(x + e, z) - groundY(x - e, z)) / (2 * e), gz = (groundY(x, z + e) - groundY(x, z - e)) / (2 * e); return [Math.atan(gz), -Math.atan(gx)]; };
  // tints: lawn matched to the terrain grass, lush meadows deeper, dry straw, shade cooler
  const grassTint = (ga, sh, j) => {
    const dry = ga.dry, lush = ga.lush;
    let r = 0.92 + j * 0.14, g = 1.2 + j * 0.1, b = 0.8 + j * 0.1;
    r = lerp(r, 0.76, lush * 0.6); b = lerp(b, 0.7, lush * 0.6);
    r = lerp(r, 1.35, dry * 0.8); g = lerp(g, 1.12, dry * 0.8); b = lerp(b, 0.7, dry * 0.8);
    const s = 1 - sh * 0.3; return [r * s, g * s, b * (s + sh * 0.1)];
  };
  const add = (kind, x, z, o) => {
    const y = o.y ?? groundY(x, z), c = chunk(x, z);
    if (o.flat) {
      const [tx, tz] = slopeTilt(x, z);
      c.flat.push({ p: [x, y + 0.012, z, rng() * 6.28, o.w, 1, o.w, tx, tz], rect: COVER_RECT[kind], tint: [...(o.tint || [1, 1, 1]), 0] });
    } else if (kind === 'fern_a' || kind === 'fern_b' || kind === 'pebble_0' || kind === 'pebble_1') {
      c[kind].push({ p: [x, y - (o.sink || 0.02), z, rng() * 6.28, o.w, o.w * (o.sy || 1), o.w], rect: [0, 0, 1, 1], tint: [...(o.tint || [1, 1, 1]), o.flex ?? 0.5] });
    } else {
      c.tuft.push({ p: [x, y - 0.03, z, rng() * 6.28, o.w, o.h, o.w], rect: COVER_RECT[kind], tint: [...(o.tint || [1, 1, 1]), o.flex ?? 0.8] });
    }
  };
  let n = 0;
  // ---- 1. lawn, verge plants, dune grass, reeds, scattered tall clumps (jittered grid over the island)
  const step = hi ? 0.76 : 1.45;
  for (let gz = -92; gz < 92; gz += step) for (let gx = -92; gx < 92; gx += step) {
    const x = gx + (rng() - 0.5) * step * 0.9, z = gz + (rng() - 0.5) * step * 0.9;
    if (x * x + z * z > 100 * 100) continue;
    const h = groundY(x, z); if (h < 0.9 || h > 14) continue;
    if (blocked(x, z) || inZone(x, z)) continue;
    const ga = groundAt(x, z), sh = vegShade(x, z), j = rng() - 0.5, u = rng();
    if (ga.rock > 0.5) { if (u < 0.05) add('tuss', x, z, { w: 0.5, h: 0.5 + rng() * 0.3, tint: [1.15, 1.05, 0.8] }); continue; }
    if (ga.sand > 0.12) {                                              // beach: dune tussocks at the grass line
      if (ga.sand < 0.45 && u < 0.3) add('tuss', x, z, { w: 0.5 + rng() * 0.3, h: 0.45 + rng() * 0.35, tint: [1.4, 1.2, 0.75], flex: 0.9 });
      continue;
    }
    if (ga.dirt > 0.62) { if (u < 0.012) add(rng() < 0.5 ? 'pebble_0' : 'pebble_1', x, z, { w: 0.6 + rng() * 0.6, sink: 0.01, flex: 0 }); continue; }
    if (ga.marsh > 0.3 && u < 0.35 * ga.marsh) { add('reed', x, z, { w: 0.55 + rng() * 0.25, h: 0.9 + rng() * 0.5, tint: [1, 1, 0.9], flex: 0.7 }); n++; continue; }
    if (ga.dirt > 0.3) {                                               // path verge: trodden short grass, plantain, clover, pebbles
      if (u < 0.08) add('rosette', x, z, { flat: true, w: 0.28 + rng() * 0.16 });
      else if (u < 0.12) add('clover', x, z, { flat: true, w: 0.5 + rng() * 0.4 });
      else if (u < 0.15) add(rng() < 0.5 ? 'pebble_0' : 'pebble_1', x, z, { w: 0.7 + rng() * 0.6, sink: 0.01, flex: 0 });
      else if (u < 0.55) add('lawn', x, z, { w: 0.45 + rng() * 0.2, h: 0.14 + rng() * 0.1, tint: grassTint(ga, sh, j), flex: 0.5 });
      continue;
    }
    if (sh > 0.55) {                                                   // under the canopy: sparse grass, litter, moss
      if (u < 0.2) add('lawn', x, z, { w: 0.5, h: 0.2 + rng() * 0.12, tint: grassTint(ga, sh, j), flex: 0.5 });
      continue;
    }
    if (u < 0.012 * (1 + ga.lush)) add('wild', x, z, { w: 0.42 + rng() * 0.2, h: 0.7 + rng() * 0.4, tint: grassTint(ga, sh, j), flex: 1 });
    else if (u < 0.034) add('tuss', x, z, { w: 0.48 + rng() * 0.25, h: 0.5 + rng() * 0.35, tint: grassTint(ga, sh, j), flex: 0.85 });
    else if (u < 0.06 && ga.lush + (1 - sh) > 0.8) add('clover', x, z, { flat: true, w: 0.55 + rng() * 0.5 });
    else { const hh = (0.22 + rng() * 0.18) * (1 + ga.lush * 0.35) * (1 - sh * 0.4); add('lawn', x, z, { w: hh * (1.6 + rng() * 0.5), h: hh, tint: grassTint(ga, sh, j), flex: 0.6 }); }
    n++;
  }
  // ---- 2. encounter-zone rims: a band of tall clumps easing into the meadow
  for (const zz of ZONES) {
    const m = Math.floor(zz.r * 9 * D);
    for (let i = 0; i < m; i++) {
      const a = rng() * 6.283, rr = zz.r + 0.2 + rng() * 2.2, x = zz.x + Math.cos(a) * rr, z = zz.z + Math.sin(a) * rr;
      if (blocked(x, z) || groundY(x, z) < 0.9) continue;
      add(rng() < 0.5 ? 'wild' : 'tuss', x, z, { w: 0.45 + rng() * 0.2, h: (0.55 + rng() * 0.4) * (1 - (rr - zz.r) / 3), tint: [0.92, 1, 0.88], flex: 1 });
    }
  }
  // ---- 3. flowers in drifts: one species per drift, dense centre thinning outward, only in sunny meadow
  const drifts = Math.round(80 * (hi ? 1 : 0.5));
  for (let d = 0, tries = 0; d < drifts && tries < 3000; tries++) {
    const cx = (rng() - 0.5) * 170, cz = (rng() - 0.5) * 170, h = groundY(cx, cz);
    if (h < 1.2 || h > 10 || blocked(cx, cz) || inZone(cx, cz, 1) || pathDist(cx, cz) < 2.8 || vegShade(cx, cz) > 0.15) continue;
    const ga = groundAt(cx, cz); if (ga.dirt > 0.3 || ga.sand > 0.1 || ga.rock > 0.3) continue;
    const sp = cx > 25 ? (rng() < 0.6 ? 'pink' : 'butter') : cx < -25 ? (rng() < 0.6 ? 'bell' : 'daisy') : cz > 10 ? (rng() < 0.55 ? 'daisy' : 'butter') : cz < -18 ? 'bell' : ['daisy', 'butter', 'bell', 'pink'][(rng() * 4) | 0];
    const R = 1.2 + rng() * 2.6, cnt = Math.round((10 + rng() * 26) * (hi ? 1 : 0.5));
    for (let i = 0; i < cnt; i++) {
      const a = rng() * 6.283, rr = R * Math.sqrt(-2 * Math.log(1 - rng() * 0.95)) * 0.5, x = cx + Math.cos(a) * rr, z = cz + Math.sin(a) * rr;
      if (blocked(x, z) || pathDist(x, z) < 2.2 || groundY(x, z) < 1.1) continue;
      const H = 0.34 + rng() * 0.2; add(sp, x, z, { w: H * 0.5, h: H, flex: 0.9 });
    }
    d++;
  }
  // ---- 4. under the trees: ferns, leaf litter, moss; clumps hugging the trunk to break the ground line
  for (const t of Veg.trees) {
    const S = VEG_SPECIES[t.sp], R = S.R * t.s;
    const north = t.z < -18;
    if (t.sp === 'bush') { if (rng() < 0.6) add('tuss', t.x + (rng() - 0.5) * 0.8, t.z + (rng() - 0.5) * 0.8, { w: 0.5, h: 0.5 + rng() * 0.2, flex: 0.8 }); continue; }
    const nf = Math.round((t.sp === 'fir' || north ? 3 + rng() * 5 : t.sp === 'cherry' ? 0 : 1 + rng() * 3) * (hi ? 1 : 0.5));
    for (let i = 0; i < nf; i++) {
      const a = rng() * 6.283, rr = (0.7 + rng() * 0.75) * R, x = t.x + Math.cos(a) * rr, z = t.z + Math.sin(a) * rr;
      if (blocked(x, z) || pathDist(x, z) < 2.6 || groundY(x, z) < 1.0) continue;
      add(rng() < 0.5 ? 'fern_a' : 'fern_b', x, z, { w: 0.65 + rng() * 0.55, flex: 0.6, tint: north ? [0.85, 0.95, 0.85] : [1, 1, 1] });
    }
    const nl = t.sp === 'fir' ? 1 + (rng() * 2 | 0) : 2 + (rng() * 3 | 0);
    for (let i = 0; i < nl; i++) {
      const a = rng() * 6.283, rr = rng() * R * 0.75, x = t.x + Math.cos(a) * rr, z = t.z + Math.sin(a) * rr;
      if (blocked(x, z) || pathDist(x, z) < 2.4) continue;
      add(t.sp === 'fir' ? 'moss' : 'leafbed', x, z, { flat: true, w: 0.8 + rng() * 0.8, tint: t.sp === 'cherry' ? [1.1, 0.9, 0.9] : [1, 1, 1] });
    }
    const nt = 2 + (rng() * 3 | 0);
    for (let i = 0; i < nt; i++) {
      const a = rng() * 6.283, rr = (0.38 + rng() * 0.35) * t.s, x = t.x + Math.cos(a) * rr, z = t.z + Math.sin(a) * rr;
      add(rng() < 0.6 ? 'tuss' : 'wild', x, z, { w: 0.4 + rng() * 0.2, h: 0.4 + rng() * 0.3, tint: [0.9, 0.95, 0.85], flex: 0.7 });
    }
  }
  // ---- 5. around rocks: grass collar, moss on the shaded foot, pebbles that broke off
  for (const r of Veg.rocks) {
    const nr = Math.round((5 + r.s * 9) * (hi ? 1 : 0.6));
    for (let i = 0; i < nr; i++) {
      const a = rng() * 6.283, rr = r.s * (0.85 + rng() * 0.45), x = r.x + Math.cos(a) * rr, z = r.z + Math.sin(a) * rr;
      if (blocked(x, z) && r.s < 1.1) continue;
      const ga = groundAt(x, z); if (ga.sand > 0.3 || ga.dirt > 0.6) continue;
      const kind = rng() < 0.45 ? 'tuss' : rng() < 0.5 ? 'wild' : 'lawn';
      add(kind, x, z, { w: kind === 'lawn' ? 0.6 : 0.45 + rng() * 0.2, h: kind === 'lawn' ? 0.3 + rng() * 0.12 : 0.45 + rng() * 0.35, tint: [0.92, 0.98, 0.86], flex: 0.8 });
    }
    if (rng() < 0.7) { const a = 0.3 + rng() * 0.8; add('moss', r.x + Math.cos(a) * r.s * 0.95, r.z + Math.sin(a) * r.s * 0.95, { flat: true, w: 0.5 + r.s * 0.4 }); }
    const np = 1 + (rng() * 2.2 | 0);
    for (let i = 0; i < np; i++) { const a = rng() * 6.283, rr = r.s * (1.1 + rng() * 0.7); add(rng() < 0.5 ? 'pebble_0' : 'pebble_1', r.x + Math.cos(a) * rr, r.z + Math.sin(a) * rr, { w: 0.7 + rng() * 0.7, sink: 0.01, flex: 0 }); }
  }
  // ---- build the chunk meshes
  const mat = vegCoverMat(), rockM = vegHasRocks() ? vegRockMat() : null;
  const root = new THREE.Group(); root.name = 'groundCover'; scene.add(root);
  let inst = 0;
  for (const c of chunks.values()) {
    const meshes = [];
    const mk = (geo, list, m, o) => { if (!geo || !list.length) return; const im = vegInstanced(geo, m, list, o); im.receiveShadow = hi; root.add(im); meshes.push(im); inst += list.length; };
    mk(vegTuft(), c.tuft, mat, { rect: true });
    mk(vegFlat(), c.flat, mat, { rect: true });
    mk(G.fern_a_leaf, c.fern_a, mat, { rect: true });
    mk(G.fern_b_leaf, c.fern_b, mat, { rect: true });
    if (rockM) { mk(G.pebble_0, c.pebble_0, rockM, {}); mk(G.pebble_1, c.pebble_1, rockM, {}); }
    if (meshes.length) Veg.cover.push({ x: c.x, z: c.z, r: CH * 0.71, meshes, vis: true });
  }
  Veg.coverStats = { instances: inst, chunks: Veg.cover.length, ms: Math.round(performance.now() - t0) };
  window.__nature = Object.assign(window.__nature || {}, { cover: Veg.coverStats });
}

// ---------------- encounter grass (ZONES): tall wild grass and tussock cards over a bed of blades, pushed aside by the player
function buildGrass(scene, zones) {
  const old = buildGrassBlades(scene, zones);
  Veg.U.uPlayer = old.U.uPlayer;                                     // the world loop feeds the player position here
  if (!vegHasCover()) return old;
  const rng = mulberry32(5150), dens = Settings.high ? 2.4 : 1.1;
  const mat = vegCoverMat();
  for (const z of zones) {
    const list = [];
    const n = Math.floor(Math.PI * z.r * z.r * dens);
    for (let i = 0; i < n; i++) {
      const a = rng() * 6.283, rr = Math.sqrt(rng()) * z.r, x = z.x + Math.cos(a) * rr, zz = z.z + Math.sin(a) * rr;
      const edge = 1 - smooth(z.r * 0.72, z.r, rr), j = rng();
      const kind = rng() < 0.4 ? 'wild' : 'tuss';
      const H = (0.8 + rng() * 0.45) * (0.5 + edge * 0.5) * (kind === 'tuss' ? 0.8 : 1);
      list.push({ p: [x, groundY(x, zz) - 0.04, zz, rng() * 6.28, H * (0.5 + rng() * 0.15), H, H * 0.55], rect: COVER_RECT[kind],
        tint: [0.86 + j * 0.16, 0.95 + j * 0.08, 0.8 + j * 0.12, 1] });
    }
    const im = vegInstanced(vegTuft(), mat, list, { rect: true });
    im.receiveShadow = Settings.high;
    scene.add(im);
  }
  return old;
}

// ---------------- island rocks: boulders sunk into the ground (contact AO + soil in the splat map), clustered with
// smaller satellites, preferring slopes, hilltops and the coast. Flowers now grow in drifts with the ground cover.
function buildRocksAndFlowers(scene) {
  const rng = mulberry32(99);
  const rocks = [];
  const okAt = (x, z) => {
    const h = groundY(x, z);
    if (h < 0.4 || pathDist(x, z) < 3.2 || Math.hypot(x - SITES.town.x, z - SITES.town.z) < 16 || Math.hypot(x - SITES.altar.x, z - SITES.altar.z) < 11) return false;
    for (const zz of ZONES) if (Math.hypot(x - zz.x, z - zz.z) < zz.r) return false;
    for (const r of SITES.rifts) if (Math.hypot(x - r.x, z - r.z) < 8) return false;
    return true;
  };
  const addRock = (x, z, s) => {
    const h = groundY(x, z), e = 0.6, gx = (groundY(x + e, z) - groundY(x - e, z)) / (2 * e), gz = (groundY(x, z + e) - groundY(x, z - e)) / (2 * e);
    rocks.push({ x, y: h - 0.1 * s, z, s, r: rng() * 6.28, sy: 0.8 + rng() * 0.45, tx: Math.atan(gz) * 0.6, tz: -Math.atan(gx) * 0.6 });
    if (s > 0.9) World.colliders.push({ x, z, r: s * 0.8 });
    groundStamp(x, z, s * 1.35 + 0.25, { dark: 0.6 }, { soft: 0.6 });
    groundStamp(x, z, s * 1.1 + 0.1, { dirt: 0.28 }, { soft: 0.55, noise: 0.6 });
  };
  for (let k = 0; k < 2400 && rocks.length < 100; k++) {
    const x = (rng() - 0.5) * 200, z = (rng() - 0.5) * 200;
    if (!okAt(x, z)) continue;
    const h = groundY(x, z), e = 1, sl = Math.hypot(groundY(x + e, z) - groundY(x - e, z), groundY(x, z + e) - groundY(x, z - e)) / (2 * e);
    if (rng() > 0.18 + sl * 1.6 + (h > 6 ? 0.25 : 0) + (h < 1.7 ? 0.2 : 0)) continue;
    let near = false; for (const r of rocks) if (Math.hypot(x - r.x, z - r.z) < r.s + 2) near = true; if (near) continue;
    const s = 0.35 + Math.pow(rng(), 2) * 1.8;
    addRock(x, z, s);
    if (s > 0.75 && rng() < 0.65) {                                   // satellites: broken-off pieces leaning on the parent
      const m = 1 + ((rng() * 3) | 0);
      for (let i = 0; i < m; i++) {
        const a = rng() * 6.283, d = s * (1.05 + rng() * 0.7), x2 = x + Math.cos(a) * d, z2 = z + Math.sin(a) * d;
        if (okAt(x2, z2)) addRock(x2, z2, s * (0.22 + rng() * 0.3));
      }
    }
  }
  const ims = buildRockField(scene, rocks);
  Veg.rocks = rocks;
  window.__nature = Object.assign(window.__nature || {}, { rocks: rocks.length, rockAssets: vegHasRocks(), trees: Veg.trees.length, treeAssets: vegHasTrees(),
    bigRocks: rocks.filter((r) => r.s > 1.25 && Math.abs(r.x) < 60 && r.z > -10).slice(0, 6).map((r) => [+r.x.toFixed(1), +r.z.toFixed(1), +r.s.toFixed(2)]) });
  if (!vegHasCover()) buildFlowersProc(scene, rng);
  return ims;
}
function buildFlowersProc(scene, rng) {
  const fl = [], fc = [0xffc6e0, 0xfff1a8, 0xd9c8ff, 0xffffff, 0xa8e6ff, 0xff9aa8];
  for (let k = 0; k < 4000 && fl.length < (isTouch ? 600 : 1500); k++) {
    const x = (rng() - 0.5) * 180, z = (rng() - 0.5) * 180, h = groundY(x, z);
    if (h < 1.1 || h > 9 || pathDist(x, z) < 2.4 || Math.hypot(x - SITES.town.x, z - SITES.town.z) < 10.5) continue;
    const col = fc[(rng() * fc.length) | 0], n = 1 + ((rng() * 4) | 0);
    for (let j = 0; j < n; j++) { const fx = x + (rng() - 0.5) * 1.2, fz = z + (rng() - 0.5) * 1.2; fl.push({ x: fx, y: groundY(fx, fz), z: fz, h: 0.18 + rng() * 0.18, s: 1.1 + rng() * 0.6, col }); }
  }
  buildFlowerFieldProc(scene, fl);
}

// ---------------- hooks called from 03_world.js (buildWorld / updateWorld)
function buildNatureExtras(scene) {
  Veg.coverDist = Settings.high ? 60 : 32;
  Veg.U.uFade.value.set(Veg.coverDist * 0.72, Veg.coverDist);
  // the ground cover needs the finished island (town colliders, splat stamps): built on the first world update
  if (vegHasCover()) Veg.pendingCover = scene;
}
function updateNatureExtras(dt) {
  if (Veg.pendingCover) {
    const sc = Veg.pendingCover; Veg.pendingCover = null;
    try { buildGroundCover(sc); } catch (e) { console.warn('ground cover', e); }
  }
  const cam = World.camera; if (!cam) return;
  const cx = cam.position.x, cz = cam.position.z;
  Veg.t += dt;
  for (const f of Veg.forests) {
    if ((cx - f.cx) ** 2 + (cz - f.cz) ** 2 > 16 || (Veg.t - f.t > 1.5 && (cx - f.cx) ** 2 + (cz - f.cz) ** 2 > 0.25)) { f.t = Veg.t; vegPartition(f, cx, cz, Veg.lodDist); }
  }
  for (const c of Veg.cover) {
    const vis = Math.hypot(cx - c.x, cz - c.z) - c.r < Veg.coverDist;
    if (vis !== c.vis) { c.vis = vis; for (const m of c.meshes) m.visible = vis; }
  }
}
