// ============================================================================
//  dragons: sculpted bodies + PBR scale shader + membrane / feather wings
// ============================================================================
const GLSL_NOISE3 = `
  float h31(vec3 p){ p = fract(p * 0.1031); p += dot(p, p.zyx + 31.32); return fract((p.x + p.y) * p.z); }
  vec3 h33(vec3 p){ p = fract(p * vec3(0.1031, 0.1030, 0.0973)); p += dot(p, p.yxz + 33.33); return fract((p.xxy + p.yxx) * p.zyx); }
  float vn3(vec3 p){ vec3 i = floor(p), f = fract(p); vec3 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(h31(i), h31(i + vec3(1,0,0)), u.x), mix(h31(i + vec3(0,1,0)), h31(i + vec3(1,1,0)), u.x), u.y),
               mix(mix(h31(i + vec3(0,0,1)), h31(i + vec3(1,0,1)), u.x), mix(h31(i + vec3(0,1,1)), h31(i + vec3(1,1,1)), u.x), u.y), u.z); }
  vec3 vor3(vec3 x){ vec3 p = floor(x), f = fract(x); float d1 = 8.0, d2 = 8.0, id = 0.0;
    for (int k = -1; k <= 1; k++) for (int j = -1; j <= 1; j++) for (int i = -1; i <= 1; i++) {
      vec3 b = vec3(float(i), float(j), float(k)); vec3 r = b - f + h33(p + b) * 0.85; float d = dot(r, r);
      if (d < d1) { d2 = d1; d1 = d; id = h31(p + b); } else if (d < d2) { d2 = d; } }
    return vec3(sqrt(d1), sqrt(d2), id); }
  vec3 vorEdgeGrad(vec3 x, out vec4 info){ vec3 p = floor(x), f = fract(x); float d1 = 8.0, d2 = 8.0, id = 0.0; vec3 r1 = vec3(1.0), r2 = vec3(1.0);
    for (int k = -1; k <= 1; k++) for (int j = -1; j <= 1; j++) for (int i = -1; i <= 1; i++) {
      vec3 b = vec3(float(i), float(j), float(k)); vec3 r = b - f + h33(p + b) * 0.85; float d = dot(r, r);
      if (d < d1) { d2 = d1; r2 = r1; d1 = d; r1 = r; id = h31(p + b); } else if (d < d2) { d2 = d; r2 = r; } }
    float F1 = sqrt(d1), F2 = sqrt(d2);
    info = vec4(F1, F2, id, F2 - F1);
    return r1 / max(F1, 1e-4) - r2 / max(F2, 1e-4); }
`;
const sstep = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };

// JS mirror of the vertex deformation so attachments (eyes, halo, pearl…) stay glued to the body
function dragonOffset(U, s, t) {
  const tailW = 1 - sstep(0, U.uTailStart.value, s);
  const amp = U.uWaveAmp.value * (tailW * tailW + U.uSerp.value * (0.4 + 0.6 * (1 - s)));
  const ph = t * U.uWaveSpeed.value - s * U.uWaveFreq.value;
  const headW = sstep(U.uNeckStart.value, 1, s) * U.uSway.value;
  return new THREE.Vector3(Math.sin(ph) * amp + Math.sin(t * 0.6) * 0.14 * headW, Math.sin(ph * 0.8 + 1.3) * amp * 0.35 + Math.sin(t * 0.9 + 0.7) * 0.07 * headW, 0);
}

// ---------------------------------------------------------------- build-time bake: SDF ambient occlusion, curvature, thickness
// Per vertex, in object space before any deformation, from the sculpt's own distance grid (no ray tracing, ~0.1 s):
//   x  occlusion (0 open … 1 buried) — a cone of 7 rays (normal + 6 tilted 50°) marched through the SDF, each step
//      compared with what a flat open surface would read, so only real creases, cavities and contacts darken
//   y  mean curvature (−1 cavity … +1 sharp ridge) — normal divergence along mesh edges, smoothed, squashed
//   z  thinness (0 thick … 1 paper thin) — inscribed radius found by marching inward along −n (ears, fins, frills)
// Every channel is 0 where nothing is baked, so materials on unbaked geometry look exactly like before.
function bakeSculpt(m, opt = {}) {
  const { pos, nor, idx, nv, sample } = m;
  const R = opt.aoR || 0.2, tMax = opt.thickMax || R * 3, tRef = opt.thinRef || R * 0.9;
  const out = new Float32Array(nv * 3);
  const steps = [0.12, 0.28, 0.55, 1.0].map((k) => k * R), sw = [1.0, 0.8, 0.6, 0.45];
  let swSum = 0; for (const w of sw) swSum += w;
  const tilt = 0.87, ct = Math.cos(tilt), st = Math.sin(tilt);
  const D = [[0, 0]]; for (let i = 0; i < 6; i++) D.push([Math.cos(i * Math.PI / 3 + 0.3), Math.sin(i * Math.PI / 3 + 0.3)]);
  const ao = new Float32Array(nv), thick = new Float32Array(nv);
  for (let q = 0; q < nv; q++) {
    const px = pos[q * 3], py = pos[q * 3 + 1], pz = pos[q * 3 + 2], nx = nor[q * 3], ny = nor[q * 3 + 1], nz = nor[q * 3 + 2];
    let tx, ty, tz; if (Math.abs(ny) < 0.9) { tx = nz; ty = 0; tz = -nx; } else { tx = 0; ty = -nz; tz = ny; }
    const l = Math.hypot(tx, ty, tz) || 1; tx /= l; ty /= l; tz /= l;
    const bx = ny * tz - nz * ty, by = nz * tx - nx * tz, bz = nx * ty - ny * tx;
    let occ = 0, wsum = 0;
    for (let d = 0; d < D.length; d++) {
      const ca = D[d][0], sa = D[d][1];
      let dx, dy, dz, cosn;
      if (d === 0) { dx = nx; dy = ny; dz = nz; cosn = 1; }
      else { dx = nx * ct + (tx * ca + bx * sa) * st; dy = ny * ct + (ty * ca + by * sa) * st; dz = nz * ct + (tz * ca + bz * sa) * st; cosn = ct; }
      const dw = d === 0 ? 1.5 : 1;
      for (let k = 0; k < steps.length; k++) {
        const s = steps[k], f = sample(px + dx * s, py + dy * s, pz + dz * s);
        const o = (s * cosn - f) / s;
        occ += (o > 1 ? 1 : o > 0 ? o : 0) * sw[k] * dw;
      }
      wsum += swSum * dw;
    }
    ao[q] = occ / wsum;
    let best = 0;
    for (let t = R * 0.06; t <= tMax; t *= 1.45) {
      const f = -sample(px - nx * t, py - ny * t, pz - nz * t);
      if (f > best) best = f;
      if (f < best * 0.5 && t > best * 2.2) break;
    }
    thick[q] = best;
  }
  // curvature from normal divergence along edges
  const acc = new Float32Array(nv), cnt = new Float32Array(nv);
  const edge = (i, j) => {
    const ex = pos[j * 3] - pos[i * 3], ey = pos[j * 3 + 1] - pos[i * 3 + 1], ez = pos[j * 3 + 2] - pos[i * 3 + 2];
    const l2 = ex * ex + ey * ey + ez * ez; if (l2 < 1e-12) return;
    const k = ((nor[j * 3] - nor[i * 3]) * ex + (nor[j * 3 + 1] - nor[i * 3 + 1]) * ey + (nor[j * 3 + 2] - nor[i * 3 + 2]) * ez) / l2;
    acc[i] += k; acc[j] += k; cnt[i]++; cnt[j]++;
  };
  for (let t = 0; t < idx.length; t += 3) { const a = idx[t], b = idx[t + 1], c = idx[t + 2]; edge(a, b); edge(b, c); edge(c, a); }
  const curv = new Float32Array(nv);
  for (let q = 0; q < nv; q++) curv[q] = cnt[q] ? acc[q] / cnt[q] : 0;
  // smoothing (surface-nets vertices are slightly irregular): curvature twice, AO and thickness once
  for (let pass = 0; pass < 2; pass++) {
    const sc = new Float32Array(nv), sa = new Float32Array(nv), sth = new Float32Array(nv), n = new Float32Array(nv);
    for (let t = 0; t < idx.length; t += 3) for (let e = 0; e < 3; e++) {
      const i = idx[t + e], j = idx[t + (e + 1) % 3];
      sc[i] += curv[j]; sc[j] += curv[i]; sa[i] += ao[j]; sa[j] += ao[i]; sth[i] += thick[j]; sth[j] += thick[i]; n[i]++; n[j]++;
    }
    for (let q = 0; q < nv; q++) if (n[q]) {
      curv[q] = (curv[q] + sc[q] / n[q]) * 0.5;
      if (pass === 0) { ao[q] = (ao[q] * 2 + sa[q] / n[q]) / 3; thick[q] = (thick[q] + sth[q] / n[q]) * 0.5; }
    }
  }
  const cs = R * 0.22;
  for (let q = 0; q < nv; q++) {
    out[q * 3] = Math.min(1, Math.max(0, ao[q] * 1.6));
    out[q * 3 + 1] = Math.tanh(curv[q] * cs);
    out[q * 3 + 2] = Math.min(1, Math.max(0, 1 - thick[q] / tRef));
  }
  return out;
}

const _dragonGeo = {};
function dragonGeometry(key, design, cellHi = 0.04, cellLo = 0.058) {
  const cell = Settings.high && !isTouch ? cellHi : cellLo;
  const ck = key + '@' + cell;
  if (_dragonGeo[ck]) return _dragonGeo[ck];
  const m = sculptMesh(design.prims, design.bounds, cell);
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.BufferAttribute(m.pos, 3));
  g.setAttribute('normal', new THREE.BufferAttribute(m.nor, 3));
  g.setAttribute('color', new THREE.BufferAttribute(m.col, 3));
  g.setAttribute('aS', new THREE.BufferAttribute(m.aS, 1));
  g.setAttribute('aJaw', new THREE.BufferAttribute(m.aJaw, 1));
  g.setAttribute('aGlow', new THREE.BufferAttribute(m.aGlow, 1));
  g.setAttribute('aBelly', new THREE.BufferAttribute(m.aBelly, 1));
  g.setAttribute('aLeg', new THREE.BufferAttribute(m.aLeg, 1));
  if (design.bake !== false) {
    try {
      const b = design.bounds, diag = Math.hypot(b[3] - b[0], b[4] - b[1], b[5] - b[2]);
      const aoR = design.aoR || clamp(diag * 0.06, 0.1, 0.45);
      g.setAttribute('aBake', new THREE.BufferAttribute(bakeSculpt(m, { aoR }), 3));
    } catch (e) { console.warn('sculpt bake skipped', key, e && e.message); }
  }
  g.setIndex(new THREE.BufferAttribute(m.idx, 1));
  g.computeBoundingSphere(); g.boundingSphere.radius *= 1.3;
  _dragonGeo[ck] = g; return g;
}

const SCULPT_DECL = `uniform float uTime, uWaveAmp, uWaveSpeed, uWaveFreq, uTailStart, uSerp, uNeckStart, uSway, uJaw, uWalk, uStride, uHipY, uShoulderY; uniform vec3 uJawHinge;
      attribute float aS; attribute float aJaw; attribute float aGlow; attribute float aBelly; attribute float aLeg; attribute vec3 aBake;
      varying vec3 vObjPos; varying vec3 vObjN; varying float vGlow; varying float vBelly; varying float vS; varying vec3 vBake;
      vec3 dragonOffset(float s){
        float tailW = 1.0 - smoothstep(0.0, uTailStart, s);
        float amp = uWaveAmp * (tailW * tailW + uSerp * (0.4 + 0.6 * (1.0 - s)));
        float ph = uTime * uWaveSpeed - s * uWaveFreq;
        float headW = smoothstep(uNeckStart, 1.0, s) * uSway;
        return vec3(sin(ph) * amp + sin(uTime * 0.6) * 0.14 * headW, sin(ph * 0.8 + 1.3) * amp * 0.35 + sin(uTime * 0.9 + 0.7) * 0.07 * headW, 0.0);
      }
      `;
const SCULPT_BODY = `vec3 transformed = vec3(position);
        vObjPos = position; vGlow = aGlow; vBelly = aBelly; vS = aS; vBake = aBake;
        if (aJaw > 0.001) { vec3 q = transformed - uJawHinge; float ja = uJaw * aJaw; float cj = cos(ja), sj = sin(ja); q.yz = mat2(cj, sj, -sj, cj) * q.yz; transformed = uJawHinge + q; }
        transformed += dragonOffset(aS);
        if (abs(aLeg) > 1.5) { float aph = uWalk + (aLeg > 0.0 ? 3.14159 : 0.0); float aw = (abs(aLeg) - 1.0) * clamp((uShoulderY - position.y) / 0.5, 0.0, 1.0);
          transformed.z += sin(aph) * uStride * 0.9 * aw; }
        else if (abs(aLeg) > 0.01) { float lph = uWalk + (aLeg > 0.0 ? 0.0 : 3.14159); float lw = min(abs(aLeg), 1.0) * clamp((uHipY - position.y) / max(uHipY, 0.01), 0.0, 1.0);
          transformed.z += sin(lph) * uStride * lw; transformed.y += max(0.0, cos(lph)) * uStride * 0.45 * lw; }`;

// ---------------------------------------------------------------- creature shading model
// Material identity on top of three's physical BRDF (GGX spec, clearcoat, sheen, iridescence and sky IBL all stay):
//   · wrapped, softly banded diffuse terminator (cel/PBR hybrid: shapes read as lit / shade planes, edges stay soft)
//   · hue-shifted shade: the unlit side keeps a saturated, hue-rotated albedo instead of greying out
//   · red-shifted scattering where light turns into shadow (skin, fur, flesh)
//   · light bleeding through thin parts when back-lit (ears, fins, frills, horn tips) from the baked thickness
//   · baked AO on all indirect light + specular occlusion; cavity-darkened albedo (dark fur roots, dirt in cracks);
//     worn, lighter convex edges from the baked curvature
//   · fur strands, a light-driven fuzz rim, body-long anisotropic sheen for scales, inner glow for jelly
// Presets per kind; every value can be overridden per creature (o.wrap, o.cel, o.shadeCol …).
const CREATURE_KINDS = {
  vinyl: { wrap: 0.3, cel: 0.55, band: 0.1, ao: 0.9, cav: 0.3, edge: 0.15, sss: 0.25, trans: 0.35, fur: 0, aniso: 0, inner: 0, shade: 0.55, rimL: 0.15, shadeCol: [1.02, 0.88, 1.16], sssCol: [1.0, 0.5, 0.36], transCol: [1.2, 0.85, 0.65], cavCol: [0.55, 0.42, 0.5] },
  fur: { wrap: 0.5, cel: 0.62, band: 0.12, ao: 1.0, cav: 0.42, edge: 0.1, sss: 0.42, trans: 0.8, fur: 1, aniso: 0, inner: 0, shade: 0.7, rimL: 0.5, shadeCol: [1.1, 0.8, 1.12], sssCol: [1.0, 0.42, 0.26], transCol: [1.35, 0.72, 0.45], cavCol: [0.46, 0.3, 0.33] },
  wool: { wrap: 0.55, cel: 0.48, band: 0.17, ao: 1.25, cav: 0.55, edge: 0.08, sss: 0.3, trans: 0.4, fur: 0.55, aniso: 0, inner: 0, shade: 0.65, rimL: 0.55, shadeCol: [0.98, 0.88, 1.2], sssCol: [1.0, 0.6, 0.7], transCol: [1.2, 0.9, 1.0], cavCol: [0.62, 0.54, 0.8] },
  skin: { wrap: 0.38, cel: 0.6, band: 0.09, ao: 0.95, cav: 0.32, edge: 0.15, sss: 0.55, trans: 0.65, fur: 0, aniso: 0, inner: 0, shade: 0.6, rimL: 0.15, shadeCol: [0.94, 0.92, 1.2], sssCol: [1.0, 0.45, 0.35], transCol: [1.25, 0.8, 0.6], cavCol: [0.5, 0.45, 0.58] },
  jelly: { wrap: 0.6, cel: 0.35, band: 0.16, ao: 0.45, cav: 0.12, edge: 0.1, sss: 0.5, trans: 1.3, fur: 0, aniso: 0, inner: 0.9, shade: 0.4, rimL: 0.2, shadeCol: [1.08, 0.9, 1.05], sssCol: [1.0, 0.7, 0.3], transCol: [1.25, 1.0, 0.55], cavCol: [0.7, 0.55, 0.45] },
  rock: { wrap: 0.02, cel: 0.8, band: 0.045, ao: 1.5, cav: 0.85, edge: 0.55, sss: 0, trans: 0, fur: 0, aniso: 0, inner: 0, shade: 0.5, rimL: 0, shadeCol: [0.92, 0.95, 1.18], sssCol: [1, 1, 1], transCol: [1, 1, 1], cavCol: [0.34, 0.32, 0.38] },
  plush: { wrap: 0.5, cel: 0.55, band: 0.14, ao: 1.0, cav: 0.38, edge: 0.1, sss: 0.38, trans: 0.55, fur: 0.32, aniso: 0, inner: 0, shade: 0.62, rimL: 0.35, shadeCol: [1.08, 0.86, 1.08], sssCol: [1.0, 0.5, 0.3], transCol: [1.3, 0.9, 0.5], cavCol: [0.55, 0.4, 0.38] },
  scale: { wrap: 0.15, cel: 0.4, band: 0.08, ao: 1.0, cav: 0.55, edge: 0.35, sss: 0.18, trans: 0.4, fur: 0, aniso: 0.6, inner: 0, shade: 0.5, rimL: 0.1, shadeCol: [1.0, 0.88, 1.2], sssCol: [1.0, 0.45, 0.3], transCol: [1.3, 0.85, 0.6], cavCol: [0.4, 0.36, 0.46] },
};
// light loop with the key light's cast-shadow factor and unshadowed colour kept apart (for hue-shifted shade)
const CR_LIGHTS_BEGIN = (() => {
  let s = THREE.ShaderChunk.lights_fragment_begin;
  const a = 'getDirectionalLightInfo( directionalLight, directLight );';
  const b = 'directLight.color *= ( directLight.visible && receiveShadow ) ? getShadow( directionalShadowMap[ i ]';
  const c = 'vDirectionalShadowCoord[ i ] ) : 1.0;';
  if (s.split(a).length === 2 && s.split(b).length === 2 && s.split(c).length === 2) {
    s = s.replace(a, a + '\n\t\tgShK = 1.0; gLc0 = directLight.color;')
      .replace(b, 'gShK = ( directLight.visible && receiveShadow ) ? getShadow( directionalShadowMap[ i ]')
      .replace(c, c + '\n\t\tdirectLight.color *= gShK;');
  }
  return s;
})();
const CR_DECL = `uniform float uWrap, uCel, uBand, uAOk, uCav, uEdge, uSSS, uTrans, uFurK, uFurF, uAniso, uInner, uShadeK, uRimL;
  uniform vec3 uShadeCol, uSSSCol, uTransCol, uCavCol, uInnerCol;
  varying vec3 vBake;
  float gShK = 1.0; vec3 gLc0 = vec3(-1.0); float gLit = 0.0; float gVis = 1.0; float gThin = 0.0; vec3 gAxisV = vec3(0.0, 0.0, 1.0);
  float crLum(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }
`;
// albedo: cavities, worn edges, fur strands (object space, so it sticks to the deforming body)
const CR_ALBEDO = `
  {
    float occ = vBake.x, curv = vBake.y; gThin = vBake.z;
    gVis = clamp(1.0 - occ * uAOk, 0.1, 1.0);
    float cav = clamp(occ * 1.25 + max(-curv, 0.0) * 0.6, 0.0, 1.0) * uCav;
    diffuseColor.rgb = mix(diffuseColor.rgb, diffuseColor.rgb * uCavCol, cav);
    diffuseColor.rgb *= 1.0 + max(curv, 0.0) * uEdge;
    if (uFurK > 0.0) {
      vec3 Pn = vObjPos * uFurF;
      vec3 fl = vec3(0.0, -0.8, -0.6);
      vec3 ps = Pn - fl * dot(Pn, fl) * 0.82;
      float aaF = 1.0 - smoothstep(0.3, 1.0, length(fwidth(ps)));
      float strand = vn3(ps) * 0.62 + vn3(ps * 2.3 + 11.0) * 0.38;
      diffuseColor.rgb *= mix(1.0, 0.78 + 0.44 * strand, uFurK * aaF);
    }
    gAxisV = normalize(normalMatrix * vec3(0.0, 0.0, 1.0));
  }
`;
const CR_BRDF = `
  void RE_Direct_Creature( const in IncidentLight directLight, const in vec3 geometryPosition, const in vec3 geometryNormal, const in vec3 geometryViewDir, const in vec3 geometryClearcoatNormal, const in PhysicalMaterial material, inout ReflectedLight reflectedLight ) {
    vec3 N = geometryNormal, L = directLight.direction, V = geometryViewDir;
    float ndl = dot(N, L);
    // wrapped, two-band diffuse: main terminator + a soft plateau step, blended with the smooth wrap by uCel
    float wr = (ndl + uWrap) / (1.0 + uWrap);
    float b1 = smoothstep(0.04 - uBand, 0.04 + uBand, wr);
    float b2 = smoothstep(0.52 - uBand * 1.5, 0.52 + uBand * 1.5, wr);
    float dif = mix(max(wr, 0.0), b1 * (0.68 + 0.32 * b2), uCel);
    vec3 lc = directLight.color;
    vec3 lc0 = gLc0.r < 0.0 ? lc : gLc0;
    gLit = max(gLit, dif * clamp(crLum(lc) / max(crLum(lc0), 1e-4), 0.0, 1.0));
    vec3 alb = material.diffuseColor;
    reflectedLight.directDiffuse += lc * dif * BRDF_Lambert(alb);
    float tw = smoothstep(-0.5, 0.0, ndl) * (1.0 - smoothstep(0.0, 0.42, ndl));
    reflectedLight.directDiffuse += lc * (tw * uSSS) * BRDF_Lambert(alb * uSSSCol);
    vec3 Lt = normalize(L + N * 0.35);
    float back = pow(clamp(dot(V, -Lt), 0.0, 1.0), 3.0) * 1.6 + clamp(-ndl, 0.0, 1.0) * 0.3;
    reflectedLight.directDiffuse += lc * (back * gThin * gThin * uTrans * 2.5) * BRDF_Lambert(alb * uTransCol);
    float nv = clamp(dot(N, V), 0.0, 1.0);
    float fz = pow(1.0 - nv, 2.5) * smoothstep(-0.25, 0.5, ndl);
    reflectedLight.directDiffuse += lc * (fz * uRimL * 1.6) * BRDF_Lambert(alb + 0.04);
    float dotNL = saturate(ndl);
    vec3 irr = dotNL * lc;
    #ifdef USE_CLEARCOAT
      float dotNLcc = saturate(dot(geometryClearcoatNormal, L));
      clearcoatSpecularDirect += dotNLcc * lc * BRDF_GGX_Clearcoat(L, V, geometryClearcoatNormal, material);
    #endif
    #ifdef USE_SHEEN
      sheenSpecularDirect += irr * BRDF_Sheen(L, V, N, material.sheenColor, material.sheenRoughness);
    #endif
    reflectedLight.directSpecular += irr * BRDF_GGX(L, V, N, material);
    if (uAniso > 0.0) {
      vec3 T = cross(N, gAxisV); float tl = length(T); T = tl > 1e-4 ? T / tl : vec3(1.0, 0.0, 0.0);
      vec3 H = normalize(L + V); float th = dot(T, H);
      float an = pow(sqrt(max(1.0 - th * th, 0.0)), 90.0) * smoothstep(0.0, 0.3, ndl);
      reflectedLight.directSpecular += lc * (an * uAniso * 0.3) * mix(vec3(1.0), alb * 2.0 + 0.25, 0.45);
    }
  }
  #undef RE_Direct
  #define RE_Direct RE_Direct_Creature
`;
// after all light: AO on indirect light (diffuse + specular occlusion), hue-shifted saturated shade on the unlit side
const CR_INDIRECT = `
  {
    vec3 albI = material.diffuseColor;
    vec3 shadeAlb = max(mix(vec3(crLum(albI)), albI, 1.45), 0.0) * uShadeCol;
    vec3 ratio = clamp(shadeAlb / max(albI, vec3(1e-3)), 0.0, 2.0);
    float shk = (1.0 - clamp(gLit, 0.0, 1.0)) * uShadeK;
    reflectedLight.indirectDiffuse *= mix(vec3(1.0), ratio, shk) * gVis;
    float soV = computeSpecularOcclusion(saturate(dot(geometryNormal, geometryViewDir)), gVis, material.roughness);
    reflectedLight.indirectSpecular *= soV;
    #ifdef USE_CLEARCOAT
      clearcoatSpecularIndirect *= soV;
    #endif
    #ifdef USE_SHEEN
      sheenSpecularIndirect *= gVis;
    #endif
  }
`;
function creatureUniforms(o) {
  const K = CREATURE_KINDS[o.kind] || CREATURE_KINDS.vinyl, v = (k, d) => o[k] ?? K[k] ?? d;
  const c = (k) => (typeof o[k] === 'number' ? new THREE.Color(o[k]) : new THREE.Color(...(Array.isArray(o[k]) ? o[k] : K[k])));
  return {
    uWrap: { value: v('wrap') }, uCel: { value: v('cel') }, uBand: { value: v('band') }, uAOk: { value: v('ao') }, uCav: { value: v('cav') }, uEdge: { value: v('edge') },
    uSSS: { value: v('sss') }, uTrans: { value: v('trans') }, uFurK: { value: v('fur') }, uFurF: { value: o.furF ?? 70 }, uAniso: { value: v('aniso') },
    uInner: { value: v('inner') }, uInnerCol: { value: new THREE.Color(o.innerCol ?? o.glow ?? 0xfff2c0) }, uShadeK: { value: v('shade') }, uRimL: { value: v('rimL') },
    uShadeCol: { value: c('shadeCol') }, uSSSCol: { value: c('sssCol') }, uTransCol: { value: c('transCol') }, uCavCol: { value: c('cavCol') },
  };
}

// ---------------------------------------------------------------- body material
function dragonMaterial(o, D) {
  const m = new THREE.MeshPhysicalMaterial({
    vertexColors: true, roughness: o.rough ?? 0.35, metalness: o.metal ?? 0.2,
    clearcoat: o.coat ?? 0.8, clearcoatRoughness: o.coatRough ?? 0.25,
    iridescence: o.irid ?? 0, iridescenceIOR: 1.7, iridescenceThicknessRange: [180, 620],
    sheen: o.sheen ?? 0, sheenColor: new THREE.Color(o.sheenCol ?? 0xffffff), sheenRoughness: 0.5,
    envMapIntensity: o.env ?? 1.1,
  });
  const scales = (o.scaleFreq ?? 5.5) > 0;
  if (!o.kind) o = Object.assign({ kind: scales ? 'scale' : 'vinyl' }, o);
  const U = {
    uTime: Shared.time, uWaveAmp: { value: o.waveAmp ?? 0.28 }, uWaveSpeed: { value: o.waveSpeed ?? 1.4 }, uWaveFreq: { value: o.waveFreq ?? 4.5 },
    uTailStart: { value: D.tailStart ?? 0.35 }, uSerp: { value: o.serp ?? 0 }, uNeckStart: { value: D.neckStart ?? 0.75 }, uSway: { value: 1 },
    uJaw: { value: 0 }, uJawHinge: { value: new THREE.Vector3(...D.jawHinge) },
    uScaleFreq: { value: o.scaleFreq ?? 5.5 }, uBump: { value: o.bump ?? 0.3 }, uBellyCol: { value: new THREE.Color(o.belly ?? 0x888888) },
    uGlowCol: { value: new THREE.Color(o.glow ?? 0xffffff) }, uVein: { value: o.vein ?? 0 }, uGlowAmt: { value: o.glowAmt ?? 2.5 },
    uRimCol: { value: new THREE.Color(o.rim ?? 0xffffff) }, uRimAmt: { value: o.rimAmt ?? 0.4 },
    uStars: { value: o.stars ?? 0 }, uSplit: { value: o.split ? 1 : 0 }, uVoidCol: { value: new THREE.Color(o.voidCol ?? 0x07050d) },
    uStripes: { value: o.stripes ?? 0 }, uFlash: { value: 0 }, uPx: { value: renderer.getPixelRatio() },
    uWalk: { value: 0 }, uStride: { value: 0 }, uHipY: { value: o.hipY ?? 0.5 }, uShoulderY: { value: o.shoulderY ?? 9 }, uHairRing: { value: o.hairRing ?? -1 }, uFuzz: { value: o.fuzz ?? 0 }, uSoft: { value: o.soft ?? 0 }, uSat: { value: o.sat ?? 1 },
  };
  Object.assign(U, creatureUniforms(o));
  if (!Settings.high) U.uFurK.value = 0; // strands are sub-pixel on phones: skip their two noise taps
  m.userData.U = U; m.userData.uFlash = U.uFlash; m.userData.kind = o.kind;
  m.defaultAttributeValues = { aBake: [0, 0, 0] };
  if (scales) m.defines = Object.assign({}, m.defines, { CR_SCALES: '' });
  m.onBeforeCompile = (sh) => {
    Object.assign(sh.uniforms, U);
    sh.vertexShader = SCULPT_DECL + sh.vertexShader
      .replace('#include <beginnormal_vertex>', '#include <beginnormal_vertex>\n vObjN = objectNormal;')
      .replace('#include <begin_vertex>', SCULPT_BODY);
    sh.fragmentShader = `uniform float uTime, uScaleFreq, uBump, uVein, uGlowAmt, uRimAmt, uStars, uSplit, uStripes, uFlash, uPx, uFuzz, uSoft, uSat, uHairRing;
      uniform vec3 uBellyCol, uGlowCol, uRimCol, uVoidCol;
      varying vec3 vObjPos; varying vec3 vObjN; varying float vGlow; varying float vBelly; varying float vS;
      float gScaleH; float gSide; vec3 gScaleGrad; uniform mat3 normalMatrix;
      ${GLSL_NOISE3}
      ${CR_DECL}
      ` + sh.fragmentShader
      .replace('#include <color_fragment>', `#include <color_fragment>
        {
          float bellyW = vBelly * smoothstep(-0.12, -0.55, normalize(vObjN).y);
          #ifdef CR_SCALES
          vec3 SS = vec3(1.0, 1.15, 0.72) * max(uScaleFreq, 0.001);
          vec3 sp = vObjPos * SS;
          vec4 vi; vec3 eg = vorEdgeGrad(sp, vi);
          vec3 vo = vi.xyz;
          float edge = vi.w;
          float te = clamp(edge / 0.24, 0.0, 1.0);
          float hScale = te * te * (3.0 - 2.0 * te);
          float aaS = 1.0 - smoothstep(0.25, 0.9, length(fwidth(sp)));
          gScaleGrad = (6.0 * te * (1.0 - te) / 0.24) * eg * SS * aaS * (1.0 - bellyW);
          hScale = mix(0.8, hScale, aaS);
          float plates = smoothstep(0.0, 0.12, fract(vObjPos.z * 3.2 + vObjPos.y * 0.4)) * smoothstep(1.0, 0.82, fract(vObjPos.z * 3.2 + vObjPos.y * 0.4));
          gScaleH = mix(hScale, plates, bellyW);
          #else
          vec3 vo = vec3(0.5); gScaleH = 1.0; gScaleGrad = vec3(0.0);
          #endif
          diffuseColor.rgb = mix(diffuseColor.rgb, uBellyCol, bellyW);
          gSide = smoothstep(-0.025, 0.025, vObjPos.x) * uSplit;
          diffuseColor.rgb = mix(diffuseColor.rgb, uVoidCol, gSide);
          #ifdef CR_SCALES
          diffuseColor.rgb *= mix(0.5, 1.06, gScaleH) * (0.9 + 0.2 * vo.z);
          #endif
          diffuseColor.rgb = max(mix(vec3(dot(diffuseColor.rgb, vec3(0.3, 0.59, 0.11))), diffuseColor.rgb, uSat), 0.0);
        }
        ${CR_ALBEDO}`)
      .replace('#include <roughnessmap_fragment>', `#include <roughnessmap_fragment>
        roughnessFactor = clamp(mix(roughnessFactor + 0.3, roughnessFactor, gScaleH) + vBake.x * 0.15, 0.04, 1.0);`)
      .replace('#include <normal_fragment_maps>', `#include <normal_fragment_maps>
        {
          vec3 gv = normalMatrix * gScaleGrad * (uBump * 0.012);
          float gl = length(gv); if (gl > 0.6) gv *= 0.6 / gl;
          normal = normalize(normal - (gv - normal * dot(normal, gv)));
        }`)
      .replace('#include <lights_physical_pars_fragment>', '#include <lights_physical_pars_fragment>\n' + CR_BRDF)
      .replace('#include <lights_fragment_begin>', CR_LIGHTS_BEGIN)
      .replace('#include <lights_fragment_end>', '#include <lights_fragment_end>\n' + CR_INDIRECT)
      .replace('#include <emissivemap_fragment>', `#include <emissivemap_fragment>
        {
          float vein = 1.0 - smoothstep(0.0, 0.045, abs(vn3(vObjPos * 1.6 + vec3(0.0, uTime * 0.04, 0.0)) - 0.5));
          vein *= smoothstep(0.2, 0.6, vn3(vObjPos * 0.7 + 7.0));
          float pulse = 0.65 + 0.35 * sin(uTime * 1.7 + vObjPos.z * 1.3);
          totalEmissiveRadiance += uGlowCol * (vein * uVein * pulse * (1.0 - gScaleH * 0.5) + vGlow * uGlowAmt * (0.75 + 0.25 * pulse));
          if (uStripes > 0.0) {
            float band = smoothstep(0.9, 0.97, sin(vS * 110.0)) * smoothstep(0.25, 0.7, abs(normalize(vObjN).x)) * (1.0 - smoothstep(-0.1, -0.5, normalize(vObjN).y));
            float spots = smoothstep(0.8, 0.86, vn3(vObjPos * 5.0));
            totalEmissiveRadiance += uGlowCol * (band * 0.7 + spots * 1.4) * uStripes * pulse;
          }
          if (uStars > 0.0) {
            vec2 fc = gl_FragCoord.xy / uPx; float hs = fract(sin(dot(floor(fc / 3.0), vec2(12.9898, 78.233))) * 43758.5453);
            float st = step(0.975, hs) * smoothstep(0.55, 0.0, length(fract(fc / 3.0) - 0.5)) * (0.5 + 0.5 * sin(uTime * 2.3 + hs * 60.0));
            float neb = vn3(vObjPos * 1.2 + vec3(uTime * 0.03));
            totalEmissiveRadiance += (vec3(1.6) * st + mix(vec3(0.05, 0.08, 0.3), vec3(0.35, 0.15, 0.6), neb) * 0.35) * uStars;
          }
          vec3 vdir = normalize(vViewPosition);
          float ndv = clamp(dot(normal, vdir), 0.0, 1.0);
          float fr = pow(1.0 - ndv, 3.0);
          vec3 rimC = mix(uRimCol, vec3(0.75, 0.35, 1.0), gSide);
          totalEmissiveRadiance += rimC * fr * uRimAmt * mix(1.0, gVis, 0.6);
          totalEmissiveRadiance += diffuseColor.rgb * (uSoft * 0.22 + uFuzz * fr * 0.9) * gVis;
          if (uInner > 0.0) totalEmissiveRadiance += uInnerCol * uInner * (pow(ndv, 1.6) * (0.35 + 0.65 * (1.0 - gThin)) * 0.55 + gThin * 0.25);
          if (uHairRing > 0.0) { float hr = smoothstep(0.022, 0.0, abs(vObjPos.y - uHairRing - 0.025 * sin(atan(vObjPos.x, vObjPos.z) * 7.0))) * smoothstep(-0.1, 0.25, vObjPos.z + 0.2); totalEmissiveRadiance += vec3(0.32, 0.36, 0.48) * hr; }
          if (uSplit > 0.0) totalEmissiveRadiance += mix(vec3(1.6, 1.3, 0.7), vec3(1.2, 0.5, 2.0), 0.5) * exp(-abs(vObjPos.x) * 38.0) * 2.2;
        }`)
      .replace('#include <dithering_fragment>', `#include <dithering_fragment>
        gl_FragColor.rgb = mix(gl_FragColor.rgb, vec3(2.2), uFlash);`);
  };
  m.customProgramCacheKey = () => 'creature-v2' + (scales ? 'S' : '');
  return m;
}

// ---------------------------------------------------------------- wings
function taperTube(points, r0, r1, radial = 7, samples = 18) {
  const curve = new THREE.CatmullRomCurve3(points.map((p) => new THREE.Vector3(...p)));
  const g = new THREE.TubeGeometry(curve, samples, 1, radial, false);
  const pos = g.attributes.position;
  for (let i = 0; i <= samples; i++) {
    const c = curve.getPointAt(i / samples), r = lerp(r0, r1, i / samples);
    for (let j = 0; j <= radial; j++) {
      const k = i * (radial + 1) + j;
      pos.setXYZ(k, c.x + (pos.getX(k) - c.x) * r, c.y + (pos.getY(k) - c.y) * r, c.z + (pos.getZ(k) - c.z) * r);
    }
  }
  return g;
}
const WING_J = { S: [0, 0, 0], E: [1.3, 0.5, -0.3], W: [2.5, 0.9, 0.05], F: [[4.5, 1.55, 0.35], [4.8, 0.7, -0.95], [4.1, -0.1, -2.1], [2.9, -0.5, -2.9]], B: [0.15, -0.38, -2.4] };
function wingGeometry(kind) {
  const J = WING_J, pos = [], uv = [], span = [], mem = [], idx = [];
  const V = (a, b, t) => [lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t)];
  const push = (p, u, v, m) => { pos.push(p[0], p[1], p[2]); uv.push(u, v); span.push(clamp(Math.hypot(p[0], p[1] * 0.4) / 4.8, 0, 1)); mem.push(m); return pos.length / 3 - 1; };
  const grid = (fn, nu, nv, m) => {
    const base = pos.length / 3;
    for (let i = 0; i <= nu; i++) for (let j = 0; j <= nv; j++) { const u = i / nu, v = j / nv; push(fn(u, v), u, v, m); }
    for (let i = 0; i < nu; i++) for (let j = 0; j < nv; j++) {
      const a = base + i * (nv + 1) + j, b = a + nv + 1;
      idx.push(a, b, a + 1, a + 1, b, b + 1);
    }
  };
  const armPt = (u) => (u < 0.5 ? V(J.S, J.E, u * 2) : V(J.E, J.W, (u - 0.5) * 2));
  if (kind !== 'feather') {
    // membranes between the fingers, scalloped trailing edge and a little billow
    for (let f = 0; f < 3; f++) {
      const A = J.F[f], Bf = J.F[f + 1];
      grid((u, v) => {
        const e = V(A, Bf, v), sc = 1 - 0.2 * Math.sin(Math.PI * v) * Math.pow(u, 1.5);
        const p = V(J.W, e, u * sc);
        const sag = Math.sin(Math.PI * v) * Math.sin(Math.PI * u * 0.9) * 0.16;
        return [p[0], p[1] - sag, p[2] - sag * 0.4];
      }, 14, 8, 1);
    }
    grid((u, v) => {
      const top = armPt(u), bot = V(J.B, J.F[3], u);
      const scal = 1 - 0.14 * Math.sin(Math.PI * u) * v;
      const p = V(top, bot, v * scal);
      const sag = Math.sin(Math.PI * v) * Math.sin(Math.PI * u) * 0.22;
      return [p[0], p[1] - sag, p[2] - sag * 0.3];
    }, 16, 10, 1);
  } else {
    // feathers: primaries on the hand, secondaries on the forearm, tertials and coverts near the body
    const feather = (root, dir, L, W, m = 1, lift = 0) => {
      const d = new THREE.Vector3(...dir).normalize(), side = new THREE.Vector3(0, 1, 0).cross(d).normalize();
      if (side.lengthSq() < 0.01) side.set(1, 0, 0);
      const up = new THREE.Vector3().crossVectors(d, side).normalize();
      grid((u, v) => {
        const curl = Math.pow(u, 2) * 0.12;
        const p = new THREE.Vector3(...root).addScaledVector(d, u * L).addScaledVector(side, (v - 0.5) * W).addScaledVector(up, lift - curl);
        return [p.x, p.y, p.z];
      }, 6, 2, m);
    };
    for (let i = 0; i < 15; i++) {
      const t = i / 14, root = V(J.W, J.F[0], t * 0.8);
      const dir = [lerp(1.0, 0.3, t * t), lerp(0.18, -0.15, t), lerp(0.15, -1.0, t)];
      feather(root, dir, lerp(2.6, 1.9, t), 0.85, 2, i * 0.006);
    }
    for (let i = 0; i < 13; i++) { const t = i / 12, root = V(J.E, J.W, t); feather(root, [0.16 + t * 0.25, -0.08, -1], lerp(1.9, 2.3, t), 0.8, 2, 0.02 + (i % 2) * 0.01); }
    for (let i = 0; i < 9; i++) { const t = i / 8, root = V(J.S, J.E, t); feather(root, [0.08, -0.12, -1], lerp(1.5, 1.85, t), 0.75, 2, 0.03 + (i % 2) * 0.01); }
    for (let i = 0; i < 18; i++) { const t = i / 17, root = armPt(t); feather(root, [0.15, -0.05, -1], 1.0, 0.62, 3, 0.07); }
    for (let i = 0; i < 18; i++) { const t = i / 17, root = armPt(t); feather(root, [0.15, 0, -1], 0.58, 0.52, 3, 0.1); }
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  g.setAttribute('aSpan', new THREE.Float32BufferAttribute(span, 1));
  g.setAttribute('aMem', new THREE.Float32BufferAttribute(mem, 1));
  g.setIndex(idx); g.computeVertexNormals();
  // bones: arm + fingers as tapered tubes
  const bones = [taperTube([J.S, J.E, J.W], 0.12, 0.07)];
  if (kind === 'feather') bones.push(taperTube([J.W, V(J.W, J.F[0], 0.8)], 0.07, 0.03));
  else {
    for (const F of J.F) bones.push(taperTube([J.W, V(J.W, F, 0.5), F], 0.06, 0.012));
    bones.push(taperTube([J.W, [J.W[0] + 0.15, J.W[1] + 0.25, J.W[2] + 0.2]], 0.05, 0.004, 6, 4));
  }
  const parts = [g];
  for (const b of bones) {
    b.deleteAttribute('uv');
    const n = b.attributes.position.count, sp = new Float32Array(n), mm = new Float32Array(n), uvs = new Float32Array(n * 2);
    for (let i = 0; i < n; i++) { const x = b.attributes.position.getX(i), y = b.attributes.position.getY(i); sp[i] = clamp(Math.hypot(x, y * 0.4) / 4.8, 0, 1); }
    b.setAttribute('aSpan', new THREE.BufferAttribute(sp, 1)); b.setAttribute('aMem', new THREE.BufferAttribute(mm, 1)); b.setAttribute('uv', new THREE.BufferAttribute(uvs, 2));
    parts.push(b.index ? b.toNonIndexed() : b);
  }
  const ni = parts.map((p) => (p.index ? p.toNonIndexed() : p));
  return mergeGeometries(ni, false);
}
function mirrorGeometry(g) {
  const m = g.clone(), p = m.attributes.position, n = m.attributes.normal;
  for (let i = 0; i < p.count; i++) { p.setX(i, -p.getX(i)); n.setX(i, -n.getX(i)); }
  for (let i = 0; i < p.count; i += 3) { // flip winding of non-indexed triangles
    for (const att of Object.values(m.attributes)) {
      const s = att.itemSize, a = att.array;
      for (let k = 0; k < s; k++) { const t = a[(i + 1) * s + k]; a[(i + 1) * s + k] = a[(i + 2) * s + k]; a[(i + 2) * s + k] = t; }
    }
  }
  return m;
}
const _wingGeo = {};
function getWing(kind, side) {
  const k = kind + side;
  if (!_wingGeo[k]) { const base = _wingGeo[kind + 1] || (_wingGeo[kind + 1] = wingGeometry(kind)); _wingGeo[k] = side > 0 ? base : mirrorGeometry(base); }
  return _wingGeo[k];
}
function wingMaterial(o, side) {
  const m = new THREE.MeshStandardMaterial({ color: o.col ?? 0x553344, roughness: o.rough ?? 0.6, metalness: o.metal ?? 0.05, side: THREE.DoubleSide, envMapIntensity: 0.8 });
  const U = {
    uTime: Shared.time, uSide: { value: side }, uFlapBase: { value: 0.25 }, uFlapAmp: { value: 0.5 }, uFlapSpeed: { value: 2.2 },
    uStyle: { value: { membrane: 0, void: 1, nebula: 2, feather: 3, fin: 4 }[o.style] ?? 0 },
    uMemCol: { value: new THREE.Color(o.mem ?? 0x8a3a3a) }, uEdgeCol: { value: new THREE.Color(o.edge ?? 0xff8a3d) }, uBoneCol: { value: new THREE.Color(o.bone ?? 0x222222) },
    uFlash: { value: 0 }, uPx: { value: renderer.getPixelRatio() },
  };
  m.userData.U = U; m.userData.uFlash = U.uFlash; m.userData.noAO = true;
  m.onBeforeCompile = (sh) => {
    Object.assign(sh.uniforms, U);
    sh.vertexShader = `uniform float uTime, uSide, uFlapBase, uFlapAmp, uFlapSpeed; attribute float aSpan; attribute float aMem; varying float vMem; varying vec2 vUv2; varying float vSpan;
      mat3 wingRot(float sp){
        float a = uSide * (uFlapBase + uFlapAmp * sin(uTime * uFlapSpeed - sp * 1.35) * (0.3 + 0.7 * sp));
        float b = -uSide * 0.18 * sp * sin(uTime * uFlapSpeed - sp * 1.35 + 1.2);
        float ca = cos(a), sa = sin(a), cb = cos(b), sb = sin(b);
        mat3 rz = mat3(ca, sa, 0.0, -sa, ca, 0.0, 0.0, 0.0, 1.0);
        mat3 ry = mat3(cb, 0.0, -sb, 0.0, 1.0, 0.0, sb, 0.0, cb);
        return ry * rz;
      }
      ` + sh.vertexShader
      .replace('#include <beginnormal_vertex>', '#include <beginnormal_vertex>\n mat3 WR = wingRot(aSpan); objectNormal = WR * objectNormal;')
      .replace('#include <begin_vertex>', '#include <begin_vertex>\n transformed = WR * transformed; vMem = aMem; vUv2 = uv; vSpan = aSpan;');
    sh.fragmentShader = `uniform float uTime, uStyle, uFlash, uPx; uniform vec3 uMemCol, uEdgeCol, uBoneCol; varying float vMem; varying vec2 vUv2; varying float vSpan;
      ${GLSL_NOISE3}
      ` + sh.fragmentShader
      .replace('#include <color_fragment>', `#include <color_fragment>
        float wEdge = 0.0; float wStar = 0.0;
        if (vMem < 0.5) { diffuseColor.rgb = uBoneCol; }
        else if (vMem < 1.5) {
          float veins = smoothstep(0.92, 1.0, sin(vUv2.y * 40.0 + sin(vUv2.x * 9.0) * 1.5)) * 0.6 + smoothstep(0.95, 1.0, sin(vUv2.x * 26.0)) * 0.4;
          diffuseColor.rgb = mix(uMemCol, uMemCol * 0.45, veins);
          wEdge = smoothstep(0.82, 1.0, vUv2.x);
          if (uStyle > 0.5 && uStyle < 1.5 && vUv2.x > 0.55 && vn3(vec3(vUv2 * 9.0, 1.0)) > 0.74) discard;
        } else {
          float w = 1.0 - pow(abs(vUv2.y - 0.5) * 2.0, 2.0);
          float shape = 0.3 + 0.7 * pow(sin(3.14159 * min(vUv2.x * 1.04, 1.0)), 0.5);
          if (abs(vUv2.y - 0.5) * 2.0 > shape) discard;
          float shaft = smoothstep(0.06, 0.0, abs(vUv2.y - 0.5));
          float barbs = 0.85 + 0.15 * sin((vUv2.x * 60.0) + abs(vUv2.y - 0.5) * 40.0);
          diffuseColor.rgb = mix(uMemCol * barbs, uEdgeCol, shaft * 0.6) * (0.75 + 0.25 * w);
          wEdge = smoothstep(0.7, 1.0, vUv2.x) * 0.8 + smoothstep(0.35, 0.5, abs(vUv2.y - 0.5)) * 0.4;
        }`)
      .replace('#include <emissivemap_fragment>', `#include <emissivemap_fragment>
        {
          totalEmissiveRadiance += uEdgeCol * wEdge * (uStyle > 2.5 && uStyle < 3.5 ? 0.9 : 1.6) * (0.7 + 0.3 * sin(uTime * 2.0 + vSpan * 4.0));
          if (vMem > 1.5) totalEmissiveRadiance += diffuseColor.rgb * 0.38;
          if (vMem > 0.5 && vMem < 1.5) {
            #if NUM_DIR_LIGHTS > 0
              // membrane: the sun shines through it (strongest looking toward the light), veins block it
              vec3 Ld = directionalLights[0].direction;
              float back = max(dot(-normal, Ld), 0.0);
              float through = pow(clamp(dot(normalize(vViewPosition), -Ld), 0.0, 1.0), 3.0);
              float vT = smoothstep(0.92, 1.0, sin(vUv2.y * 40.0 + sin(vUv2.x * 9.0) * 1.5)) * 0.6 + smoothstep(0.95, 1.0, sin(vUv2.x * 26.0)) * 0.4;
              totalEmissiveRadiance += uMemCol * back * 0.55;
              totalEmissiveRadiance += uMemCol * vec3(1.25, 0.95, 0.8) * directionalLights[0].color * (back * 0.06 + through * 0.22) * (1.0 - vT * 0.8) * (0.4 + 0.6 * vSpan);
            #endif
            if (uStyle > 0.5 && uStyle < 2.5) {
              vec2 fc = gl_FragCoord.xy / uPx; float hs = fract(sin(dot(floor(fc / 3.0), vec2(12.9898, 78.233))) * 43758.5453);
              float st = step(0.97, hs) * smoothstep(0.55, 0.0, length(fract(fc / 3.0) - 0.5)) * (0.5 + 0.5 * sin(uTime * 2.0 + hs * 50.0));
              float neb = vn3(vec3(vUv2 * 3.0, uTime * 0.05));
              totalEmissiveRadiance += vec3(1.5) * st + (uStyle > 1.5 ? mix(vec3(0.05, 0.1, 0.4), vec3(0.5, 0.2, 0.8), neb) * 0.9 : uEdgeCol * neb * 0.25);
            }
            if (uStyle > 3.5) totalEmissiveRadiance += uEdgeCol * smoothstep(0.9, 1.0, sin(vUv2.y * 30.0)) * 1.2;
          }
        }`)
      .replace('#include <dithering_fragment>', '#include <dithering_fragment>\n gl_FragColor.rgb = mix(gl_FragColor.rgb, vec3(2.2), uFlash);');
  };
  m.customProgramCacheKey = () => 'wing-v2';
  return m;
}

// ---------------------------------------------------------------- environment reflections from a sky
let _pmrem = null;
function envFromSky(U) {
  if (!_pmrem) _pmrem = new THREE.PMREMGenerator(renderer);
  const sc = new THREE.Scene(); const sky = makeSky(U); sc.add(sky);
  const rt = _pmrem.fromScene(sc, 0.02, 0.1, 1000);
  sky.traverse((o) => { if (o.material && o.material.isSpriteMaterial) o.material.dispose(); });
  return rt;
}

// ---------------------------------------------------------------- assemble a dragon rig
function slitEye(parent, pos, r, color) {
  const g = grp(parent, pos, [0, pos[0] < 0 ? -0.55 : 0.55, 0]);
  part(GEO.sphere, dragonEyeMat(color, pos[0] < 0 ? -1 : 1), g, [0, 0, 0], [r * 1.1, r * 0.78, r * 0.85]).userData.noOl = true;
  return g;
}
function buildDragon(r, cfg) {
  const D = cfg.design;
  r.olw = 0; r.noBreath = true; r.float = cfg.float ?? 1.0; r.floatAmp = cfg.floatAmp ?? 0.18; r.hopAmp = 0.2;
  const B = grp(r.body); B.scale.setScalar(cfg.scale);
  const geo = dragonGeometry(cfg.key, D), mat = dragonMaterial(cfg.mat, D);
  const body = new THREE.Mesh(geo, mat); body.castShadow = true; body.receiveShadow = true; B.add(body);
  const U = mat.userData.U;
  r.dragon = { D, U, mat, wings: [] };
  const follow = [];
  const glue = (obj, s) => follow.push({ obj, base: obj.position.clone(), s });
  for (const e of D.eyes) glue(slitEye(B, e, D.eyeR || 0.06, cfg.eye ?? 0xffd27a), 1);
  if (D.eyeRows) for (const e of D.eyeRows) glue(slitEye(B, e, 0.05, cfg.eye ?? 0x9ff8ff), 1);
  if (cfg.wings) {
    for (const side of [-1, 1]) {
      const w = cfg.wings[side < 0 ? 0 : 1];
      const wm = wingMaterial(w, side), wg = getWing(w.style === 'feather' ? 'feather' : 'membrane', side);
      const mesh = new THREE.Mesh(wg, wm); mesh.castShadow = true;
      const pivot = grp(B, [side * D.wingRoot[0], D.wingRoot[1], D.wingRoot[2]]);
      pivot.scale.setScalar(w.scale ?? 1); pivot.add(mesh);
      r.dragon.wings.push(wm);
    }
  }
  r.setFlight = (mode) => {
    const p = { fly: [0.22, 0.55, 2.2], hover: [0.35, 0.42, 1.7], perch: [0.95, 0.06, 1.0], glide: [0.12, 0.12, 0.9] }[mode] || [0.35, 0.42, 1.7];
    for (const wm of r.dragon.wings) { wm.userData.U.uFlapBase.value = p[0]; wm.userData.U.uFlapAmp.value = p[1]; wm.userData.U.uFlapSpeed.value = p[2]; }
  };
  r.setFlight(cfg.flight || 'hover');
  r.roar = () => Tw.add(1.2, (k) => { U.uJaw.value = Math.sin(k * Math.PI) * 0.55; }, ease.lin);
  r.fns.push((t) => {
    for (const f of follow) f.obj.position.copy(f.base).add(dragonOffset(U, f.s, Shared.time.value));
    if (!r.jawBusy && Math.random() < 0.002) { r.jawBusy = true; Tw.add(0.9, (k) => { U.uJaw.value = Math.sin(k * Math.PI) * 0.22; }, ease.lin).then(() => { r.jawBusy = false; }); }
  });
  r.glue = glue; r.B = B;
  r.size = D.height * cfg.scale * 0.92;
  return B;
}


// ---------------------------------------------------------------- animated outline for sculpted bodies
// Inverted hull that follows every vertex deformation (same SCULPT_BODY as the body). The authored width is in object
// units, but the hull is clamped to a screen-space band (≈0.9–2.6 px at 900 px tall), so lines stay clean and
// unbroken at battle distance and never turn into thick borders in close-ups. The ink is a dark, saturated version
// of the local albedo (coloured line art), blended with the given line colour.
const CS_RES = { value: new THREE.Vector2(1280, 720) };
const _csRes = new THREE.Vector2();
function sculptOutline(mesh, width, color = 0x1a1226, o = {}) {
  const U = mesh.material.userData.U;
  const m = new THREE.MeshBasicMaterial({ color, side: THREE.BackSide });
  m.userData.noAO = true;
  m.defaultAttributeValues = { aBake: [0, 0, 0], color: [1, 1, 1] };
  const OU = { uOlW: { value: width }, uOlRes: CS_RES, uOlMin: { value: o.minPx ?? 0.9 }, uOlMax: { value: o.maxPx ?? 2.6 }, uOlInk: { value: o.ink ?? 0.5 } };
  m.userData.OU = OU;
  m.onBeforeCompile = (sh) => {
    Object.assign(sh.uniforms, U, OU);
    sh.vertexShader = SCULPT_DECL + 'uniform float uOlW, uOlMin, uOlMax; uniform vec2 uOlRes; varying vec3 vInk; float gOlPx = 0.0;\n#ifndef USE_COLOR\nattribute vec3 color;\n#endif\n' + sh.vertexShader
      .replace('#include <begin_vertex>', SCULPT_BODY + `
        vInk = color;
        {
          vec3 nO = normalize(normal);
          vec4 mv0 = modelViewMatrix * vec4(transformed, 1.0);
          float sN = max(length(mat3(modelViewMatrix) * nO), 1e-5);
          float depth = projectionMatrix[3][3] > 0.5 ? 1.0 : max(-mv0.z, 0.01);
          gOlPx = 2.0 * depth / (projectionMatrix[1][1] * max(uOlRes.y, 1.0));
          float ref = max(uOlRes.y / 900.0, 0.6);
          float wPx = uOlW * sN / gOlPx;
          float tPx = clamp(wPx, uOlMin * ref, uOlMax * ref);
          transformed += nO * (tPx * gOlPx / sN);
        }`)
      .replace('#include <project_vertex>', `#include <project_vertex>
        gl_Position = projectionMatrix * vec4(mvPosition.xyz + normalize(mvPosition.xyz) * gOlPx * 2.0, 1.0);`);
    sh.fragmentShader = 'uniform float uOlInk; varying vec3 vInk;\n' + sh.fragmentShader.replace('#include <color_fragment>', `#include <color_fragment>
      {
        vec3 inkC = max(mix(vec3(dot(vInk, vec3(0.2126, 0.7152, 0.0722))), vInk, 1.3), 0.0);
        diffuseColor.rgb = mix(diffuseColor.rgb, inkC * inkC * 0.2 + diffuseColor.rgb * 0.35, uOlInk);
      }`);
  };
  m.customProgramCacheKey = () => 'sculptOl-v2';
  const ol = new THREE.Mesh(mesh.geometry, m);
  ol.userData.isOl = true; ol.castShadow = false; ol.raycast = () => {};
  ol.onBeforeRender = (rr) => { rr.getDrawingBufferSize(_csRes); if (_csRes.y > 0) CS_RES.value.copy(_csRes); };
  mesh.add(ol); return ol;
}

// ---------------------------------------------------------------- eyes: gaze, cornea, catch-lights
// Gaze: every eye material calls eyeGaze() from onBeforeRender. The target (rig.gazeAt / any ancestor's
// userData.gazeAt — an Object3D or Vector3 — else the camera that is drawing, so portraits and close-ups look at the
// viewer) is taken into the eye group's frame and turned into an iris offset (the eyeball's rotation). Offsets toward
// the nose are clamped tighter than outward ones, so a pair converges on near targets but never goes cross- or
// wall-eyed; targets behind the head fade back to a neutral stare. Both eyes of a face share one saccade generator
// (keyed by the face group): a small conjugate jump every 1–3 s.
const _gzV = new THREE.Vector3(), _gzM = new THREE.Matrix4(), _gzSac = new WeakMap();
function eyeGaze(object, camera, uGaze, side = 1, lim = {}) {
  const eg = object.parent; if (!eg || !uGaze) return;
  const face = eg.parent || eg;
  let tgt = null;
  for (let o = face, k = 0; o && k < 8 && !tgt; o = o.parent, k++) {
    const g = (o.userData && o.userData.gazeAt) || (o.userData && o.userData.rig && o.userData.rig.gazeAt);
    if (g) tgt = g.isObject3D ? g.getWorldPosition(_gzV) : _gzV.copy(g);
  }
  if (!tgt) tgt = _gzV.setFromMatrixPosition(camera.matrixWorld);
  tgt.applyMatrix4(_gzM.copy(eg.matrixWorld).invert());
  const l = tgt.length() || 1, dx = tgt.x / l, dy = tgt.y / l, dz = tgt.z / l;
  const w = sstep(0.0, 0.5, dz);
  const k = lim.gain ?? 0.9, mIn = lim.inward ?? 0.15, mOut = lim.outward ?? 0.24, mUp = lim.up ?? 0.12, mDn = lim.down ?? 0.16;
  // side: +1 when the eye's outer corner is local +x; inward = toward the nose
  let gx = dx * k, gy = dy * k;
  gx = side > 0 ? clamp(gx, -mIn, mOut) : clamp(gx, -mOut, mIn);
  gy = clamp(gy, -mDn, mUp);
  const now = Shared.time.value;
  let S = _gzSac.get(face);
  if (!S) { S = { t: now + Math.random() * 2, x: 0, y: 0 }; _gzSac.set(face, S); }
  if (now > S.t || now < S.t - 6) {
    S.t = now + 1 + Math.random() * 2;
    const still = Math.random() < 0.3;
    S.x = still ? 0 : (Math.random() - 0.5) * 0.09; S.y = still ? 0 : (Math.random() - 0.5) * 0.06;
  }
  uGaze.value.set((gx + S.x) * w, (gy + S.y) * w);
}
// shared eye GLSL: object-space view vector (for cornea refraction) without inverse(), and view-space catch-lights
const EYE_V = `varying vec3 vN; varying vec3 vNv; varying vec3 vVo; varying vec3 vVp; varying vec2 vKey;
  void eyeVaryings(vec3 pos) {
    vN = pos;
    vec4 mv = modelViewMatrix * vec4(pos, 1.0); vVp = mv.xyz;
    vNv = normalize(normalMatrix * pos);
    mat3 m3 = mat3(modelViewMatrix); vec3 s2 = max(vec3(dot(m3[0], m3[0]), dot(m3[1], m3[1]), dot(m3[2], m3[2])), vec3(1e-8));
    vec3 vv = -mv.xyz; vVo = vec3(dot(m3[0], vv), dot(m3[1], vv), dot(m3[2], vv)) / s2;
    // the studio key light (upper left of the screen) projected into this eye's own plane
    vec3 Lv = vec3(-0.6, 0.66, 0.45); vec3 Lo = vec3(dot(m3[0], Lv), dot(m3[1], Lv), dot(m3[2], Lv)) / s2;
    vKey = Lo.xy;
  }
`;
const EYE_F = `varying vec3 vN; varying vec3 vNv; varying vec3 vVo; varying vec3 vVp; varying vec2 vKey;
  // point on the iris plane (depth d below the apex of the unit eyeball) seen through the cornea
  vec2 eyeIris(vec3 n, float d) {
    vec3 V = normalize(vVo);
    vec3 rd = refract(-V, n, 0.75);
    float t = max(n.z - (1.0 - d), 0.0) / max(-rd.z, 0.3);
    return n.xy + rd.xy * t;
  }
  // catch-lights on the cornea, placed around the visible iris centre c (radius IR) from one screen-space studio key
  // (upper left) — the same direction on both eyes, never mirrored, never smaller than ~1.5 px so they read at range.
  // x: key highlight, y: small bounce highlight (lower right), z: cornea fresnel
  vec3 eyeCatch(vec2 p, vec2 c, float IR, float px) {
    vec2 k = vKey; float kl = length(k); k = kl > 1e-4 ? k / kl : vec2(-0.7, 0.7);
    vec2 d1 = p - (c + k * IR * 0.4);
    vec2 r1v = vec2(k.x * d1.x + k.y * d1.y, -k.y * d1.x + k.x * d1.y) / vec2(0.82, 1.0);
    float r1 = max(IR * 0.24, px * 1.6);
    vec2 d2 = p - (c - k * IR * 0.5 + vec2(k.y, -k.x) * IR * 0.14);
    float r2 = max(IR * 0.1, px * 1.0);
    float fr = pow(1.0 - clamp(dot(normalize(vNv), normalize(-vVp)), 0.0, 1.0), 3.0);
    return vec3(smoothstep(r1 + px, r1 - px, length(r1v)), smoothstep(r2 + px, r2 - px, length(d2)), fr);
  }
`;
// anime eye (people): lids, thick upper lash line, iris fibres seen through a refracting cornea, lid shadow, gaze,
// view-space catch-lights, uniform-driven blink. Options (all optional): iris, iris2, skin, lash, side, irisR (iris
// radius in eye units, 0.52), pupil (fraction of the iris, 0.48), cornea (parallax depth, 0.36), gaze (false = fixed stare)
function animeEye(o = {}) {
  const U = { uIris: { value: new THREE.Color(o.iris ?? 0x2a1a4a) }, uIris2: { value: new THREE.Color(o.iris2 ?? 0x8a6aff) }, uSkin: { value: new THREE.Color(o.skin ?? 0xffe0cc) }, uLash: { value: new THREE.Color(o.lash ?? 0x1a1020) },
    uBlink: { value: 0 }, uSide: { value: o.side ?? 1 }, uGaze: { value: new THREE.Vector2() }, uIrisR: { value: o.irisR ?? 0.52 }, uPupil: { value: o.pupil ?? 0.48 }, uDepth: { value: o.cornea ?? 0.36 } };
  const m = new THREE.ShaderMaterial({
    uniforms: THREE.UniformsUtils.merge([THREE.UniformsLib.fog]),
    vertexShader: `${EYE_V} ${FOG_V}
      void main(){ eyeVaryings(normalize(position)); vec4 mvPosition = modelViewMatrix * vec4(position, 1.0); gl_Position = projectionMatrix * mvPosition;
        #include <fog_vertex>
      }`,
    fragmentShader: `uniform vec3 uIris, uIris2, uSkin, uLash; uniform float uBlink, uSide, uIrisR, uPupil, uDepth; uniform vec2 uGaze; ${EYE_F} ${FOG_F}
      void main(){
        vec3 n = normalize(vN); vec2 q = vec2(n.x * uSide, n.y);
        float front = step(0.0, n.z);
        float px = max(length(fwidth(n.xy)), 1e-4);
        float topOpen = 0.6 - 0.42 * q.x * q.x + 0.1 * q.x;
        float top = mix(topOpen, -0.5 + 0.2 * q.x * q.x, uBlink);
        float bot = -0.6 + 0.32 * q.x * q.x;
        vec3 col = uSkin * (0.82 + 0.12 * n.y);
        if (front > 0.5 && q.y < top && q.y > bot && abs(q.x) < 0.92) {
          float lidSh = smoothstep(top, top - 0.32, q.y);
          col = vec3(0.98, 0.97, 1.0) * mix(0.66, 1.0, lidSh) * (0.84 + 0.16 * n.z);
          vec2 ip = eyeIris(n, uDepth) - uGaze;
          vec2 ic = vec2(0.0, -0.06); vec2 d = ip - ic; float r = length(d), IR = uIrisR;
          float aaI = smoothstep(0.35, 0.12, px);
          if (r < IR + px) {
            float t = r / IR, ang = atan(d.y, d.x);
            vec3 base = mix(uIris2 * 1.4, uIris * 0.78, smoothstep(-0.5, 0.35, d.y));
            base *= 1.0 + (0.14 * sin(ang * 28.0 + t * 8.0) + 0.06 * sin(ang * 63.0 - t * 5.0)) * (0.6 + 0.4 * t) * aaI;
            base += uIris2 * 0.4 * smoothstep(0.55, 0.85, t) * smoothstep(0.1, -0.4, d.y);
            base = mix(base, uIris * 0.16, smoothstep(0.8, 1.0, t));
            base *= mix(0.42, 1.0, lidSh);
            float pr = IR * uPupil;
            base = mix(base, vec3(0.015, 0.01, 0.03), smoothstep(pr + px, pr - px, r));
            col = mix(col, base, smoothstep(IR + px, IR - px, r));
          }
          vec3 ct = eyeCatch(n.xy, ic + uGaze, IR, px);
          col += vec3(0.55, 0.62, 0.75) * ct.z * 0.35 * lidSh;
          col = mix(col, vec3(1.45), ct.x * (1.0 - uBlink));
          col = mix(col, vec3(1.15), ct.y * 0.85 * (1.0 - uBlink));
        }
        float lw = 0.075 + 0.07 * smoothstep(-0.2, 0.8, q.x);
        float lash = front * smoothstep(lw, lw * 0.4, abs(q.y - top - lw * 0.45)) * step(-0.9, q.x) * step(q.x, 0.98);
        lash = max(lash, front * smoothstep(0.06, 0.02, length(q - vec2(0.92, top + 0.06 + 0.12 * (1.0 - uBlink)))) * (1.0 - uBlink));
        col = mix(col, uLash, lash);
        float ll = front * smoothstep(0.03, 0.0, abs(q.y - bot)) * step(abs(q.x), 0.55) * 0.55 * (1.0 - uBlink);
        col = mix(col, uLash, ll);
        gl_FragColor = vec4(col, 1.0);
        #include <fog_fragment>
      }`,
    fog: true,
  });
  Object.assign(m.uniforms, U);
  m.userData.blink = U.uBlink; m.userData.gaze = U.uGaze;
  if (o.gaze !== false) m.onBeforeRender = (rr, sc, cam, geo, obj) => eyeGaze(obj, cam, U.uGaze, U.uSide.value, { inward: 0.12, outward: 0.2, up: 0.1, down: 0.12 });
  return m;
}
// dragon eye: glowing iris with radial veins under a refracting cornea, vertical slit pupil that follows the gaze,
// darker lid-shaded top, wet view-space catch-lights
function dragonEyeMat(color, side = 1) {
  const U = { uCol: { value: new THREE.Color(color) }, uTime: Shared.time, uGaze: { value: new THREE.Vector2() } };
  const m = new THREE.ShaderMaterial({
    uniforms: U,
    vertexShader: `${EYE_V} void main(){ eyeVaryings(normalize(position)); gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }`,
    fragmentShader: `uniform vec3 uCol; uniform float uTime; uniform vec2 uGaze; ${EYE_F}
      void main(){
        vec3 n = normalize(vN);
        if (n.z < 0.0) { gl_FragColor = vec4(uCol * 0.3, 1.0); return; }
        float px = max(length(fwidth(n.xy)), 1e-4);
        vec2 q = eyeIris(n, 0.5) - uGaze;
        float r = length(q), ang = atan(q.y, q.x);
        float aa = smoothstep(0.4, 0.15, px);
        vec3 c = uCol * (1.2 + 1.6 * smoothstep(0.9, 0.1, r)) * (1.0 + 0.15 * sin(ang * 22.0 + r * 9.0) * aa);
        c += uCol * 0.8 * smoothstep(0.42, 0.18, abs(r - 0.32)) * aa * 0.4;
        c = mix(c, uCol * 0.12, smoothstep(0.78, 0.98, r));
        float slit = smoothstep(0.13 + px, 0.05, abs(q.x) / (1.0 - q.y * q.y * 0.6 + 0.001)) * smoothstep(0.95, 0.7, abs(q.y));
        c = mix(c, vec3(0.01, 0.0, 0.02), slit * (0.9 + 0.1 * sin(uTime * 0.7)));
        c *= mix(1.0, 0.3, smoothstep(0.3, 0.85, n.y));
        vec3 ct = eyeCatch(n.xy, uGaze, 0.72, px);
        c += vec3(0.5, 0.55, 0.65) * ct.z * 0.5;
        c = mix(c, vec3(2.2), ct.x);
        c = mix(c, vec3(1.4), ct.y * 0.8);
        gl_FragColor = vec4(c, 1.0);
      }`,
  });
  m.userData.gaze = U.uGaze;
  m.onBeforeRender = (rr, sc, cam, geo, obj) => eyeGaze(obj, cam, U.uGaze, side, { gain: 0.7, inward: 0.12, outward: 0.2, up: 0.08, down: 0.12 });
  return m;
}

// ---------------------------------------------------------------- anime toon skin for sculpted people
const toonGradSoft = (() => {
  const d = new Uint8Array([118, 118, 205, 255]);
  const t = new THREE.DataTexture(d, 4, 1, THREE.RedFormat); t.minFilter = t.magFilter = THREE.NearestFilter; t.needsUpdate = true; return t;
})();
// Backward compatible: same signature and defaults; adds baked AO (contact shading under hair, chin, arms, folds) on
// indirect light and lightly on direct light, cavity-darkened albedo, and a hue-shifted (saturated, slightly cool)
// shade on the unlit side. New options: ao (0.8), cav (0.3), shade (0.35), shadeCol ([0.95, 0.9, 1.14]).
function sculptToonMaterial(o, D) {
  const m = new THREE.MeshToonMaterial({ vertexColors: true, gradientMap: toonGradSoft });
  const U = {
    uTime: Shared.time, uWaveAmp: { value: o.waveAmp ?? 0 }, uWaveSpeed: { value: 1 }, uWaveFreq: { value: 3 }, uTailStart: { value: D.tailStart ?? 0.01 }, uSerp: { value: 0 },
    uNeckStart: { value: D.neckStart ?? 0.95 }, uSway: { value: 0.2 }, uJaw: { value: 0 }, uJawHinge: { value: new THREE.Vector3(...(D.jawHinge || [0, 0, 0])) },
    uWalk: { value: 0 }, uStride: { value: 0 }, uHipY: { value: o.hipY ?? 0.6 }, uShoulderY: { value: o.shoulderY ?? 9 },
    uHairRing: { value: o.hairRing ?? -1 }, uSat: { value: o.sat ?? 1.15 }, uFlash: { value: 0 }, uRim2: { value: new THREE.Color(o.rim ?? 0xfff4e0) }, uRimAmt2: { value: o.rimAmt ?? 0.35 },
    uWarm: { value: o.warm ?? 0 },
    uTAO: { value: o.ao ?? 0.8 }, uTCav: { value: o.cav ?? 0.3 }, uTShade: { value: o.shade ?? 0.35 }, uTShadeCol: { value: new THREE.Color(...(o.shadeCol || [0.95, 0.9, 1.14])) },
  };
  m.userData.U = U; m.userData.uFlash = U.uFlash;
  m.defaultAttributeValues = { aBake: [0, 0, 0] };
  m.onBeforeCompile = (sh) => {
    Object.assign(sh.uniforms, U);
    sh.uniforms.uRim = Look.rim; sh.uniforms.uRimStr = Look.rimStr; sh.uniforms.uSpec = Look.spec;
    sh.vertexShader = SCULPT_DECL + sh.vertexShader
      .replace('#include <beginnormal_vertex>', '#include <beginnormal_vertex>\n vObjN = objectNormal;')
      .replace('#include <begin_vertex>', SCULPT_BODY);
    sh.fragmentShader = `uniform float uHairRing, uSat, uFlash, uRimAmt2, uRimStr, uSpec, uWarm, uTAO, uTCav, uTShade; uniform vec3 uRim2, uRim, uTShadeCol; varying vec3 vObjPos; varying vec3 vObjN; varying vec3 vBake;
      ` + sh.fragmentShader
      .replace('#include <color_fragment>', `#include <color_fragment>
        diffuseColor.rgb = max(mix(vec3(dot(diffuseColor.rgb, vec3(0.3, 0.59, 0.11))), diffuseColor.rgb, uSat), 0.0);
        diffuseColor.rgb *= 1.0 - clamp(vBake.x * 1.2 + max(-vBake.y, 0.0) * 0.6, 0.0, 1.0) * uTCav * 0.6;
        diffuseColor.rgb *= 1.0 + max(vBake.y, 0.0) * 0.12;`)
      .replace('#include <opaque_fragment>', `
        {
          vec3 vdir = normalize(vViewPosition);
          float fr = pow(1.0 - clamp(dot(normal, vdir), 0.0, 1.0), 3.0);
          float gVisT = clamp(1.0 - vBake.x * uTAO, 0.15, 1.0);
          float rimBand = smoothstep(0.42, 0.5, fr);
          // how much key light reaches this pixel (0 on the shade side and inside cast shadows)
          float litK = clamp(dot(reflectedLight.directDiffuse, vec3(0.333)) / max(dot(diffuseColor.rgb, vec3(0.333)), 0.002) * 1.6, 0.0, 1.0);
          // baked AO: full on ambient, a little on the key so creases under hair / chin / arms stay grounded
          outgoingLight -= reflectedLight.indirectDiffuse * (1.0 - gVisT) + reflectedLight.directDiffuse * (1.0 - gVisT) * 0.3;
          // hue-shifted shade: saturated, slightly cool albedo on the unlit side
          vec3 alb = diffuseColor.rgb, shA = max(mix(vec3(dot(alb, vec3(0.2126, 0.7152, 0.0722))), alb, 1.4), 0.0) * uTShadeCol;
          outgoingLight += reflectedLight.indirectDiffuse * gVisT * (clamp(shA / max(alb, vec3(1e-3)), 0.0, 2.0) - 1.0) * (1.0 - litK) * uTShade;
          outgoingLight += uRim2 * rimBand * uRimAmt2 * (0.5 + 0.5 * diffuseColor.rgb) * mix(0.4, 1.0, gVisT);
          // anime-style warm shadow: the unlit side is filled with a peach tone instead of cold sky ambient
          outgoingLight += diffuseColor.rgb * vec3(0.34, 0.17, 0.11) * (1.0 - litK) * uWarm * gVisT;
          #if NUM_DIR_LIGHTS > 0
            vec3 hv = normalize(directionalLights[0].direction + vdir);
            outgoingLight += directionalLights[0].color * smoothstep(0.965, 0.98, dot(normal, hv)) * uSpec * 0.25 * litK;
          #endif
          if (uHairRing > 0.0) {
            // soft "angel ring": a broad sheen band broken into strands, strongest where the hair faces the light
            float ang = atan(vObjPos.x, vObjPos.z);
            float band = smoothstep(0.05, 0.0, abs(vObjPos.y - uHairRing - 0.03 * sin(ang * 7.0)));
            float strands = 0.45 + 0.55 * smoothstep(0.2, 0.9, sin(ang * 23.0 + vObjPos.y * 40.0) * 0.5 + 0.5);
            float hr = band * strands * smoothstep(-0.1, 0.25, vObjPos.z + 0.2);
            outgoingLight += mix(vec3(0.2, 0.22, 0.3), diffuseColor.rgb * 2.2 + 0.08, 0.5) * hr * 0.55;
          }
        }
        #include <opaque_fragment>`)
      .replace('#include <dithering_fragment>', '#include <dithering_fragment>\n gl_FragColor.rgb = mix(gl_FragColor.rgb, vec3(2.2), uFlash);');
  };
  m.customProgramCacheKey = () => 'sculptToon-v4';
  return m;
}
