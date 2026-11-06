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
  g.setIndex(new THREE.BufferAttribute(m.idx, 1));
  g.computeBoundingSphere(); g.boundingSphere.radius *= 1.3;
  _dragonGeo[ck] = g; return g;
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
  const U = {
    uTime: Shared.time, uWaveAmp: { value: o.waveAmp ?? 0.28 }, uWaveSpeed: { value: o.waveSpeed ?? 1.4 }, uWaveFreq: { value: o.waveFreq ?? 4.5 },
    uTailStart: { value: D.tailStart ?? 0.35 }, uSerp: { value: o.serp ?? 0 }, uNeckStart: { value: D.neckStart ?? 0.75 }, uSway: { value: 1 },
    uJaw: { value: 0 }, uJawHinge: { value: new THREE.Vector3(...D.jawHinge) },
    uScaleFreq: { value: o.scaleFreq ?? 5.5 }, uBump: { value: o.bump ?? 0.3 }, uBellyCol: { value: new THREE.Color(o.belly ?? 0x888888) },
    uGlowCol: { value: new THREE.Color(o.glow ?? 0xffffff) }, uVein: { value: o.vein ?? 0 }, uGlowAmt: { value: o.glowAmt ?? 2.5 },
    uRimCol: { value: new THREE.Color(o.rim ?? 0xffffff) }, uRimAmt: { value: o.rimAmt ?? 0.4 },
    uStars: { value: o.stars ?? 0 }, uSplit: { value: o.split ? 1 : 0 }, uVoidCol: { value: new THREE.Color(o.voidCol ?? 0x07050d) },
    uStripes: { value: o.stripes ?? 0 }, uFlash: { value: 0 }, uPx: { value: renderer.getPixelRatio() },
    uWalk: { value: 0 }, uStride: { value: 0 }, uHipY: { value: o.hipY ?? 0.5 }, uShoulderY: { value: o.shoulderY ?? 9 }, uFuzz: { value: o.fuzz ?? 0 }, uSoft: { value: o.soft ?? 0 }, uSat: { value: o.sat ?? 1 },
  };
  m.userData.U = U; m.userData.uFlash = U.uFlash;
  m.onBeforeCompile = (sh) => {
    Object.assign(sh.uniforms, U);
    sh.vertexShader = `uniform float uTime, uWaveAmp, uWaveSpeed, uWaveFreq, uTailStart, uSerp, uNeckStart, uSway, uJaw, uWalk, uStride, uHipY, uShoulderY; uniform vec3 uJawHinge;
      attribute float aS; attribute float aJaw; attribute float aGlow; attribute float aBelly; attribute float aLeg;
      varying vec3 vObjPos; varying vec3 vObjN; varying float vGlow; varying float vBelly; varying float vS;
      vec3 dragonOffset(float s){
        float tailW = 1.0 - smoothstep(0.0, uTailStart, s);
        float amp = uWaveAmp * (tailW * tailW + uSerp * (0.4 + 0.6 * (1.0 - s)));
        float ph = uTime * uWaveSpeed - s * uWaveFreq;
        float headW = smoothstep(uNeckStart, 1.0, s) * uSway;
        return vec3(sin(ph) * amp + sin(uTime * 0.6) * 0.14 * headW, sin(ph * 0.8 + 1.3) * amp * 0.35 + sin(uTime * 0.9 + 0.7) * 0.07 * headW, 0.0);
      }
      ` + sh.vertexShader
      .replace('#include <beginnormal_vertex>', '#include <beginnormal_vertex>\n vObjN = objectNormal;')
      .replace('#include <begin_vertex>', `vec3 transformed = vec3(position);
        vObjPos = position; vGlow = aGlow; vBelly = aBelly; vS = aS;
        if (aJaw > 0.001) { vec3 q = transformed - uJawHinge; float ja = uJaw * aJaw; float cj = cos(ja), sj = sin(ja); q.yz = mat2(cj, sj, -sj, cj) * q.yz; transformed = uJawHinge + q; }
        transformed += dragonOffset(aS);
        if (abs(aLeg) > 1.5) { float aph = uWalk + (aLeg > 0.0 ? 3.14159 : 0.0); float aw = (abs(aLeg) - 1.0) * clamp((uShoulderY - position.y) / 0.5, 0.0, 1.0);
          transformed.z += sin(aph) * uStride * 0.9 * aw; }
        else if (abs(aLeg) > 0.01) { float lph = uWalk + (aLeg > 0.0 ? 0.0 : 3.14159); float lw = min(abs(aLeg), 1.0) * clamp((uHipY - position.y) / max(uHipY, 0.01), 0.0, 1.0);
          transformed.z += sin(lph) * uStride * lw; transformed.y += max(0.0, cos(lph)) * uStride * 0.45 * lw; }`);
    sh.fragmentShader = `uniform float uTime, uScaleFreq, uBump, uVein, uGlowAmt, uRimAmt, uStars, uSplit, uStripes, uFlash, uPx, uFuzz, uSoft, uSat;
      uniform vec3 uBellyCol, uGlowCol, uRimCol, uVoidCol;
      varying vec3 vObjPos; varying vec3 vObjN; varying float vGlow; varying float vBelly; varying float vS;
      float gScaleH; float gSide; vec3 gScaleGrad; uniform mat3 normalMatrix;
      ${GLSL_NOISE3}
      ` + sh.fragmentShader
      .replace('#include <color_fragment>', `#include <color_fragment>
        {
          float bellyW = vBelly * smoothstep(-0.12, -0.55, normalize(vObjN).y);
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
          if (uScaleFreq <= 0.0) { gScaleH = 1.0; gScaleGrad = vec3(0.0); }
          diffuseColor.rgb = mix(diffuseColor.rgb, uBellyCol, bellyW);
          gSide = smoothstep(-0.025, 0.025, vObjPos.x) * uSplit;
          diffuseColor.rgb = mix(diffuseColor.rgb, uVoidCol, gSide);
          diffuseColor.rgb *= uScaleFreq > 0.0 ? mix(0.5, 1.06, gScaleH) * (0.9 + 0.2 * vo.z) : 1.0;
          diffuseColor.rgb = max(mix(vec3(dot(diffuseColor.rgb, vec3(0.3, 0.59, 0.11))), diffuseColor.rgb, uSat), 0.0);
        }`)
      .replace('#include <roughnessmap_fragment>', `#include <roughnessmap_fragment>
        roughnessFactor = clamp(mix(roughnessFactor + 0.3, roughnessFactor, gScaleH), 0.04, 1.0);`)
      .replace('#include <normal_fragment_maps>', `#include <normal_fragment_maps>
        {
          vec3 gv = normalMatrix * gScaleGrad * (uBump * 0.012);
          float gl = length(gv); if (gl > 0.6) gv *= 0.6 / gl;
          normal = normalize(normal - (gv - normal * dot(normal, gv)));
        }`)
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
          float fr = pow(1.0 - clamp(dot(normal, vdir), 0.0, 1.0), 3.0);
          vec3 rimC = mix(uRimCol, vec3(0.75, 0.35, 1.0), gSide);
          totalEmissiveRadiance += rimC * fr * uRimAmt;
          totalEmissiveRadiance += diffuseColor.rgb * (uSoft * 0.22 + uFuzz * fr * 0.9);
          if (uSplit > 0.0) totalEmissiveRadiance += mix(vec3(1.6, 1.3, 0.7), vec3(1.2, 0.5, 2.0), 0.5) * exp(-abs(vObjPos.x) * 38.0) * 2.2;
        }`)
      .replace('#include <dithering_fragment>', `#include <dithering_fragment>
        gl_FragColor.rgb = mix(gl_FragColor.rgb, vec3(2.2), uFlash);`);
  };
  m.customProgramCacheKey = () => 'dragon-v1';
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
              float back = max(dot(-normal, directionalLights[0].direction), 0.0);
              totalEmissiveRadiance += uMemCol * back * 0.55;
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
  m.customProgramCacheKey = () => 'wing-v1';
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
  const g = grp(parent, pos);
  part(GEO.sphere, E(color, 3.2), g, [0, 0, 0], [r * 1.05, r * 0.72, r * 0.9]).userData.noOl = true;
  part(GEO.box, new THREE.MeshBasicMaterial({ color: 0x050208 }), g, [0, 0, r * 0.62], [r * 0.2, r * 1.2, r * 0.2]);
  part(GEO.sphere, E(0xffffff, 3.5), g, [r * 0.35, r * 0.3, r * 0.72], r * 0.16);
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
