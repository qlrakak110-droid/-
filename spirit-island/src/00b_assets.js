// ============================================================================
//  asset library: textures and glTF models authored offline (spirit-island/tools/)
//  and loaded at boot. Every consumer must keep a procedural fallback: when the
//  page is opened from file:// (no HTTP) or a file is missing, Assets.* returns null.
// ============================================================================
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';

const Assets = {
  base: 'assets/', tex: {}, models: {}, ready: false, failed: [],
  _want: { textures: {}, models: {} },
};
// Called at top level by any src file:  registerAssets({ textures: { rock_a: { file: 'tex/rock_a.jpg', lo: 'tex/rock_a_512.jpg', srgb: true } }, models: { house_a: 'models/house_a.glb' } })
//  - textures: srgb true for colour maps, false (default) for normal / ORM / height maps; lo = smaller file used on phones
//  - models: path, or { file, lo }
function registerAssets(def) {
  Object.assign(Assets._want.textures, def.textures || {});
  Object.assign(Assets._want.models, def.models || {});
}
// texture lookup: a THREE.Texture (shared, RepeatWrapping) or null
function assetTex(name) { return Assets.tex[name] || null; }
// model lookup: a fresh clone of the glTF scene (materials shared) or null
function assetModel(name) { const g = Assets.models[name]; return g ? g.scene.clone(true) : null; }
function assetGltf(name) { return Assets.models[name] || null; }

Assets.loadAll = async function (onProgress) {
  const W = Assets._want, jobs = [];
  if (location.protocol === 'file:') { Assets.ready = true; return; }      // WebGL can't use file:// images; fall back to procedural
  const lo = typeof Settings !== 'undefined' && !Settings.high;
  const tl = new THREE.TextureLoader(), gl = new GLTFLoader();
  let done = 0; const total = Object.keys(W.textures).length + Object.keys(W.models).length;
  const tick = () => { done++; if (onProgress) onProgress(done, total); };
  for (const [name, d0] of Object.entries(W.textures)) {
    const d = typeof d0 === 'string' ? { file: d0 } : d0, file = (lo && d.lo) || d.file;
    jobs.push(new Promise((res) => tl.load(Assets.base + file, (t) => {
      t.wrapS = t.wrapT = THREE.RepeatWrapping; t.anisotropy = lo ? 2 : 8;
      t.colorSpace = d.srgb ? THREE.SRGBColorSpace : THREE.NoColorSpace;
      Assets.tex[name] = t; tick(); res();
    }, undefined, () => { Assets.failed.push(file); tick(); res(); })));
  }
  for (const [name, d0] of Object.entries(W.models)) {
    const d = typeof d0 === 'string' ? { file: d0 } : d0, file = (lo && d.lo) || d.file;
    jobs.push(new Promise((res) => gl.load(Assets.base + file, (g) => {
      g.scene.traverse((o) => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });
      Assets.models[name] = g; tick(); res();
    }, undefined, () => { Assets.failed.push(file); tick(); res(); })));
  }
  await Promise.all(jobs);
  if (Assets.failed.length) console.warn('assets missing (procedural fallback used):', Assets.failed.join(', '));
  Assets.ready = true;
};

// ---------------- PBR helpers
// pbrSet('rock_a') expects textures rock_a_albedo (srgb), rock_a_normal, rock_a_orm (r=AO g=roughness b=height) registered
function pbrSet(name) {
  const a = assetTex(name + '_albedo'), n = assetTex(name + '_normal'), o = assetTex(name + '_orm');
  return a ? { albedo: a, normal: n, orm: o } : null;
}
// Triplanar PBR: patches a MeshStandardMaterial so map / normalMap / roughness come from world-space triplanar
// projection (no UVs needed: terrain cliffs, sculpted rocks, dragons). scale = texture repeats per world unit.
function triplanarPBR(mat, set, scale = 0.25, opts = {}) {
  if (!set) return mat;
  const U = { tpA: { value: set.albedo }, tpN: { value: set.normal }, tpO: { value: set.orm }, tpScale: { value: scale },
    tpNormStr: { value: opts.normalStrength ?? 1 }, tpTint: { value: new THREE.Color(opts.tint ?? 0xffffff) }, tpRough: { value: opts.roughness ?? 1 } };
  mat.userData.tp = U;
  const prev = mat.onBeforeCompile;
  mat.onBeforeCompile = (sh, r) => {
    if (prev) prev(sh, r);
    Object.assign(sh.uniforms, U);
    sh.vertexShader = 'varying vec3 tpW; varying vec3 tpNw;\n' + sh.vertexShader.replace('#include <worldpos_vertex>', `#include <worldpos_vertex>
      tpW = (modelMatrix * vec4(transformed, 1.0)).xyz; tpNw = normalize(mat3(modelMatrix) * objectNormal);`);
    sh.fragmentShader = `uniform sampler2D tpA, tpN, tpO; uniform float tpScale, tpNormStr, tpRough; uniform vec3 tpTint; varying vec3 tpW; varying vec3 tpNw;
      vec3 tpBlend(vec3 n){ vec3 b = pow(abs(n), vec3(4.0)); return b / (b.x + b.y + b.z + 1e-4); }
      vec4 tpSample(sampler2D t, vec3 p, vec3 b){ return texture2D(t, p.zy) * b.x + texture2D(t, p.xz) * b.y + texture2D(t, p.xy) * b.z; }
      // whiteout-blended triplanar normal mapping (world space), after Ben Golus
      vec3 tpNormal(vec3 p, vec3 n, vec3 b){
        vec3 tx = texture2D(tpN, p.zy).xyz * 2.0 - 1.0, ty = texture2D(tpN, p.xz).xyz * 2.0 - 1.0, tz = texture2D(tpN, p.xy).xyz * 2.0 - 1.0;
        tx.xy *= tpNormStr; ty.xy *= tpNormStr; tz.xy *= tpNormStr;
        tx = vec3(tx.xy + n.zy, abs(tx.z) * n.x);
        ty = vec3(ty.xy + n.xz, abs(ty.z) * n.y);
        tz = vec3(tz.xy + n.xy, abs(tz.z) * n.z);
        return normalize(tx.zyx * b.x + ty.xzy * b.y + tz.xyz * b.z);
      }
      ` + sh.fragmentShader
      .replace('#include <map_fragment>', `
        vec3 tpP = tpW * tpScale, tpB = tpBlend(normalize(tpNw));
        vec4 tpAl = tpSample(tpA, tpP, tpB);
        diffuseColor.rgb *= tpAl.rgb * tpTint;
        vec4 tpOrm = tpSample(tpO, tpP, tpB);`)
      .replace('#include <roughnessmap_fragment>', `#include <roughnessmap_fragment>
        roughnessFactor *= mix(1.0, tpOrm.g * 1.25, step(0.001, tpOrm.g + tpOrm.r)) * tpRough;`)
      .replace('#include <normal_fragment_maps>', `#include <normal_fragment_maps>
        {
          vec3 wn = tpNormal(tpP, normalize(tpNw), tpB);
          normal = normalize((viewMatrix * vec4(wn, 0.0)).xyz);
        }`)
      .replace('#include <aomap_fragment>', `#include <aomap_fragment>
        reflectedLight.indirectDiffuse *= mix(1.0, tpOrm.r, 0.85);`);
  };
  const k = mat.customProgramCacheKey ? mat.customProgramCacheKey() : '';
  mat.customProgramCacheKey = () => k + '|tp';
  mat.needsUpdate = true;
  return mat;
}
