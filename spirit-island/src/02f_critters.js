// ============================================================================
//  critters: sculpted (signed-distance) bodies for every regular spirit,
//  soft PBR "vinyl figure" skin with fur sheen, painted markings, glowing type
//  accents, a per-pixel face layer (mouth, nose glint, blush, brows, crest mark)
//  and lens-shaped anime eyes that blink shut into a lash curve
// ============================================================================
function animeEyeMat(iris = 0x2a1a4a, iris2 = 0x7a5aff) {
  const k = 'eye' + iris + '_' + iris2;
  if (_mc.has(k)) return _mc.get(k);
  const m = new THREE.ShaderMaterial({
    uniforms: THREE.UniformsUtils.merge([THREE.UniformsLib.fog, { uIris: { value: new THREE.Color(iris) }, uIris2: { value: new THREE.Color(iris2) } }]),
    vertexShader: `varying vec3 vN; ${FOG_V}
      void main(){ vN = normalize(position); vec4 mvPosition = modelViewMatrix * vec4(position, 1.0); gl_Position = projectionMatrix * mvPosition;
        #include <fog_vertex>
      }`,
    fragmentShader: `uniform vec3 uIris, uIris2; varying vec3 vN; ${FOG_F}
      void main(){
        vec3 n = normalize(vN);
        float rr = length(n.xy);
        vec3 col = vec3(0.97, 0.97, 1.0) * (0.82 + 0.18 * n.y);
        if (n.z > 0.0 && rr < 0.66) {
          float t = rr / 0.66;
          vec3 ic = mix(uIris2 * 1.25, uIris, smoothstep(-0.55, 0.55, n.y));
          ic *= 0.85 + 0.15 * sin(atan(n.y, n.x) * 22.0 + t * 6.0);
          ic = mix(ic, uIris * 0.25, smoothstep(0.78, 1.0, t));
          col = ic;
          if (rr < 0.3) col = vec3(0.02, 0.012, 0.04);
        }
        col = mix(col, vec3(1.25), smoothstep(0.15, 0.11, length(n.xy - vec2(0.2, 0.3))) * step(0.0, n.z));
        col = mix(col, vec3(1.05), smoothstep(0.075, 0.05, length(n.xy - vec2(-0.2, -0.24))) * step(0.0, n.z) * 0.9);
        col *= mix(0.62, 1.0, smoothstep(0.88, 0.58, n.y));
        gl_FragColor = vec4(col, 1.0);
        #include <fog_fragment>
      }`,
    fog: true,
  });
  _mc.set(k, m); return m;
}

// ---------------------------------------------------------------- critter eye
// Only the lens-shaped opening (plus the lash line) of the eye sphere is drawn; everything else is cut away with
// alpha-to-coverage so the sculpted face (with its carved socket) shows through. The iris lies on a plane behind a
// refracting cornea (parallax: the eye reads as a wet, deep ball) and rotates with the gaze (see eyeGaze in 02d);
// catch-lights come from one view-space key light, so both eyes agree. Lids: blink lowers a skin-coloured upper lid
// over the eyeball into a "‿" lash curve, a happy squint raises the lower lid into an arch, a hit squeezes them shut.
function critterEye(o = {}) {
  const U = {
    uIris: { value: new THREE.Color(o.iris ?? 0x2a1a4a) }, uIris2: { value: new THREE.Color(o.iris2 ?? 0x8a6aff) },
    uLash: { value: new THREE.Color(o.lash ?? 0x1c1018) }, uBlink: { value: 0 }, uSide: { value: o.side ?? 1 },
    // x: opening half-height, y: outer-corner lift, z: lash wing, w: iris radius
    uShape: { value: new THREE.Vector4(o.open ?? 0.8, o.tilt ?? 0.05, o.wing ?? 0.5, o.irisR ?? 0.6) },
    uGlow: { value: o.glow ?? 0 }, uSlit: { value: o.slit ?? 0 }, uFlash: { value: 0 },
    uGaze: { value: new THREE.Vector2() }, uExpr: { value: new THREE.Vector2() }, uSkin: { value: new THREE.Color(o.skin ?? 0xd8c8c0) },
    uPupil: { value: o.pupil ?? 1 }, uDepth: { value: o.cornea ?? 0.42 },
  };
  const m = new THREE.ShaderMaterial({
    uniforms: THREE.UniformsUtils.merge([THREE.UniformsLib.fog]),
    vertexShader: `${EYE_V} ${FOG_V}
      void main(){ eyeVaryings(position); vec4 mvPosition = modelViewMatrix * vec4(position, 1.0); gl_Position = projectionMatrix * mvPosition;
        #include <fog_vertex>
      }`,
    fragmentShader: `uniform vec3 uIris, uIris2, uLash, uSkin; uniform float uBlink, uSide, uGlow, uSlit, uFlash, uPupil, uDepth; uniform vec4 uShape; uniform vec2 uGaze, uExpr; ${EYE_F} ${FOG_F}
      float cov(float sd, float pw) { return clamp(0.5 - sd / pw, 0.0, 1.0); }
      void main(){
        vec3 n = normalize(vN);
        if (n.z < 0.02) discard;
        vec2 q = vec2(n.x * uSide, n.y);
        float pw = max(max(fwidth(q.x), fwidth(q.y)), 1e-4);
        float H = uShape.x, tilt = uShape.y, IR = uShape.w;
        float xx = clamp(q.x / 0.9, -1.0, 1.0);
        float arc = sqrt(max(1.0 - pow(abs(xx), 2.6), 0.0));
        float topO = H * arc + tilt * xx + 0.03, botO = -H * 0.86 * arc + tilt * xx * 0.4;
        // closed-lid lines: blink "‿", hit squeeze (tilted crease), happy squint arch "∩"
        float hap = uExpr.x, hurt = uExpr.y, cl = max(uBlink, hurt);
        float shutB = -0.1 - 0.16 * arc, shutS = -0.05 - 0.08 * arc + 0.12 * xx, shutH = -0.2 + 0.36 * arc;
        float shut = mix(shutB, shutS, clamp(hurt / max(cl, 1e-3), 0.0, 1.0));
        float top = mix(topO, shut, cl), bot = mix(botO, shut - 0.002, cl);
        bot = mix(bot, max(shutH, bot), hap); top = mix(top, max(top * 0.7 + shutH * 0.3, bot + 0.02), hap);
        float lensSD = max(max(q.y - topO, botO - q.y), abs(q.x) - 0.9);
        float openA = cov(lensSD, pw);
        float inside = cov(max(max(q.y - top, bot - q.y), abs(q.x) - 0.9), pw);
        // sclera: a ball (darker toward the corners), the upper lid's soft shadow band, cool lower half
        float lidSh = smoothstep(top - 0.36, top - 0.02, q.y);
        vec3 col = vec3(0.98, 0.97, 1.0) * mix(1.0, 0.58, lidSh) * (0.8 + 0.2 * n.z);
        col = mix(col, vec3(0.84, 0.86, 0.98), smoothstep(-0.2, -0.75, q.y) * 0.35);
        // iris on a plane behind the cornea, rotated by the gaze; never mirrored between the eyes
        vec2 ip = eyeIris(n, uDepth) - uGaze;
        vec2 d = (ip - vec2(0.0, -0.05)) / vec2(1.0, 1.1);
        float r = length(d), t = r / IR, ang = atan(d.y, d.x);
        float aaI = smoothstep(0.35, 0.15, pw);
        vec3 ir = mix(uIris2 * 1.3, uIris * 0.78, smoothstep(-0.6, 0.5, d.y / IR));
        ir *= 1.0 + (0.16 * sin(ang * 26.0 + t * 7.0) + 0.07 * sin(ang * 59.0 - t * 4.0)) * smoothstep(0.3, 0.75, t) * aaI;
        ir += uIris2 * 1.1 * smoothstep(0.5, 0.86, t) * smoothstep(0.05, -0.65, d.y / IR) * (1.0 - smoothstep(0.9, 1.0, t));
        ir += uIris2 * 0.3 * smoothstep(0.5, 0.56, t) * (1.0 - smoothstep(0.56, 0.7, t)) * aaI;
        ir = mix(ir, uIris * 0.2, smoothstep(0.8, 0.99, t));
        float pr = uSlit > 0.5 ? length(vec2(d.x / (0.17 * IR * uPupil), d.y / (0.8 * IR))) : r / (0.44 * IR * uPupil);
        ir = mix(ir, vec3(0.025, 0.014, 0.04), smoothstep(1.06, 0.92, pr));
        ir *= mix(1.0, 0.42, lidSh) * (1.0 + uGlow);
        col = mix(col, ir, cov(r - IR, pw));
        // wet cornea: sky sheen at grazing angles + catch-lights (key upper-left, small bounce lower-right)
        vec3 ct = eyeCatch(n.xy, vec2(0.0, -0.05) + uGaze, IR, pw);
        col += vec3(0.5, 0.58, 0.72) * ct.z * 0.3 * (1.0 - lidSh * 0.6);
        col = mix(col, vec3(1.55), ct.x * (1.0 - cl) * (1.0 - hap * 0.4));
        col = mix(col, vec3(1.2), ct.y * 0.9 * (1.0 - cl));
        // lids: skin over the eyeball wherever the lids have closed over the open lens
        vec3 skin = uSkin * (0.78 + 0.22 * n.z) * (0.88 + 0.14 * n.y);
        skin *= 1.0 - 0.3 * smoothstep(0.12, 0.0, abs(q.y - top)) * (1.0 - inside);
        col = mix(skin, col, inside);
        // lash: thick upper line growing toward the outer corner (never thinner than ~1px), wing flick, thin lower lash
        float lw = max(mix(0.045, 0.1, smoothstep(-0.8, 0.9, q.x)) * (1.0 - 0.25 * cl), pw * 0.55);
        float upper = cov(abs(q.y - top - lw * 0.3) - lw, pw) * smoothstep(0.99, 0.93, abs(q.x));
        vec2 w = q - vec2(0.9, top + 0.05); w = vec2(w.x * 0.8 + w.y * 0.6, -w.x * 0.6 + w.y * 0.8);
        float wing = cov((length(w / vec2(0.15, 0.045)) - 0.85) * 0.045, pw) * uShape.z;
        float lower = cov(abs(q.y - bot) - max(0.03, pw * 0.4), pw) * smoothstep(-0.25, 0.35, q.x) * smoothstep(0.92, 0.8, q.x) * 0.8 * (1.0 - cl);
        lower = max(lower, cov(abs(q.y - bot) - max(0.035, pw * 0.5), pw) * hap * smoothstep(0.92, 0.6, abs(q.x)));
        float lash = max(max(upper, wing), lower);
        col = mix(col, uLash, lash);
        float a = max(openA, lash);
        if (a < 0.02) discard;
        col = mix(col, vec3(2.2), uFlash);
        gl_FragColor = vec4(col, a);
        #include <tonemapping_fragment>
        #include <colorspace_fragment>
        #include <fog_fragment>
      }`,
    fog: true,
  });
  Object.assign(m.uniforms, U);
  m.alphaToCoverage = true;
  m.userData.blink = U.uBlink; m.userData.uFlash = U.uFlash; m.userData.gaze = U.uGaze; m.userData.expr = U.uExpr; m.userData.skin = U.uSkin;
  if (o.gaze !== false) m.onBeforeRender = (rr, sc, cam, geo, obj) => eyeGaze(obj, cam, U.uGaze, U.uSide.value, o.gazeLim || {});
  return m;
}

// ---------------------------------------------------------------- face layer on the body material
// Object-space decals evaluated per pixel, so they stay crisp and follow every vertex deformation.
const CRITTER_FACE_DECL = `uniform vec4 uMouth, uNose, uBlush, uBrow, uMark; uniform float uMouthK, uMarkK, uBrowTilt, uHatch, uBlushEdge, uBlushA;
  uniform vec3 uLineCol, uBlushCol, uBrowCol, uMarkCol, uMarkGlow; vec3 gDecalE;
`;
const CRITTER_FACE = `
  {
    vec3 P = vObjPos; vec3 Nn = normalize(vObjN);
    gDecalE = vec3(0.0);
    float fw = max(length(fwidth(P.xy)), 1e-4);
    float frontN = smoothstep(0.0, 0.3, Nn.z);
    if (uMouthK > 0.5 && uMouth.w > 0.0) {
      vec2 d = (P.xy - uMouth.xy) / uMouth.w; float pw = fw / uMouth.w;
      float zm = frontN * step(uMouth.z, P.z);
      if (uMouthK < 1.5) {
        vec2 a = vec2(abs(d.x) - 0.5, d.y);
        float arc = a.y < 0.0 ? abs(length(a) - 0.5) : min(length(a - vec2(-0.5, 0.0)), length(a - vec2(0.5, 0.0)));
        float ph = length(vec2(d.x, d.y - clamp(d.y, 0.0, 0.5)));
        float sd = min(arc, ph) - 0.12;
        diffuseColor.rgb = mix(diffuseColor.rgb, uLineCol, (1.0 - smoothstep(-pw, pw, sd)) * zm);
      } else if (uMouthK < 2.5) {
        float arc = abs(length(d - vec2(0.0, 0.6)) - 0.8) - 0.11;
        float m = (1.0 - smoothstep(-pw, pw, arc)) * smoothstep(0.86, 0.7, abs(d.x)) * step(d.y, 0.5);
        diffuseColor.rgb = mix(diffuseColor.rgb, uLineCol, m * zm);
      } else {
        float sd = max(length(vec2(d.x, d.y * 1.2)) - 0.9, d.y - 0.12);
        float tg = smoothstep(1.0 + pw * 2.0, 1.0 - pw * 2.0, length((d - vec2(0.0, -0.62)) / vec2(0.58, 0.36)));
        vec3 mc = mix(vec3(0.32, 0.05, 0.09), vec3(1.0, 0.42, 0.5), tg);
        float fill = 1.0 - smoothstep(-pw, pw, sd);
        float edge = 1.0 - smoothstep(0.1 - pw, 0.1 + pw, abs(sd));
        diffuseColor.rgb = mix(diffuseColor.rgb, mc, fill * zm);
        diffuseColor.rgb = mix(diffuseColor.rgb, uLineCol, edge * zm);
      }
    }
    if (uNose.w > 0.0) {
      float ng = smoothstep(uNose.w, uNose.w * 0.2, length(P - uNose.xyz));
      diffuseColor.rgb = mix(diffuseColor.rgb, vec3(1.0), ng * 0.5);
      gDecalE += vec3(1.0, 0.97, 0.94) * ng * 0.7;
    }
    if (uBlush.w > 0.0) {
      vec2 bq = (vec2(abs(P.x), P.y) - uBlush.xy) / vec2(uBlush.w, uBlush.w * 0.58);
      float e = length(bq);
      float bm = smoothstep(1.0, uBlushEdge, e) * step(uBlush.z, P.z) * smoothstep(-0.3, 0.2, Nn.z);
      diffuseColor.rgb = mix(diffuseColor.rgb, uBlushCol, bm * uBlushA);
      float hs = smoothstep(0.55, 0.9, sin((bq.x * 0.85 - bq.y * 0.5) * 7.5 + 1.2)) * smoothstep(0.8, 0.35, e) * step(abs(bq.x), 0.75);
      diffuseColor.rgb = mix(diffuseColor.rgb, uBlushCol * vec3(0.85, 0.55, 0.6), hs * uHatch * step(uBlush.z, P.z) * 0.8);
    }
    if (uBrow.w > 0.0) {
      vec2 c = vec2(abs(P.x), P.y) - uBrow.xy;
      float cs = cos(uBrowTilt), sn = sin(uBrowTilt);
      c = vec2(c.x * cs + c.y * sn, -c.x * sn + c.y * cs);
      float sd = length(vec2(max(abs(c.x) - uBrow.w, 0.0), c.y)) - uBrow.w * 0.42;
      diffuseColor.rgb = mix(diffuseColor.rgb, uBrowCol, (1.0 - smoothstep(-fw, fw, sd)) * step(uBrow.z, P.z) * frontN);
    }
    if (uMarkK > 0.5 && uMark.w > 0.0) {
      vec2 d = (P.xy - uMark.xy) / uMark.w; float pw = fw / uMark.w;
      float sd;
      if (uMarkK < 1.5) {
        float wob = 0.12 * sin(d.y * 4.0 + 1.0) * smoothstep(-0.3, 0.9, d.y);
        float hw = 0.5 * (1.0 - (d.y + 0.35) / 1.35);
        sd = min(length(d - vec2(0.0, -0.35)) - 0.5, max(abs(d.x + wob) - hw, max(-0.35 - d.y, d.y - 1.0)));
        float side = min(length(d - vec2(0.62, -0.42)) - 0.22, max(abs(d.x - 0.62) - 0.22 * (1.0 - (d.y + 0.42) / 0.7), max(-0.42 - d.y, d.y - 0.28)));
        float side2 = min(length(d - vec2(-0.62, -0.42)) - 0.22, max(abs(d.x + 0.62) - 0.22 * (1.0 - (d.y + 0.42) / 0.7), max(-0.42 - d.y, d.y - 0.28)));
        sd = min(sd, min(side, side2));
      } else if (uMarkK < 2.5) {
        sd = max(length(d) - 1.0, -(length(d - vec2(0.42, 0.3)) - 0.86));
      } else if (uMarkK < 3.5) {
        float hw = 0.55 * (1.0 - (d.y + 0.3) / 1.3);
        sd = min(length(d - vec2(0.0, -0.3)) - 0.55, max(abs(d.x) - hw, max(-0.3 - d.y, d.y - 1.0)));
      } else {
        sd = (abs(d.x) * 1.7 + abs(d.y) - 1.0) * 0.6;
      }
      float mk = (1.0 - smoothstep(-pw, pw, sd)) * step(uMark.z, P.z) * frontN;
      diffuseColor.rgb = mix(diffuseColor.rgb, uMarkCol, mk);
      gDecalE += uMarkGlow * mk;
    }
  }
`;
function critterSkin(mat, F = {}) {
  const U = mat.userData.U, v4 = (a) => new THREE.Vector4(...(a || [0, 0, 0, 0]));
  Object.assign(U, {
    uMouth: { value: v4(F.mouth) }, uMouthK: { value: F.mouth ? (F.mouthK ?? 1) : 0 }, uLineCol: { value: new THREE.Color(F.line ?? 0x2a1216) },
    uNose: { value: v4(F.nose) }, uBlush: { value: v4(F.blush) }, uBlushCol: { value: new THREE.Color(F.blushCol ?? 0xff7f96) }, uHatch: { value: F.hatch ?? 1 }, uBlushEdge: { value: F.blushEdge ?? 0.15 }, uBlushA: { value: F.blushA ?? 0.6 },
    uBrow: { value: v4(F.brow) }, uBrowTilt: { value: F.browTilt ?? 0 }, uBrowCol: { value: new THREE.Color(F.browCol ?? 0x3a1a14) },
    uMark: { value: v4(F.mark) }, uMarkK: { value: F.mark ? (F.markK ?? 1) : 0 }, uMarkCol: { value: new THREE.Color(F.markCol ?? 0xffd27a) }, uMarkGlow: { value: new THREE.Color(F.markGlow ?? 0x000000) },
  });
  const ob = mat.onBeforeCompile;
  mat.onBeforeCompile = (sh, rr) => {
    ob(sh, rr);
    Object.assign(sh.uniforms, U);
    sh.fragmentShader = CRITTER_FACE_DECL + sh.fragmentShader
      .replace('#include <alphamap_fragment>', CRITTER_FACE + '\n#include <alphamap_fragment>')
      .replace('#include <lights_physical_fragment>', 'totalEmissiveRadiance += gDecalE;\n#include <lights_physical_fragment>');
  };
  mat.customProgramCacheKey = () => 'critter-skin-v2';
  return mat;
}

// ---------------------------------------------------------------- one-time vertex paint (markings + glow accents)
const tintV = (v, c, t) => { if (!(t > 0)) return; if (t > 1) t = 1; v.c[0] += (c[0] - v.c[0]) * t; v.c[1] += (c[1] - v.c[1]) * t; v.c[2] += (c[2] - v.c[2]) * t; };
const shadeV = (v, k) => { v.c[0] *= k; v.c[1] *= k; v.c[2] *= k; };
function paintCritter(geo, fn) {
  if (geo.userData.painted) return;
  geo.userData.painted = true;
  const P = geo.attributes.position.array, N = geo.attributes.normal.array, C = geo.attributes.color.array, G = geo.attributes.aGlow.array;
  const v = { x: 0, y: 0, z: 0, nx: 0, ny: 0, nz: 0, c: [0, 0, 0], g: 0 };
  for (let i = 0, n = P.length / 3; i < n; i++) {
    const i3 = i * 3;
    v.x = P[i3]; v.y = P[i3 + 1]; v.z = P[i3 + 2]; v.nx = N[i3]; v.ny = N[i3 + 1]; v.nz = N[i3 + 2];
    v.c[0] = C[i3]; v.c[1] = C[i3 + 1]; v.c[2] = C[i3 + 2]; v.g = G[i];
    fn(v);
    C[i3] = v.c[0]; C[i3 + 1] = v.c[1]; C[i3 + 2] = v.c[2]; G[i] = v.g;
  }
  geo.attributes.color.needsUpdate = true; geo.attributes.aGlow.needsUpdate = true;
}

function critterKit() {
  const prims = [], c = (h) => hexRGB(h);
  return {
    prims,
    el(p, r, col, o = {}) { prims.push(SDF.el(p, r, Object.assign({ k: 0.06, s0: 0.5, s1: 0.5, col: c(col), hex: col }, o))); },
    rc(a, b, r1, r2, col, o = {}) { prims.push(SDF.rc(a, b, r1, r2, Object.assign({ k: 0.05, s0: 0.5, s1: 0.5, col: c(col), hex: col }, o))); },
    sub(p, r, k = 0.03) { prims.push(SDF.el(p, r, { k, sub: true })); },
    // pointed fur tuft from a (root, buried in the body) to b (tip)
    tuft(a, b, r, col, o = {}) { prims.push(SDF.rc(a, b, r, r * 0.14, Object.assign({ k: 0.035, s0: 0.5, s1: 0.5, col: c(col), hex: col }, o))); },
  };
}
const HEAD = { s0: 1, s1: 1 };
const add3 = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
const _critterDesigns = {};
function critter(key, fn) { if (!_critterDesigns[key]) _critterDesigns[key] = fn(); return _critterDesigns[key]; }

// ============================================================================
//  MAINLINE SPIRIT LOOK — clean sculpt → flat colour regions → soft cel shading, data-driven per species.
//  A species opts in by giving its design a `look` (see SPIRIT_MATS / SPIRIT_SHADE below):
//    look.kind   default region material ('fur' | 'skin' | 'water' | 'leaf' | …) and shading preset
//    look.mats   { [primHex]: material } per colour region (e.g. the nose glossy, antlers horn, leaves satin)
//    look.over   overlay markings [{ col, sd(v) → signed distance in object units (negative inside), mat?, em?, soft? }]
//    look.shade  overrides of the species shading (tint = hue-shifted shadow multiplier, mid band, rim …)
//  1. spiritGeometry: surface nets → Taubin smoothing → projection onto the EXACT sculpt field (every vertex on the
//     true smooth surface: no stair-steps, lumps or wobbly outlines; creases the sculpt intends stay crisp) →
//     tangential relaxation → normals from the exact field gradient (clean, curved terminators).
//  2. Regions: every distinct prim colour is a class; per vertex the distance to each class and the signed distance
//     of each overlay are stored (3 × vec4). The fragment shader resolves them per pixel with a ~1 px antialiased
//     edge, so colour boundaries are clean curves — no vertex-colour blur, no noise, no baked blotches.
//  3. spiritMaterial: 2-tone cel (+ narrow mid band) from the scene's key light incl. its cast shadow, hemisphere /
//     ambient fill, per-species hue-shifted shadow, subtle sky+sun rim, one shaped specular on glossy regions only,
//     small emissive accents. Same shader on phones (no post needed).
// ============================================================================
const SPIRIT_SLOTS = 12;
// per region material: [emissive, specular strength, specular size (1 − N·H threshold), terminator half-width]
const SPIRIT_MATS = {
  fur: [0, 0, 0, 0.07], fluff: [0, 0, 0, 0.1], skin: [0, 0.22, 0.04, 0.045], water: [0, 1.1, 0.011, 0.04],
  leaf: [0, 0.3, 0.08, 0.045], horn: [0, 0.45, 0.03, 0.04], hoof: [0, 0.5, 0.025, 0.035], nose: [0, 1.0, 0.02, 0.035],
  glow: [0.9, 0, 0, 0.08], ember: [1.4, 0, 0, 0.08],
};
// per species shading presets (by look.kind); look.shade overrides any field
//   shade: shadow luminance relative to the lit plateau · sat/tint: hue-shifted shadow albedo · mid/midW/midTint: the
//   narrow band on the shadow side of the terminator · rim/rimT: sky+sun rim strength / fresnel threshold ·
//   term: terminator offset (more lit area) · aoK/aoS: low-frequency crease occlusion (terminator push / shade dim) ·
//   form: gentle falloff on the lit plateau toward the terminator · ambHue: how much the shadow takes the sky colour
const SPIRIT_SHADE = {
  fur: { shade: 0.6, sat: 1.25, tint: [0.94, 0.7, 0.96], mid: 0.55, midW: 0.17, midTint: [1.12, 0.84, 0.8], rim: 0.34, rimT: 0.72, term: 0.14, aoK: 0.5, aoS: 0.3, form: 0.12, ambHue: 0.35, key: 1, amb: 1 },
  water: { shade: 0.6, sat: 1.15, tint: [0.62, 0.8, 1.14], mid: 0.6, midW: 0.2, midTint: [0.92, 1.1, 1.14], rim: 0.42, rimT: 0.7, term: 0.1, aoK: 0.4, aoS: 0.25, form: 0.15, ambHue: 0.4, key: 1, amb: 1 },
  skin: { shade: 0.6, sat: 1.2, tint: [0.92, 0.74, 1.0], mid: 0.5, midW: 0.15, midTint: [1.1, 0.88, 0.86], rim: 0.3, rimT: 0.72, term: 0.12, aoK: 0.45, aoS: 0.3, form: 0.13, ambHue: 0.35, key: 1, amb: 1 },
};

// ---- exact sculpt field (same smooth union / subtraction order as sculptMesh), culled per 8 cm bucket
function spiritField(prims, bounds) {
  const B = 0.08, pad = 0.25, x0 = bounds[0] - pad, y0 = bounds[1] - pad, z0 = bounds[2] - pad;
  const nx = Math.ceil((bounds[3] - x0 + pad) / B) + 1, ny = Math.ceil((bounds[4] - y0 + pad) / B) + 1, nz = Math.ceil((bounds[5] - z0 + pad) / B) + 1;
  const cells = new Array(nx * ny * nz);
  const ci = (v, o, n) => Math.min(n - 1, Math.max(0, Math.floor((v - o) / B)));
  prims.forEach((P, pi) => {
    const bb = SDF.aabb(P);
    for (let k = ci(bb[2], z0, nz), k1 = ci(bb[5], z0, nz); k <= k1; k++) for (let j = ci(bb[1], y0, ny), j1 = ci(bb[4], y0, ny); j <= j1; j++) for (let i = ci(bb[0], x0, nx), i1 = ci(bb[3], x0, nx); i <= i1; i++) {
      const c = (k * ny + j) * nx + i; (cells[c] || (cells[c] = [])).push(pi);
    }
  });
  return (x, y, z) => {
    const L = cells[(ci(z, z0, nz) * ny + ci(y, y0, ny)) * nx + ci(x, x0, nx)];
    if (!L) return 0.5;
    let g = 1e3;
    for (let q = 0; q < L.length; q++) {
      const P = prims[L[q]], d = SDF.dist(P, x, y, z), k = P.k;
      if (P.sub) { const h = Math.max(k - Math.abs(-d - g), 0) / k; g = Math.max(g, -d) + h * h * k * 0.25; }
      else if (d < g + k) { const h = Math.max(k - Math.abs(g - d), 0) / k; g = Math.min(g, d) - h * h * k * 0.25; }
    }
    return g;
  };
}

// ---- clean geometry: smoothing + exact projection + relaxation, exact normals, region distances, soft crease AO
const _spiritGeo = {};
function spiritGeometry(key, D, look) {
  const hi = Settings.high && !isTouch, cell = hi ? (D.cellHi ?? 0.02) : (D.cellLo ?? 0.03);
  const ck = key + '@' + cell;
  if (_spiritGeo[ck]) return _spiritGeo[ck];
  const m = sculptMesh(D.prims, D.bounds, cell);
  const nv = m.nv, idx = m.idx, pos = m.pos, F = spiritField(D.prims, D.bounds);
  // 1-ring adjacency (each interior edge listed twice: uniform weights stay uniform)
  const st = new Uint32Array(nv + 1);
  for (let t = 0; t < idx.length; t++) st[idx[t] + 1] += 2;
  for (let i = 0; i < nv; i++) st[i + 1] += st[i];
  const nb = new Uint32Array(st[nv]), fill = st.slice(0, nv);
  for (let t = 0; t < idx.length; t += 3) {
    const a = idx[t], b = idx[t + 1], c = idx[t + 2];
    nb[fill[a]++] = b; nb[fill[a]++] = c; nb[fill[b]++] = a; nb[fill[b]++] = c; nb[fill[c]++] = a; nb[fill[c]++] = b;
  }
  const tmp = new Float32Array(nv * 3), nor = new Float32Array(nv * 3);
  const lap = (fac, tang) => {
    for (let i = 0; i < nv; i++) {
      const s = st[i], e = st[i + 1], i3 = i * 3;
      if (e === s) { tmp[i3] = pos[i3]; tmp[i3 + 1] = pos[i3 + 1]; tmp[i3 + 2] = pos[i3 + 2]; continue; }
      let ax = 0, ay = 0, az = 0;
      for (let q = s; q < e; q++) { const j = nb[q] * 3; ax += pos[j]; ay += pos[j + 1]; az += pos[j + 2]; }
      const inv = 1 / (e - s);
      let dx = ax * inv - pos[i3], dy = ay * inv - pos[i3 + 1], dz = az * inv - pos[i3 + 2];
      if (tang) { const dn = dx * nor[i3] + dy * nor[i3 + 1] + dz * nor[i3 + 2]; dx -= dn * nor[i3]; dy -= dn * nor[i3 + 1]; dz -= dn * nor[i3 + 2]; }
      tmp[i3] = pos[i3] + dx * fac; tmp[i3 + 1] = pos[i3 + 1] + dy * fac; tmp[i3 + 2] = pos[i3 + 2] + dz * fac;
    }
    pos.set(tmp);
  };
  const h = 0.0012, maxStep = cell * 0.7;
  const project = (iters) => {
    for (let i = 0; i < nv; i++) {
      const i3 = i * 3; let x = pos[i3], y = pos[i3 + 1], z = pos[i3 + 2];
      for (let k = 0; k < iters; k++) {
        const f = F(x, y, z);
        if (Math.abs(f) < 2e-5) break;
        const gx = (F(x + h, y, z) - f) / h, gy = (F(x, y + h, z) - f) / h, gz = (F(x, y, z + h) - f) / h;
        const g2 = gx * gx + gy * gy + gz * gz; if (g2 < 1e-6) break;
        let sx = gx * f / g2, sy = gy * f / g2, sz = gz * f / g2;
        const sl = Math.hypot(sx, sy, sz); if (sl > maxStep) { const r = maxStep / sl; sx *= r; sy *= r; sz *= r; }
        x -= sx; y -= sy; z -= sz;
      }
      pos[i3] = x; pos[i3 + 1] = y; pos[i3 + 2] = z;
    }
  };
  const normals = (central) => {
    for (let i = 0; i < nv; i++) {
      const i3 = i * 3, x = pos[i3], y = pos[i3 + 1], z = pos[i3 + 2];
      let gx, gy, gz;
      if (central) { gx = F(x + h, y, z) - F(x - h, y, z); gy = F(x, y + h, z) - F(x, y - h, z); gz = F(x, y, z + h) - F(x, y, z - h); }
      else { const f = F(x, y, z); gx = F(x + h, y, z) - f; gy = F(x, y + h, z) - f; gz = F(x, y, z + h) - f; }
      const l = Math.hypot(gx, gy, gz);
      if (l > 1e-9) { nor[i3] = gx / l; nor[i3 + 1] = gy / l; nor[i3 + 2] = gz / l; } else { nor[i3] = m.nor[i3]; nor[i3 + 1] = m.nor[i3 + 1]; nor[i3 + 2] = m.nor[i3 + 2]; }
    }
  };
  const its = D.smooth ?? 4;
  for (let k = 0; k < its; k++) { lap(0.5); lap(-0.53); }
  project(2); normals(false);
  lap(0.55, true); project(1); normals(true);
  // macro normals: the normal field diffused over the surface (~10 cm), unnormalised so its length says how much
  // the neighbourhood agrees (thin ears / fins → short → ignored). Terminators and highlights then follow the big
  // forms (head ball, body) instead of every small sculpt detail (eye sockets, muzzle bumps, lid folds) — the
  // "transferred sphere normals" trick of anime faces, here weighted toward the head.
  // The same diffusion of the positions gives a soft crease measure (how far the smoothed surface floats above the
  // real one): low-frequency occlusion where the head meets the body, legs meet the belly … never fine-scale noise.
  const mn = new Float32Array(nor), m2 = new Float32Array(nv * 3), mp = new Float32Array(pos), p2 = new Float32Array(nv * 3);
  const its2 = Math.round((D.macro ?? 0.1) ** 2 / (cell * cell) * 0.9);
  for (let k = 0; k < its2; k++) {
    for (let i = 0; i < nv; i++) {
      const s0 = st[i], e = st[i + 1], i3 = i * 3;
      let ax = mn[i3] * 2, ay = mn[i3 + 1] * 2, az = mn[i3 + 2] * 2, px = mp[i3] * 2, py = mp[i3 + 1] * 2, pz = mp[i3 + 2] * 2;
      for (let q = s0; q < e; q++) { const j = nb[q] * 3; ax += mn[j]; ay += mn[j + 1]; az += mn[j + 2]; px += mp[j]; py += mp[j + 1]; pz += mp[j + 2]; }
      const inv = 1 / (e - s0 + 2); m2[i3] = ax * inv; m2[i3 + 1] = ay * inv; m2[i3 + 2] = az * inv; p2[i3] = px * inv; p2[i3 + 1] = py * inv; p2[i3 + 2] = pz * inv;
    }
    mn.set(m2); mp.set(p2);
  }
  const aNm = new Float32Array(nv * 4);
  for (let i = 0; i < nv; i++) {
    const i3 = i * 3, l = Math.hypot(mn[i3], mn[i3 + 1], mn[i3 + 2]);
    const conf = l > 1e-6 ? sstep(0.55, 0.85, l) : 0, head = sstep(0.85, 0.98, m.aS[i]);
    aNm[i * 4] = l > 1e-6 ? mn[i3] / l : nor[i3]; aNm[i * 4 + 1] = l > 1e-6 ? mn[i3 + 1] / l : nor[i3 + 1]; aNm[i * 4 + 2] = l > 1e-6 ? mn[i3 + 2] / l : nor[i3 + 2];
    aNm[i * 4 + 3] = conf * (look.macroBody ?? 0.45) * (1 - head) + conf * (look.macroHead ?? 0.8) * head;
  }
  // regions
  const R = spiritRegions(D, look, pos, nor, nv, m);
  const bake = new Float32Array(nv * 3), aoS = D.aoScale ?? 0.035;
  for (let i = 0; i < nv; i++) {
    const i3 = i * 3, c = (mp[i3] - pos[i3]) * nor[i3] + (mp[i3 + 1] - pos[i3 + 1]) * nor[i3 + 1] + (mp[i3 + 2] - pos[i3 + 2]) * nor[i3 + 2];
    bake[i3] = sstep(0.15, 1, c / aoS);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  g.setAttribute('normal', new THREE.BufferAttribute(nor, 3));
  g.setAttribute('color', new THREE.BufferAttribute(R.col, 3));
  g.setAttribute('aR0', new THREE.BufferAttribute(R.a[0], 4));
  g.setAttribute('aR1', new THREE.BufferAttribute(R.a[1], 4));
  g.setAttribute('aR2', new THREE.BufferAttribute(R.a[2], 4));
  g.setAttribute('aBake', new THREE.BufferAttribute(bake, 3));
  g.setAttribute('aNm', new THREE.BufferAttribute(aNm, 4));
  g.setAttribute('aS', new THREE.BufferAttribute(m.aS, 1));
  g.setAttribute('aJaw', new THREE.BufferAttribute(m.aJaw, 1));
  g.setAttribute('aGlow', new THREE.BufferAttribute(m.aGlow, 1));
  g.setAttribute('aBelly', new THREE.BufferAttribute(m.aBelly, 1));
  g.setAttribute('aLeg', new THREE.BufferAttribute(m.aLeg, 1));
  g.setIndex(new THREE.BufferAttribute(idx, 1));
  g.computeBoundingSphere(); g.boundingSphere.radius *= 1.3;
  g.userData.palette = R.palette;
  _spiritGeo[ck] = g; return g;
}

// palette slots: classes (one per distinct prim colour, stored as distance above the nearest class) followed by
// overlays (signed distance). Returns the attributes, a hard per-vertex colour (outline ink) and the slot table.
function spiritRegions(D, look, pos, nor, nv, m) {
  const add = D.prims.filter((P) => !P.sub);
  const hexOf = (P) => (P.hex != null ? P.hex : linToHex(P.col || [1, 1, 1]));
  const hexes = [];
  for (const P of add) { const hx = hexOf(P); if (!hexes.includes(hx)) hexes.push(hx); }
  const over = (look.over || []).slice(0, Math.max(0, SPIRIT_SLOTS - Math.min(hexes.length, SPIRIT_SLOTS)));
  const nc = Math.min(hexes.length, SPIRIT_SLOTS - over.length);
  // classes beyond the budget fold into the nearest kept colour
  const lin = hexes.map((hx) => hexRGB(hx));
  const clsOfHex = hexes.map((hx, i) => {
    if (i < nc) return i;
    let b = 0, bd = 1e9;
    for (let j = 0; j < nc; j++) { const d = (lin[i][0] - lin[j][0]) ** 2 + (lin[i][1] - lin[j][1]) ** 2 + (lin[i][2] - lin[j][2]) ** 2; if (d < bd) { bd = d; b = j; } }
    return b;
  });
  const cls = add.map((P) => clsOfHex[hexes.indexOf(hexOf(P))]);
  const boxes = add.map((P) => SDF.aabb(P));
  const a = [new Float32Array(nv * 4), new Float32Array(nv * 4), new Float32Array(nv * 4)];
  const col = new Float32Array(nv * 3), dc = new Float64Array(nc), CL = 0.1;
  const ovLin = over.map((o) => hexRGB(o.col));
  const v = { x: 0, y: 0, z: 0, nx: 0, ny: 0, nz: 0, jaw: 0, leg: 0, s: 0 };
  for (let i = 0; i < nv; i++) {
    const x = pos[i * 3], y = pos[i * 3 + 1], z = pos[i * 3 + 2];
    dc.fill(1e9);
    for (let p = 0; p < add.length; p++) {
      const b = boxes[p];
      if (x < b[0] - 0.2 || y < b[1] - 0.2 || z < b[2] - 0.2 || x > b[3] + 0.2 || y > b[4] + 0.2 || z > b[5] + 0.2) continue;
      const d = SDF.dist(add[p], x, y, z), c = cls[p];
      if (d < dc[c]) dc[c] = d;
    }
    let dm = 1e9, w = 0;
    for (let c = 0; c < nc; c++) if (dc[c] < dm) { dm = dc[c]; w = c; }
    for (let s = 0; s < SPIRIT_SLOTS; s++) a[s >> 2][i * 4 + (s & 3)] = CL;
    for (let c = 0; c < nc; c++) a[c >> 2][i * 4 + (c & 3)] = Math.min(dc[c] - dm, CL);
    let cr = lin[w][0], cg = lin[w][1], cb = lin[w][2];
    v.x = x; v.y = y; v.z = z; v.nx = nor[i * 3]; v.ny = nor[i * 3 + 1]; v.nz = nor[i * 3 + 2]; v.jaw = m.aJaw[i]; v.leg = m.aLeg[i]; v.s = m.aS[i];
    for (let o = 0; o < over.length; o++) {
      const s = nc + o, sd = Math.max(-CL, Math.min(CL, over[o].sd(v)));
      a[s >> 2][i * 4 + (s & 3)] = sd;
      if (sd < 0) { cr = ovLin[o][0]; cg = ovLin[o][1]; cb = ovLin[o][2]; }
    }
    col[i * 3] = cr; col[i * 3 + 1] = cg; col[i * 3 + 2] = cb;
  }
  const kind = look.kind || 'fur', mats = look.mats || {};
  const mp = (k) => SPIRIT_MATS[k] || SPIRIT_MATS[kind] || SPIRIT_MATS.fur;
  const palette = [];
  for (let c = 0; c < nc; c++) palette.push({ col: hexes[c], p: mp(mats[hexes[c]]).slice() });
  for (const o of over) {
    const p = o.mat ? mp(o.mat).slice() : [0, -1, 0, 0];
    if (o.em != null) p[0] = o.em;
    palette.push({ col: o.col, p, soft: o.soft || 0 });
  }
  return { a, col, palette, nc, ns: nc + over.length };
}

// ---- the cel material
const SPIRIT_DECL = `uniform vec3 uPal[${SPIRIT_SLOTS}]; uniform vec4 uPalP[${SPIRIT_SLOTS}]; uniform float uPalS[${SPIRIT_SLOTS}]; uniform int uNC, uNS;
  uniform float uShade, uShadeSat, uMid, uMidW, uRim, uRimT, uTerm, uAOk, uAOs, uForm, uAmbHue, uKeyK, uAmbK, uFlash;
  uniform float uKeySat, uShadeHueK;
  uniform vec3 uShadeTint, uMidTint, uShadeHue;
  varying vec4 vR0, vR1, vR2, vNm; varying vec3 vObjPos; varying vec3 vObjN; varying vec3 vBake;
  vec4 gPP;
`;
const SPIRIT_RESOLVE = `
  {
    float Dv[${SPIRIT_SLOTS}];
    vec4 f0 = fwidth(vR0), f1 = fwidth(vR1), f2 = fwidth(vR2);
    float Fw[${SPIRIT_SLOTS}];
    Dv[0] = vR0.x; Dv[1] = vR0.y; Dv[2] = vR0.z; Dv[3] = vR0.w; Dv[4] = vR1.x; Dv[5] = vR1.y; Dv[6] = vR1.z; Dv[7] = vR1.w; Dv[8] = vR2.x; Dv[9] = vR2.y; Dv[10] = vR2.z; Dv[11] = vR2.w;
    Fw[0] = f0.x; Fw[1] = f0.y; Fw[2] = f0.z; Fw[3] = f0.w; Fw[4] = f1.x; Fw[5] = f1.y; Fw[6] = f1.z; Fw[7] = f1.w; Fw[8] = f2.x; Fw[9] = f2.y; Fw[10] = f2.z; Fw[11] = f2.w;
    float dm = 1.0;
    for (int i = 0; i < ${SPIRIT_SLOTS}; i++) { if (i < uNC) dm = min(dm, Dv[i]); }
    vec3 c = vec3(0.0); vec4 pp = vec4(0.0); float ws = 0.0;
    for (int i = 0; i < ${SPIRIT_SLOTS}; i++) {
      if (i < uNC) {
        float w = clamp(1.0 - (Dv[i] - dm) / max(Fw[i] * 0.85, 1e-5), 0.0, 1.0);
        c += uPal[i] * w; pp += uPalP[i] * w; ws += w;
      }
    }
    c /= max(ws, 1e-4); pp /= max(ws, 1e-4);
    for (int i = 0; i < ${SPIRIT_SLOTS}; i++) {
      if (i >= uNC && i < uNS) {
        float mk = clamp(0.5 - Dv[i] / max(Fw[i] * 0.85, uPalS[i]), 0.0, 1.0);
        c = mix(c, uPal[i], mk);
        if (uPalP[i].y < 0.0) pp.x = mix(pp.x, uPalP[i].x, mk); else pp = mix(pp, uPalP[i], mk);
      }
    }
    diffuseColor.rgb = c; gPP = pp;
  }
`;
const SPIRIT_LIGHT = `
  {
    vec3 N0 = normalize(normal), Vv = normalize(vViewPosition);
    // shading normal: blend toward the macro normal (big forms) — clean face terminators, one highlight per form
    vec3 N = normalize(mix(N0, normalize(vNm.xyz), clamp(vNm.w, 0.0, 1.0)));
    vec3 upV = normalize((viewMatrix * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
    vec3 alb = diffuseColor.rgb;
    // fill: ambient + probe + hemisphere taken at a normal bent toward the sky, so the shadow side stays a flat,
    // sky-tinted tone instead of a smeared gradient
    vec3 Na = normalize(N + upV * 1.3);
    vec3 amb = ambientLightColor;
    #if defined(USE_LIGHT_PROBES)
      amb += getLightProbeIrradiance(lightProbe, Na);
    #endif
    #if NUM_HEMI_LIGHTS > 0
      amb += getHemisphereLightIrradiance(hemisphereLights[0], Na);
    #endif
    amb *= RECIPROCAL_PI;
    vec3 keyC = vec3(0.0), keyD = normalize(upV + Vv); float shw = 1.0;
    #if NUM_DIR_LIGHTS > 0
      keyC = directionalLights[0].color * RECIPROCAL_PI; keyD = directionalLights[0].direction;
      keyC = mix(vec3(dot(keyC, vec3(0.2126, 0.7152, 0.0722))), keyC, uKeySat);
      #if defined(USE_SHADOWMAP) && NUM_DIR_LIGHT_SHADOWS > 0
        shw = receiveShadow ? getShadow(directionalShadowMap[0], directionalLightShadows[0].shadowMapSize, directionalLightShadows[0].shadowBias, directionalLightShadows[0].shadowRadius, vDirectionalShadowCoord[0]) : 1.0;
      #endif
    #endif
    float ndl = dot(N, keyD);
    float tt = ndl + uTerm - vBake.x * uAOk;
    float aw = max(fwidth(tt) * 0.9, gPP.w);
    float litF = smoothstep(-aw, aw, tt);
    float shS = smoothstep(0.3, 0.7, shw);
    float lit = litF * shS;
    vec3 litE = keyC * uKeyK + amb * uAmbK;
    float LL = dot(litE, vec3(0.2126, 0.7152, 0.0722));
    vec3 litT = alb * litE * (1.0 - uForm * (1.0 - smoothstep(0.0, 0.85, ndl)));
    vec3 ambH = amb / max(dot(amb, vec3(0.2126, 0.7152, 0.0722)), 1e-4);
    float aLum = dot(alb, vec3(0.2126, 0.7152, 0.0722));
    vec3 sA = max(mix(vec3(aLum), alb, uShadeSat), 0.0) * uShadeTint;
    sA = mix(sA, uShadeHue * (aLum / max(dot(uShadeHue, vec3(0.2126, 0.7152, 0.0722)), 1e-3)), uShadeHueK);
    float upk = smoothstep(-0.6, 0.75, dot(N, upV));
    vec3 shT = sA * mix(vec3(1.0), ambH, uAmbHue) * (LL * uShade * mix(0.86, 1.05, upk) * (1.0 - vBake.x * uAOs));
    float band = smoothstep(-uMidW - aw, -uMidW + aw, tt) * (1.0 - litF) * shS;
    vec3 col = mix(shT, litT, lit);
    col = mix(col, mix(shT, litT, 0.5) * uMidTint, band * uMid);
    // rim: a thin, clean band on the silhouette facing the sun / sky
    float fr = 1.0 - clamp(dot(N, Vv), 0.0, 1.0);
    float rw = fwidth(fr) * 0.75 + 0.012;
    float rimB = smoothstep(uRimT - rw, uRimT + rw, fr) * smoothstep(-0.3, 0.3, dot(N, normalize(keyD + upV * 0.8))) * (1.0 - 0.8 * lit);
    vec3 rimC = keyC * 0.5 + amb * 0.8;
    #if NUM_DIR_LIGHTS > 1
      rimC += directionalLights[1].color * RECIPROCAL_PI * 0.5;
    #endif
    col += rimC * (0.3 + 0.7 * alb) * rimB * uRim * mix(0.45, 1.0, shS);
    // one shaped specular, glossy regions only
    // the highlight rides on the big form only (macro normal), so it is one clean shape, never shards on small details
    vec3 Nsp = normalize(mix(N0, normalize(vNm.xyz), clamp(vNm.w * 1.6, 0.0, 1.0)));
    float nh = dot(Nsp, normalize(keyD + Vv)), nhw = fwidth(nh) + 0.002, th = 1.0 - gPP.z;
    float sp = smoothstep(th - nhw, th + nhw, nh) * lit * max(gPP.y, 0.0);
    col += (keyC * 0.95 + 0.05) * sp;
    reflectedLight.directDiffuse = col;
    totalEmissiveRadiance += alb * gPP.x + gDecalE;
  }
`;
function spiritMaterial(D, look, cfg = {}, solid = null) {
  const m = new THREE.MeshLambertMaterial({ color: 0xffffff });
  const S = Object.assign({}, SPIRIT_SHADE[look.kind] || SPIRIT_SHADE.fur, look.shade || {});
  const pal = solid ? [{ col: solid.col, p: (SPIRIT_MATS[solid.mat] || SPIRIT_MATS[look.kind] || SPIRIT_MATS.fur).slice(), soft: 0 }] : D.palette;
  const P3 = [], P4 = [], PS = [];
  for (let i = 0; i < SPIRIT_SLOTS; i++) {
    const e = pal[i];
    P3.push(new THREE.Color(e ? e.col : 0xff00ff)); P4.push(new THREE.Vector4(...(e ? e.p : [0, 0, 0, 0.05]))); PS.push(e ? e.soft || 0 : 0);
  }
  if (solid && solid.em != null) P4[0].x = solid.em;
  const U = {
    uTime: Shared.time, uWaveAmp: { value: solid ? 0 : cfg.waveAmp ?? 0.1 }, uWaveSpeed: { value: cfg.waveSpeed ?? 3.4 }, uWaveFreq: { value: cfg.waveFreq ?? 3.2 },
    uTailStart: { value: D.tailStart ?? 0.32 }, uSerp: { value: 0 }, uNeckStart: { value: D.neckStart ?? 0.9 }, uSway: { value: solid ? 0 : 1 },
    uJaw: { value: 0 }, uJawHinge: { value: new THREE.Vector3(...(D.jawHinge || [0, 0, 0])) },
    uWalk: { value: 0 }, uStride: { value: 0 }, uHipY: { value: D.hipY ?? 0.5 }, uShoulderY: { value: D.shoulderY ?? 9 },
    uPal: { value: P3 }, uPalP: { value: P4 }, uPalS: { value: PS }, uNC: { value: solid ? 1 : D.nc }, uNS: { value: solid ? 1 : D.ns },
    uShade: { value: S.shade }, uShadeSat: { value: S.sat }, uShadeTint: { value: new THREE.Vector3(...S.tint) }, uMid: { value: S.mid }, uMidW: { value: S.midW },
    uMidTint: { value: new THREE.Vector3(...S.midTint) }, uRim: { value: S.rim }, uRimT: { value: S.rimT }, uTerm: { value: S.term }, uAOk: { value: S.aoK }, uAOs: { value: S.aoS },
    uForm: { value: S.form }, uAmbHue: { value: S.ambHue }, uKeyK: { value: S.key }, uAmbK: { value: S.amb }, uKeySat: { value: S.keySat ?? 0.6 }, uShadeHue: { value: new THREE.Color(S.hue ?? 0x6a4a8a) }, uShadeHueK: { value: S.hueK ?? 0.22 }, uFlash: { value: 0 },
  };
  // face decals (mouth, blush, brows, crest mark) — crisp object-space shapes, see CRITTER_FACE
  const F = solid ? {} : (D.face || {}), v4 = (a) => new THREE.Vector4(...(a || [0, 0, 0, 0]));
  Object.assign(U, {
    uMouth: { value: v4(F.mouth) }, uMouthK: { value: F.mouth ? (F.mouthK ?? 1) : 0 }, uLineCol: { value: new THREE.Color(F.line ?? 0x2a1216) },
    uNose: { value: v4(F.nose) }, uBlush: { value: v4(F.blush) }, uBlushCol: { value: new THREE.Color(F.blushCol ?? 0xff7f96) }, uHatch: { value: F.hatch ?? 0 }, uBlushEdge: { value: F.blushEdge ?? 0.72 }, uBlushA: { value: F.blushA ?? 0.5 },
    uBrow: { value: v4(F.brow) }, uBrowTilt: { value: F.browTilt ?? 0 }, uBrowCol: { value: new THREE.Color(F.browCol ?? 0x3a1a14) },
    uMark: { value: v4(F.mark) }, uMarkK: { value: F.mark ? (F.markK ?? 1) : 0 }, uMarkCol: { value: new THREE.Color(F.markCol ?? 0xffd27a) }, uMarkGlow: { value: new THREE.Color(F.markGlow ?? 0x000000) },
  });
  m.userData.U = U; m.userData.uFlash = U.uFlash; m.userData.kind = 'spirit';
  m.defaultAttributeValues = { aBake: [0, 0, 0], aR0: [0, 0.1, 0.1, 0.1], aR1: [0.1, 0.1, 0.1, 0.1], aR2: [0.1, 0.1, 0.1, 0.1], aNm: [0, 1, 0, 0] };
  m.onBeforeCompile = (sh) => {
    Object.assign(sh.uniforms, U);
    sh.vertexShader = SCULPT_DECL + 'attribute vec4 aR0, aR1, aR2, aNm; varying vec4 vR0, vR1, vR2, vNm;\n' + sh.vertexShader
      .replace('#include <beginnormal_vertex>', '#include <beginnormal_vertex>\n vObjN = objectNormal; vR0 = aR0; vR1 = aR1; vR2 = aR2; vNm = vec4(normalMatrix * aNm.xyz, aNm.w);')
      .replace('#include <begin_vertex>', SCULPT_BODY);
    sh.fragmentShader = SPIRIT_DECL + CRITTER_FACE_DECL + sh.fragmentShader
      .replace('#include <color_fragment>', SPIRIT_RESOLVE + CRITTER_FACE)
      .replace('#include <lights_fragment_begin>', SPIRIT_LIGHT)
      .replace('#include <lights_fragment_maps>', '')
      .replace('#include <lights_fragment_end>', '')
      .replace('#include <dithering_fragment>', '#include <dithering_fragment>\n gl_FragColor.rgb = mix(gl_FragColor.rgb, vec3(2.2), uFlash);');
  };
  m.customProgramCacheKey = () => 'spiritCel-v2';
  return m;
}
// single-colour parts (sprouts, blossoms, gems) in the same cel look; outline with the same screen-space ink line
function spiritPart(r, geo, hex, mat, parent, pos, scl, rot, o = {}) {
  const look = r.spiritLook || { kind: 'fur' };
  const sm = spiritMaterial({}, look, {}, { col: hex, mat, em: o.em });
  const p = part(geo, sm, parent, pos, scl, rot);
  p.castShadow = o.shadow !== false;
  if (o.outline !== false) sculptOutline(p, o.olw ?? 0.01, o.olc ?? 0x24161c, { minPx: 0.7, maxPx: 1.4, ink: 0.7 });
  if (r.flashMats) r.flashMats.push(sm);
  return p;
}

// ---- eyes: flat-layered iris (dark limbal ring · main colour · light lower crescent · round or slit pupil), flat
// sclera with a crisp lid-shadow band, one big + one small catch-light from ONE screen-space key (same on both eyes),
// clean lash line + wing; blink / happy squint / hurt squeeze; converging gaze with saccades (eyeGaze in 02d)
function spiritEye(o = {}) {
  const U = {
    uIris: { value: new THREE.Color(o.iris ?? 0x8a4a12) }, uIris2: { value: new THREE.Color(o.iris2 ?? 0xffc04a) }, uIrisRim: { value: new THREE.Color(o.irisRim ?? 0x2a1006) },
    uPupilC: { value: new THREE.Color(o.pupilCol ?? 0x120a0c) }, uSclera: { value: new THREE.Color(o.sclera ?? 0xfafaff) }, uLidTint: { value: new THREE.Color(o.lidTint ?? 0xc9c4e6) },
    uLash: { value: new THREE.Color(o.lash ?? 0x1c1018) }, uBlink: { value: 0 }, uSide: { value: o.side ?? 1 },
    uShape: { value: new THREE.Vector4(o.open ?? 0.8, o.tilt ?? 0.05, o.wing ?? 0.5, o.irisR ?? 0.62) },
    uSlit: { value: o.slit ?? 0 }, uFlash: { value: 0 }, uGlow: { value: o.glow ?? 0 },
    uGaze: { value: new THREE.Vector2() }, uExpr: { value: new THREE.Vector2() }, uSkin: { value: new THREE.Color(o.skin ?? 0xd8c8c0) },
    uPupil: { value: o.pupil ?? 1 }, uDepth: { value: o.cornea ?? 0.36 },
  };
  const m = new THREE.ShaderMaterial({
    uniforms: THREE.UniformsUtils.merge([THREE.UniformsLib.fog]),
    vertexShader: `${EYE_V} ${FOG_V}
      void main(){ eyeVaryings(position); vec4 mvPosition = modelViewMatrix * vec4(position, 1.0); gl_Position = projectionMatrix * mvPosition;
        #include <fog_vertex>
      }`,
    fragmentShader: `uniform vec3 uIris, uIris2, uIrisRim, uPupilC, uSclera, uLidTint, uLash, uSkin; uniform float uBlink, uSide, uSlit, uFlash, uPupil, uDepth, uGlow; uniform vec4 uShape; uniform vec2 uGaze, uExpr; ${EYE_F} ${FOG_F}
      float cov(float sd, float pw) { return clamp(0.5 - sd / pw, 0.0, 1.0); }
      void main(){
        vec3 n = normalize(vN);
        if (n.z < 0.02) discard;
        vec2 q = vec2(n.x * uSide, n.y);
        float pw = max(max(fwidth(q.x), fwidth(q.y)), 1e-4);
        float H = uShape.x, tilt = uShape.y, IR = uShape.w;
        float xx = clamp(q.x / 0.9, -1.0, 1.0);
        float arc = sqrt(max(1.0 - pow(abs(xx), 2.6), 0.0));
        float topO = H * arc + tilt * xx + 0.03, botO = -H * 0.86 * arc + tilt * xx * 0.4;
        float hap = clamp(uExpr.x, 0.0, 1.0), hurt = clamp(uExpr.y, 0.0, 1.0), cl = clamp(max(uBlink, hurt), 0.0, 1.0);
        float shutB = -0.1 - 0.16 * arc, shutS = -0.05 - 0.08 * arc + 0.12 * xx, shutH = -0.2 + 0.36 * arc;
        float shut = mix(shutB, shutS, clamp(hurt / max(cl, 1e-3), 0.0, 1.0));
        float top = mix(topO, shut, cl), bot = mix(botO, shut - 0.002, cl);
        bot = mix(bot, max(shutH, bot), hap); top = mix(top, max(top * 0.7 + shutH * 0.3, bot + 0.02), hap);
        float lensSD = max(max(q.y - topO, botO - q.y), abs(q.x) - 0.9);
        float openA = cov(lensSD, pw);
        float inside = cov(max(max(q.y - top, bot - q.y), abs(q.x) - 0.9), pw);
        // sclera: flat, with a crisp cool lid-shadow band under the upper lid
        float lidB = cov((top - 0.2 - 0.05 * arc) - q.y, pw);
        vec3 col = mix(uSclera, uSclera * uLidTint, lidB);
        // iris on a plane behind the cornea, rotated by the gaze; never mirrored between the eyes
        vec2 ip = eyeIris(n, uDepth) - uGaze;
        vec2 d = (ip - vec2(0.0, -0.04)) / vec2(1.0, 1.08);
        float r = length(d);
        vec3 ir = uIris;
        ir = mix(ir, uIris2, cov(length((d - vec2(0.0, -0.46 * IR)) / vec2(1.0, 0.8)) - 0.64 * IR, pw));
        ir = mix(ir, uIrisRim, cov(0.84 * IR - r, pw));
        float pr = uSlit > 0.5 ? length(vec2(d.x / (0.2 * IR * uPupil), d.y / (0.78 * IR))) - 1.0 : (r - 0.42 * IR * uPupil) / (0.42 * IR * uPupil);
        ir = mix(ir, uPupilC, cov(pr * 0.42 * IR * uPupil, pw));
        ir = mix(ir, ir * vec3(0.62, 0.6, 0.72), lidB);
        ir *= 1.0 + uGlow;
        col = mix(col, ir, cov(r - IR, pw));
        // catch-lights: one big (key, upper left of the screen) + one small (opposite) — shared by both eyes
        vec3 ct = eyeCatch(n.xy, vec2(0.0, -0.04) + uGaze, IR, pw);
        col = mix(col, vec3(1.35), ct.x * (1.0 - cl) * (1.0 - hap * 0.5));
        col = mix(col, vec3(1.15), ct.y * 0.95 * (1.0 - cl));
        // lids: skin over the eyeball wherever the lids have closed over the open lens
        vec3 skin = uSkin * 0.92;
        col = mix(skin, col, inside);
        // lash: clean upper line thickening toward the outer corner + wing; thin lower line on the outer half
        float lw = max(mix(0.05, 0.1, smoothstep(-0.8, 0.9, q.x)) * (1.0 - 0.25 * cl), pw * 0.6);
        float upper = cov(abs(q.y - top - lw * 0.3) - lw, pw) * smoothstep(0.99, 0.93, abs(q.x));
        vec2 w = q - vec2(0.9, top + 0.05); w = vec2(w.x * 0.8 + w.y * 0.6, -w.x * 0.6 + w.y * 0.8);
        float wing = cov((length(w / vec2(0.15, 0.045)) - 0.85) * 0.045, pw) * uShape.z;
        float lower = cov(abs(q.y - bot) - max(0.026, pw * 0.45), pw) * smoothstep(-0.1, 0.4, q.x) * smoothstep(0.92, 0.8, q.x) * 0.85 * (1.0 - cl);
        lower = max(lower, cov(abs(q.y - bot) - max(0.035, pw * 0.5), pw) * hap * smoothstep(0.92, 0.6, abs(q.x)));
        float lash = max(max(upper, wing), lower);
        col = mix(col, uLash, lash);
        float a = max(openA, lash);
        if (a < 0.02) discard;
        col = mix(col, vec3(2.2), uFlash);
        gl_FragColor = vec4(col, a);
        #include <tonemapping_fragment>
        #include <colorspace_fragment>
        #include <fog_fragment>
      }`,
    fog: true,
  });
  Object.assign(m.uniforms, U);
  m.alphaToCoverage = true;
  // the lens sits in a shallow socket: a small depth offset keeps it from z-fighting with the socket floor
  m.polygonOffset = true; m.polygonOffsetFactor = -1; m.polygonOffsetUnits = -2;
  m.userData.blink = U.uBlink; m.userData.uFlash = U.uFlash; m.userData.gaze = U.uGaze; m.userData.expr = U.uExpr; m.userData.skin = U.uSkin;
  if (o.gaze !== false) m.onBeforeRender = (rr, sc, cam, geo, obj) => eyeGaze(obj, cam, U.uGaze, U.uSide.value, o.gazeLim || {});
  return m;
}

// ---------------------------------------------------------------- eye sockets
// Exact replay of the sculpt's field (same smooth union / subtraction order as sculptMesh), to find where the face
// surface really is along each eye's axis.
function sculptField(prims, x, y, z) {
  let g = 1e3;
  for (const P of prims) {
    const d = SDF.dist(P, x, y, z), k = P.k;
    if (P.sub) { const h = Math.max(k - Math.abs(-d - g), 0) / k; g = Math.max(g, -d) + h * h * k * 0.25; }
    else if (d < g + k) { const h = Math.max(k - Math.abs(g - d), 0) / k; g = Math.min(g, d) - h * h * k * 0.25; }
  }
  return g;
}
// The eyeball should sit IN the head: carve a shallow almond dish behind each eye (the baked AO then darkens its rim)
// and add a soft upper-lid fold above it, coloured like the skin around the eye. Returns the extra primitives and
// the skin colour per eye (used for the lid that closes over the eyeball when blinking).
function eyeSockets(D, eo = {}) {
  const k = D.socket ?? 1, extra = [], skins = [];
  const add = D.prims.filter((P) => !P.sub);
  const E3 = new THREE.Euler(), vz = new THREE.Vector3(), vy = new THREE.Vector3();
  for (const e of D.eyes || []) {
    const r = e.r;
    E3.set(e.pitch || 0, e.yaw || 0, e.roll || 0); vz.set(0, 0, 1).applyEuler(E3); vy.set(0, 1, 0).applyEuler(E3);
    const P = e.p, at = (t) => [P[0] + vz.x * t, P[1] + vz.y * t, P[2] + vz.z * t];
    // nearest additive primitive at the eye → skin colour
    let best = null, bd = 1e9;
    for (const Q of add) { const d = SDF.dist(Q, P[0], P[1], P[2]); if (d < bd) { bd = d; best = Q; } }
    const col = (best && best.col) || [1, 1, 1];
    skins.push(col);
    if (!(k > 0)) continue;
    // surface along the eye axis
    let ts = null;
    for (let t = -1.6 * r; t <= 1.6 * r; t += 0.05 * r) { const p = at(t); if (sculptField(D.prims, p[0], p[1], p[2]) > 0) { ts = t; break; } }
    if (ts === null) continue;
    const dep = 0.48 * r * k, c = at(ts - dep), H = (eo.open ?? 0.8);
    extra.push(SDF.el(c, [1.12 * r, 0.62 * r + 0.3 * r * H, 0.82 * r], { k: 0.32 * r, sub: true }));
    const lid = at(ts - 0.14 * r);
    const up = (1.25 * H + 0.2) * r;
    const lf = D.lidFold ?? 1;
    if (lf > 0) extra.push(SDF.el([lid[0] + vy.x * up, lid[1] + vy.y * up, lid[2] + vy.z * up], [0.9 * r, 0.18 * r * lf, 0.25 * r * lf], { k: 0.2 * r, s0: 1, s1: 1, col, hex: best && best.hex, jaw: 0 }));
  }
  return { extra, skins };
}

const linToHex = (c) => { const f = (v) => { v = Math.max(0, Math.min(1, v)); const s = v <= 0.0031308 ? v * 12.92 : 1.055 * Math.pow(v, 1 / 2.4) - 0.055; return Math.round(s * 255); }; return (f(c[0]) << 16) | (f(c[1]) << 8) | f(c[2]); };

function buildCritter(r, cfg) {
  const D = cfg.design;
  r.olw = 0; r.hopAmp = cfg.hop ?? 0.6;
  if (cfg.float) { r.float = cfg.float; r.floatAmp = cfg.floatAmp ?? 0.1; }
  const B = grp(r.body); B.scale.setScalar(cfg.scale ?? 1);
  Object.defineProperty(B.userData, 'rig', { value: r, enumerable: false, writable: true, configurable: true }); // gaze target lookup (r.gazeAt); hidden from userData clones
  const eo = cfg.eye || {};
  if (!D._sock) D._sock = eyeSockets(D, eo);
  const DD = Object.assign({ jawHinge: [0, 0, 0], tailStart: 0.32, neckStart: 0.9 }, D, { prims: D.prims.concat(D._sock.extra) });
  if (D.earHinge) DD.jawHinge = D.earHinge;
  const L = D.look;
  let geo, mat;
  if (L) {
    // mainline look: clean geometry, flat colour regions, soft cel (see spiritGeometry / spiritMaterial)
    geo = spiritGeometry('s_' + cfg.key, DD, L);
    const pal = geo.userData.palette;
    mat = spiritMaterial(Object.assign({}, DD, { palette: pal, nc: pal.filter((p) => p.soft === undefined).length, ns: pal.length }), L, cfg);
    r.spiritLook = L;
  } else {
    geo = dragonGeometry('c_' + cfg.key, DD, 0.021, 0.03);
    if (D.paint) paintCritter(geo, D.paint);
    const kind = (cfg.mat && cfg.mat.kind) || 'vinyl', soft = kind === 'fur' || kind === 'wool' || kind === 'plush';
    mat = dragonMaterial(Object.assign({ kind, scaleFreq: 0, rough: soft ? 0.74 : 0.55, metal: 0, coat: soft ? 0 : 0.2, coatRough: 0.4, sheen: soft ? 0.22 : 0.3, sheenRough: soft ? 0.85 : 0.5, env: soft ? 0.24 : 0.32, sheenCol: 0xfff0e0, rim: 0xffffff, rimAmt: 0.06, waveAmp: 0.1, waveFreq: 3.2, waveSpeed: 3.4, soft: 0.03, fuzz: 0.04, hipY: D.hipY ?? 0.5, sat: 1.12, glowAmt: 1.6 }, cfg.mat), DD);
    critterSkin(mat, D.face);
  }
  const U = mat.userData.U; U.uSway.value = cfg.sway ?? 0.3;
  const body = new THREE.Mesh(geo, mat); body.castShadow = true; body.receiveShadow = true; B.add(body);
  if (cfg.outline !== false) {
    if (L) sculptOutline(body, cfg.olw ?? 0.012, cfg.olc ?? 0x2a1a22, { minPx: 0.75, maxPx: 1.75, ink: cfg.olInk ?? 0.72 });
    else sculptOutline(body, cfg.olw ?? 0.016, cfg.olc ?? 0x24161c);
  }
  const follow = [];
  const glue = (obj, s) => follow.push({ obj, base: obj.position.clone(), s });
  const eyeU = [];
  (D.eyes || []).forEach((e, i) => {
    const g = grp(B, e.p, [e.pitch || 0, e.yaw || 0, e.roll || 0]);
    const sk = D._sock.skins[i] || [1, 1, 1];
    const side = e.p[0] < 0 ? -1 : 1;
    const em = L ? spiritEye(Object.assign({ iris: cfg.iris ?? 0x8a4a12, iris2: cfg.iris2 ?? 0xffc04a, irisRim: cfg.irisRim ?? 0x2a1006, lash: cfg.lash ?? 0x1c1018, side, skin: linToHex(sk) }, eo))
      : critterEye(Object.assign({ iris: cfg.iris ?? 0x2a1a4a, iris2: cfg.iris2 ?? 0x8a6aff, lash: cfg.lash ?? 0x1c1018, side, skin: linToHex(sk) }, eo));
    part(GEO.sphere, em, g, [0, 0, 0], [e.r * 1.12, e.r * 1.25, e.r * (eo.depth ?? 0.5)]).userData.noOl = true;
    (r.blinkU = r.blinkU || []).push(em.userData.blink);
    eyeU.push(em.userData.expr);
    glue(g, 1);
  });
  // ear flicks: ear primitives carry the (otherwise unused) jaw weight and rotate about the ear hinge
  if (D.earHinge) {
    const amp = D.earAmp ?? -0.22;
    let next = rand(1, 4), ph = -1;
    r.fns.push((t, dt) => {
      next -= dt;
      if (next < 0) { ph = 0; next = rand(2.2, 6.5); }
      if (ph >= 0) { ph += dt * 3.2; U.uJaw.value = ph < 1 ? Math.sin(ph * Math.PI) * amp * (1 + 0.35 * Math.sin(ph * Math.PI * 4)) : 0; if (ph >= 1) ph = -1; }
    });
  }
  // expressions: a hit (flash) squeezes the eyes shut for a moment; r.expr = 'happy' | 'hurt' holds one; and an
  // occasional double blink so the rhythm never looks mechanical
  let hurtT = 0, prevBt = 0;
  r.fns.push((t, dt) => {
    U.uWalk.value = r.walkPhase; U.uStride.value = (D.stride ?? 0.12) * r.moving;
    for (const f of follow) f.obj.position.copy(f.base).add(dragonOffset(U, f.s, Shared.time.value).multiplyScalar(1));
    if (U.uFlash.value > 0.15) hurtT = 0.5;
    hurtT = Math.max(0, hurtT - dt);
    const hap = r.expr === 'happy' ? 1 : 0, hurt = hurtT > 0 || r.expr === 'hurt' ? 1 : 0;
    for (const x of eyeU) { x.value.x = damp(x.value.x, hap, 9, dt); x.value.y = damp(x.value.y, hurt, 22, dt); }
    if (prevBt > 0 && r.bt <= 0 && Math.random() < 0.22) r.nb = 0.09;
    prevBt = r.bt;
    if (r.blinkU) for (const u of r.blinkU) u.value = u.value >= 0 ? Math.min(u.value, 1) : 0;
  });
  r.glue = glue; r.B = B; r.critter = { U, mat };
  r.size = (D.height ?? 1.3) * (cfg.scale ?? 1);
  return B;
}
const eyePair = (hc, x, y, z, rad, yaw = 0.3, extra = {}) => [-1, 1].map((sx) => Object.assign({ p: add3(hc, [sx * x, y, z]), r: rad, yaw: sx * yaw }, extra, extra.roll ? { roll: sx * extra.roll } : {}));
// shading helpers for paint functions
const sst = (a, b, x) => { const t = Math.min(Math.max((x - a) / (b - a), 0), 1); return t * t * (3 - 2 * t); };

// ---------------------------------------------------------------- overlay helpers (signed distances, object units)
const lerp3 = (a, b, t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
const sdP = (P) => (v) => SDF.dist(P, v.x, v.y, v.z);
// along-axis cut: negative beyond fraction t0 of segment a→b (e.g. a dark ear tip), only on vertices that belong to
// the part (weight w from the sculpt: ears carry the jaw weight)
function sdTip(a, b, t0) {
  const ab = [b[0] - a[0], b[1] - a[1], b[2] - a[2]], l = Math.hypot(...ab);
  return (v) => (t0 - ((v.x - a[0]) * ab[0] + (v.y - a[1]) * ab[1] + (v.z - a[2]) * ab[2]) / (l * l)) * l;
}
const sdMin = (...fs) => (v) => { let d = 1e9; for (const f of fs) d = Math.min(d, f(v)); return d; };
const sdMax = (...fs) => (v) => { let d = -1e9; for (const f of fs) d = Math.max(d, f(v)); return d; };
// spots: spheres centred on an ellipsoid's surface along given directions
function sdSpots(c, rr, list) {
  const pts = list.map(([d, rad]) => {
    const l = Math.hypot(d[0] / rr[0], d[1] / rr[1], d[2] / rr[2]);
    return [c[0] + d[0] / l, c[1] + d[1] / l, c[2] + d[2] / l, rad];
  });
  return (v) => { let best = 1e9; for (const p of pts) best = Math.min(best, Math.hypot(v.x - p[0], v.y - p[1], v.z - p[2]) - p[3]); return best; };
}
const onPart = (key, min = 0.5) => (v) => (min - Math.abs(v[key])) * 0.12;

// ---------------- 화르르 / 염호 : flame fox — big cream cheek ruff and bib, dark socks and ear tips, peach inner ears,
// one bushy cream-tipped tail with a living flame (염호: three tails, ember ear tips, brow line, forehead gem)
function dFox(st) {
  return critter('fox' + st, () => {
    const K = critterKit(), O = st === 2 ? 0xf2541a : 0xff6a1c, CR = 0xfff0dc, DK = 0x3a1a14, NOSE = 0x2a1210, EAR = 0xffcdb6;
    const L = st === 2 ? 1.22 : 1, by = 0.5 * L, bz = st === 2 ? 0.5 : 0.42;
    K.el([0, by, 0], [0.3, 0.28, bz], O, { k: 0.1 });
    K.el([0, by + 0.04, bz - 0.17], [0.23, 0.25, 0.22], CR, { k: 0.12 });
    K.el([0, by - 0.12, -0.04], [0.2, 0.13, bz * 0.8], CR, { k: 0.12 });
    for (const x of [-0.1, 0, 0.1]) K.tuft([x * 0.8, by + 0.02, bz - 0.06], [x * 1.7, by - 0.17 - (x ? 0 : 0.03), bz + 0.06], 0.075, CR);
    for (const [sx, sz] of [[-1, 1], [1, 1], [-1, -1], [1, -1]]) {
      const leg = sx * sz > 0 ? 1 : -1;
      const hip = [sx * 0.16, by - 0.06, sz * (bz * 0.55)], paw = [sx * 0.175, 0.07, sz * (bz * 0.55) + 0.05];
      K.rc(hip, paw, 0.1, 0.066, O, { k: 0.07, leg });
      K.el([paw[0], 0.055, paw[2] + 0.025], [0.08, 0.055, 0.1], DK, { k: 0.04, leg });
      for (const tx of [-0.034, 0.034]) K.el([paw[0] + tx, 0.04, paw[2] + 0.11], [0.03, 0.028, 0.03], DK, { k: 0.02, leg });
    }
    const hc = [0, 0.98 * L, bz * 0.72];
    K.rc([0, by + 0.1, bz * 0.5], add3(hc, [0, -0.08, -0.05]), 0.17, 0.16, O, { k: 0.1, s0: 0.7, s1: 0.95 });
    if (st === 2) for (let i = 0; i < 9; i++) {
      const a = -1.7 + (i / 8) * 3.4, nc = [0, by + 0.32, bz * 0.62];
      K.tuft(add3(nc, [Math.sin(a) * 0.08, 0.02, Math.cos(a) * 0.06]), add3(nc, [Math.sin(a) * 0.3, -0.14 - Math.cos(a) * 0.05, Math.cos(a) * 0.26 + 0.02]), 0.1, CR, { k: 0.05, s0: 0.85, s1: 0.85 });
    }
    K.el(hc, [0.33, 0.3, 0.29], O, Object.assign({ k: 0.08 }, HEAD));
    for (const sx of [-1, 1]) {
      K.el(add3(hc, [sx * 0.2, -0.1, 0.06]), [0.16, 0.12, 0.14], CR, Object.assign({ k: 0.07 }, HEAD));
      K.tuft(add3(hc, [sx * 0.24, -0.07, 0.03]), add3(hc, [sx * 0.45, -0.15, -0.05]), 0.08, CR, Object.assign({}, HEAD));
      K.tuft(add3(hc, [sx * 0.22, -0.15, 0.05]), add3(hc, [sx * 0.38, -0.27, -0.01]), 0.065, CR, Object.assign({}, HEAD));
    }
    K.el(add3(hc, [0, -0.09, 0.24]), [0.13, 0.09, 0.14], CR, Object.assign({ k: 0.06 }, HEAD));
    K.el(add3(hc, [0, -0.05, 0.37]), [0.05, 0.034, 0.032], NOSE, Object.assign({ k: 0.02 }, HEAD));
    K.tuft(add3(hc, [0.0, 0.2, 0.1]), add3(hc, [0.05, 0.36, 0.17]), 0.06, O, Object.assign({}, HEAD));
    const eh = st === 2 ? 1.18 : 1, ears = [];
    for (const sx of [-1, 1]) {
      const a = add3(hc, [sx * 0.14, 0.18, -0.02]), b = add3(hc, [sx * 0.28, 0.52 * eh, -0.06]);
      K.rc(a, b, 0.115, 0.012, O, Object.assign({ k: 0.05, jaw: 1 }, HEAD)); ears.push([a, b]);
    }
    const tails = st === 2 ? [-0.24, 0, 0.24] : [0], tips = [];
    for (const tx of tails) {
      const p0 = [tx * 0.3, by + 0.05, -bz * 0.85], p1 = [tx, by + 0.26, -bz - 0.24], p2 = [tx * 1.25, by + 0.6, -bz - 0.36], p3 = [tx * 1.35, by + 0.86, -bz - 0.26];
      K.rc(p0, p1, 0.1, 0.18, O, { k: 0.07, s0: 0.32, s1: 0.22 });
      K.rc(p1, p2, 0.18, 0.165, O, { k: 0.06, s0: 0.22, s1: 0.1 });
      K.rc(p2, p3, 0.165, 0.035, CR, { k: 0.05, s0: 0.1, s1: 0.0 });
      tips.push([p2, p3]);
    }
    const hy = hc[1], hz = hc[2];
    // markings: inner ears (a slimmer cone set forward of each ear), ear tips, socks, a warm glow on the tail tip
    const inner = ears.map(([a, b]) => sdP(SDF.rc(add3(lerp3(a, b, 0.16), [0, 0, 0.066]), add3(lerp3(a, b, 0.8), [0, 0, 0.044]), 0.084, 0.012)));
    const look = {
      kind: 'fur',
      mats: { [NOSE]: 'nose' },
      shade: { tint: [0.95, 0.66, 0.92], midTint: [1.14, 0.8, 0.74], hue: 0x7a3c78, hueK: 0.24 },
      over: [
        { col: DK, sd: sdMax((v) => v.y - 0.2 * L, onPart('leg', 0.45)) },
        { col: EAR, sd: sdMax(sdMin(...inner), onPart('jaw')) },
        { col: st === 2 ? 0xffb44a : DK, mat: st === 2 ? 'ember' : undefined, sd: sdMax(sdMin(...ears.map(([a, b]) => sdTip(a, b, st === 2 ? 0.66 : 0.7))), onPart('jaw')) },
        { col: 0xffe2a0, em: 0.4, sd: sdMin(...tips.map(([a, b]) => sdMax(sdTip(a, b, 0.62), (v) => v.z - b[2] - 0.2))) },
      ],
    };
    const face = {
      mouth: [0, hy - 0.125, hz + 0.3, st === 2 ? 0.04 : 0.045], mouthK: 1, line: 0x3a1410,
      blush: [0.19, hy - 0.075, hz + 0.12, 0.06], blushCol: 0xff7a74, blushEdge: 0.7, blushA: 0.42,
      mark: st === 2 ? null : [0, hy + 0.165, hz + 0.15, 0.055], markK: 1, markCol: 0xffd25a, markGlow: 0xffa030,
      brow: st === 2 ? [0.12, hy + 0.115, hz + 0.18, 0.04] : null, browTilt: -0.35, browCol: 0x7a2408,
    };
    return { prims: K.prims, bounds: [-0.8, -0.05, -bz - 0.8, 0.8, 1.8 * L, bz + 0.75], hipY: by, height: 1.45 * L, stride: 0.12, look, face, socket: 0.35, lidFold: 0,
      earHinge: add3(hc, [0, 0.16, -0.04]), earAmp: -0.2,
      eyes: eyePair(hc, 0.138, 0.015, 0.252, st === 2 ? 0.086 : 0.094, 0.3), tails: tails.map((tx) => [tx * 1.35, by + 0.92, -bz - 0.26]), hc, eh };
  });
}
function foxModel(r, st) {
  const D = dFox(st);
  const B = buildCritter(r, { key: 'fox' + st, design: D, scale: st === 2 ? 1.25 : 1, iris: st === 2 ? 0xd4661a : 0xd8801e, iris2: 0xffd468, irisRim: st === 2 ? 0x4a1204 : 0x5a1c06, lash: 0x2a1010,
    eye: st === 2 ? { open: 0.66, tilt: 0.14, wing: 0.9, irisR: 0.6 } : { open: 0.82, tilt: 0.05, wing: 0.45, irisR: 0.64 } });
  for (const tp of D.tails) { const f = flame(r, B, tp, st === 2 ? 0.66 : 0.8); r.glue(f, 0); }
  if (st === 2) {
    for (const sx of [-1, 1]) { const f = flame(r, B, add3(D.hc, [sx * 0.29, 0.58 * D.eh, -0.06]), 0.32); r.glue(f, 1); }
    const gem = spiritPart(r, GEO.octa, 0xffd25a, 'glow', B, add3(D.hc, [0, 0.165, 0.27]), [0.042, 0.068, 0.03], [0, 0, 0], { em: 1.6, outline: false }); r.glue(gem, 1);
  }
  r.size = 1.4 * (st === 2 ? 1.25 : 1);
}
MODELS.hwarr = (r) => foxModel(r, 1);
MODELS.yeomho = (r) => foxModel(r, 2);

// ---------------- 물롱 / 파도롱 : sea-pup — glossy water-jelly skin, white muzzle and belly, pale fins, a few deep-blue
// spots on the crown and back, a floating bubble (파도롱: crest fins, glowing tide lines, water ring)
function dSeal(st) {
  return critter('seal' + st, () => {
    const K = critterKit(), BL = st === 2 ? 0x3a8ff0 : 0x55b8fb, WH = 0xeef8ff, FN = 0x9fe9ff, NOSE = 0x173052, CRS = 0x2f74d4;
    K.el([0, 0.44, 0], [0.46, 0.4, 0.55], BL, { k: 0.12 });
    K.el([0, 0.36, 0.14], [0.35, 0.29, 0.42], BL, { k: 0.12 });
    K.rc([0, 0.36, -0.38], [0, 0.2, -0.62], 0.25, 0.1, BL, { k: 0.1, s0: 0.3, s1: 0.1 });
    for (const sx of [-1, 1]) {
      K.el([sx * 0.15, 0.17, -0.7], [0.17, 0.045, 0.12], FN, { k: 0.05, s0: 0.05, s1: 0.05 });
      K.el([sx * 0.5, 0.17, 0.22], [0.2, 0.05, 0.12], BL, { k: 0.07, leg: sx });
      K.el([sx * 0.62, 0.16, 0.27], [0.08, 0.035, 0.07], FN, { k: 0.05, leg: sx });
    }
    const hc = [0, 0.9, 0.2];
    K.el(hc, [0.38, 0.35, 0.35], BL, Object.assign({ k: 0.14 }, HEAD));
    for (const sx of [-1, 1]) K.el(add3(hc, [sx * 0.078, -0.125, 0.27]), [0.1, 0.078, 0.08], WH, Object.assign({ k: 0.05 }, HEAD));
    K.el(add3(hc, [0, -0.2, 0.24]), [0.11, 0.06, 0.08], WH, Object.assign({ k: 0.06 }, HEAD));
    K.el(add3(hc, [0, -0.07, 0.345]), [0.052, 0.036, 0.034], NOSE, Object.assign({ k: 0.02 }, HEAD));
    const fs = st === 2 ? 1.25 : 1;
    for (const sx of [-1, 1]) {
      K.el(add3(hc, [sx * 0.33, 0.1, -0.02]), [0.2 * fs, 0.055, 0.13], FN, Object.assign({ k: 0.05, jaw: 1 }, HEAD));
      K.tuft(add3(hc, [sx * 0.4, 0.11, -0.04]), add3(hc, [sx * (0.36 + 0.22 * fs), 0.2, -0.12]), 0.07, FN, Object.assign({ jaw: 1 }, HEAD));
    }
    if (st === 2) for (let i = 0; i < 3; i++) K.rc(add3(hc, [0, 0.3 - i * 0.04, -0.08 - i * 0.12]), add3(hc, [0, 0.58 - i * 0.07, -0.3 - i * 0.14]), 0.065, 0.008, CRS, Object.assign({ k: 0.04 }, HEAD));
    const hy = hc[1], hz = hc[2];
    const spotC = st === 2 ? 0x1d5fb8 : 0x2c86d8;
    const spots = sdMin(
      sdSpots(hc, [0.38, 0.35, 0.35], [[[0.42, 0.85, -0.3], 0.048], [[-0.34, 0.92, -0.4], 0.04], [[0.06, 0.7, -0.75], 0.056]]),
      sdSpots([0, 0.44, 0], [0.46, 0.4, 0.55], [[[0.55, 0.62, -0.55], 0.066], [[-0.5, 0.66, -0.62], 0.056], [[0.12, 0.55, -0.85], 0.05], [[-0.78, 0.38, -0.3], 0.046], [[0.8, 0.36, -0.12], 0.04], [[-0.2, 0.42, -0.9], 0.04]]));
    const belly = (v) => Math.max((Math.hypot(v.x / 0.27, (v.y - 0.33) / 0.3) - 1) * 0.24, (0.06 - v.z) * 0.4);
    const over = [{ col: WH, mat: 'water', sd: belly }, { col: spotC, sd: spots }];
    if (st === 2) over.push({ col: 0xc6f8ff, mat: 'glow', em: 1.1, sd: sdMax((v) => Math.abs(v.y - (0.4 + 0.045 * Math.sin(v.z * 8 + 0.6))) - 0.014, (v) => 0.3 - Math.abs(v.x), (v) => v.z - 0.18) });
    const look = { kind: 'water', mats: { [NOSE]: 'nose', [WH]: 'water', [FN]: 'water' }, shade: { tint: [0.72, 0.85, 1.1], hue: 0x2a46a8, hueK: 0.2 }, over };
    const face = {
      mouth: [0, hy - 0.17, hz + 0.24, 0.055], mouthK: st === 2 ? 1 : 3, line: 0x1a2a44,
      blush: [0.215, hy - 0.06, hz + 0.16, 0.065], blushCol: 0xff8aa8, blushEdge: 0.7, blushA: 0.4,
    };
    return { prims: K.prims, bounds: [-0.9, -0.05, -0.95, 0.9, 1.5, 0.75], hipY: 0.3, height: 1.4, stride: 0.06, look, face, socket: 0.35, lidFold: 0,
      earHinge: add3(hc, [0, 0.1, -0.02]), earAmp: 0.3,
      eyes: eyePair(hc, 0.165, 0.045, 0.29, 0.1, 0.32), hc };
  });
}
function sealModel(r, st) {
  const D = dSeal(st);
  const B = buildCritter(r, { key: 'seal' + st, design: D, scale: st === 2 ? 1.36 : 1, hop: 0.5, iris: 0x2a86e8, iris2: 0x9cecff, irisRim: 0x0a2458, lash: 0x0c1a30, olc: 0x10203a,
    eye: st === 2 ? { open: 0.74, tilt: 0.1, wing: 0.6, irisR: 0.62 } : { open: 0.86, tilt: 0.02, wing: 0.3, irisR: 0.66 } });
  const orb = grp(B, add3(D.hc, [0, 0.5, -0.04]));
  part(GEO.sphere, toonMat({ color: 0xa6f0ff, transparent: true, opacity: 0.4 }), orb, [0, 0, 0], 0.15);
  part(GEO.sphere, E(0x9cf0ff, 2.0), orb, [0, 0, 0], 0.06);
  part(GEO.sphere, E(0xffffff, 1.8), orb, [-0.05, 0.06, 0.08], 0.025);
  wig(r, orb, 'z', 0.12, 1.7); wig(r, orb, 'x', 0.08, 1.3, 1.1);
  r.glue(orb, 1);
  if (st === 2) {
    const ring = grp(B, [0, 0.42, 0], [Math.PI / 2 + 0.12, 0, 0]);
    part(GEO.torus, toonMat({ color: 0x8fe8ff, transparent: true, opacity: 0.5, depthWrite: false }), ring, [0, 0, 0], [0.74, 0.74, 1.6]);
    part(GEO.ring, E(0xc8f8ff, 1.5), ring, [0, 0, 0], 0.76);
    for (let i = 0; i < 8; i++) { const a = (i / 8) * Math.PI * 2; part(GEO.sphere, E(0xbff6ff, 1.9), ring, [Math.cos(a) * 0.74, Math.sin(a) * 0.74, 0], 0.03 + (i % 2) * 0.015); }
    spin(r, ring, 'z', 0.7);
  }
  r.size = 1.45 * (st === 2 ? 1.36 : 1);
}
MODELS.mullong = (r) => sealModel(r, 1);
MODELS.padolong = (r) => sealModel(r, 2);

// ---------------- 새싹뿔 / 숲뿔사슴 : sprout fawn — honey coat with cream dapples, cream muzzle / belly / tail, satin
// leaf ears with a midrib, a sprout on the crown (숲뿔사슴: antlers with blossoms, leafy collar, glowing sap tips)
function dFawn(st) {
  return critter('fawn' + st, () => {
    const K = critterKit(), FW = st === 2 ? 0xc8925a : 0xe2b37c, CR = 0xfff3dc, LF = 0x62d35a, LF2 = 0x8ee26e, DK = 0x3a2416, NOSE = 0x2a1810, AN = 0x7a5232;
    const LL = st === 2 ? 1.18 : 1;
    K.el([0, 0.78 * LL, 0], [0.28, 0.26, 0.46], FW, { k: 0.1 });
    K.el([0, 0.7 * LL, 0.04], [0.2, 0.16, 0.36], CR, { k: 0.1 });
    for (const [sx, sz] of [[-1, 1], [1, 1], [-1, -1], [1, -1]]) {
      const leg = sx * sz > 0 ? 1 : -1;
      const hip = [sx * 0.15, 0.66 * LL, sz * 0.26], knee = [sx * 0.155, 0.36 * LL, sz * 0.27 - (sz > 0 ? 0 : 0.03)], hoof = [sx * 0.15, 0.08, sz * 0.27];
      K.rc(hip, knee, 0.085, 0.05, FW, { k: 0.06, leg });
      K.rc(knee, hoof, 0.05, 0.042, FW, { k: 0.04, leg });
      K.el([hoof[0], 0.045, hoof[2] + 0.012], [0.052, 0.045, 0.062], DK, { k: 0.02, leg });
    }
    const hc = [0, 1.27 * LL, 0.45];
    K.rc([0, 0.9 * LL, 0.3], add3(hc, [0, -0.08, -0.06]), 0.12, 0.095, FW, { k: 0.08, s0: 0.7, s1: 0.95 });
    K.el(hc, [0.24, 0.23, 0.25], FW, Object.assign({ k: 0.07 }, HEAD));
    K.el(add3(hc, [0, -0.075, 0.19]), [0.13, 0.11, 0.14], CR, Object.assign({ k: 0.06 }, HEAD));
    K.el(add3(hc, [0, -0.045, 0.325]), [0.042, 0.03, 0.026], NOSE, Object.assign({ k: 0.02 }, HEAD));
    K.tuft(add3(hc, [0, 0.16, 0.08]), add3(hc, [0.03, 0.27, 0.16]), 0.05, FW, Object.assign({}, HEAD));
    const ribs = [];
    for (const sx of [-1, 1]) {
      // leaf ears: broad blade + pointed tip, they flick
      K.el(add3(hc, [sx * 0.27, 0.075, -0.03]), [0.15, 0.036, 0.08], LF, Object.assign({ k: 0.05, jaw: 1 }, HEAD));
      K.rc(add3(hc, [sx * 0.36, 0.085, -0.035]), add3(hc, [sx * 0.5, 0.13, -0.055]), 0.055, 0.006, LF, Object.assign({ k: 0.03, jaw: 1 }, HEAD));
      K.tuft(add3(hc, [sx * 0.17, -0.1, 0.0]), add3(hc, [sx * 0.29, -0.18, -0.06]), 0.05, CR, Object.assign({}, HEAD));
      ribs.push([add3(hc, [sx * 0.15, 0.07, -0.028]), add3(hc, [sx * 0.49, 0.128, -0.053])]);
    }
    if (st === 2) {
      for (const sx of [-1, 1]) {
        const a = add3(hc, [sx * 0.1, 0.18, -0.06]), b = add3(hc, [sx * 0.24, 0.62, -0.18]), c2 = add3(hc, [sx * 0.3, 0.85, -0.3]);
        K.rc(a, b, 0.037, 0.029, AN, Object.assign({ k: 0.03 }, HEAD));
        K.rc(b, c2, 0.029, 0.012, AN, Object.assign({ k: 0.02 }, HEAD));
        K.rc(add3(hc, [sx * 0.17, 0.4, -0.12]), add3(hc, [sx * 0.42, 0.55, -0.05]), 0.023, 0.01, AN, Object.assign({ k: 0.02 }, HEAD));
        K.rc(add3(hc, [sx * 0.22, 0.55, -0.16]), add3(hc, [sx * 0.15, 0.78, -0.08]), 0.02, 0.008, AN, Object.assign({ k: 0.02 }, HEAD));
      }
      // leafy collar around the neck
      for (let i = 0; i < 9; i++) {
        const a = -2.0 + (i / 8) * 4.0, nc = [0, 1.0 * LL, 0.36];
        K.rc(add3(nc, [Math.sin(a) * 0.08, 0.02, Math.cos(a) * 0.06]), add3(nc, [Math.sin(a) * 0.27, -0.14, Math.cos(a) * 0.22 + 0.03]), 0.07, 0.008, i % 2 ? LF : LF2, { k: 0.04, s0: 0.85, s1: 0.85 });
      }
    }
    K.el([0, 0.86 * LL, -0.47], [0.075, 0.09, 0.065], CR, { k: 0.04, s0: 0.2, s1: 0.2 });
    const hy = hc[1], hz = hc[2];
    // dapples: two staggered rows each side of the spine, on the top of the body
    const spotP = [];
    for (const sx of [-1, 1]) for (let i = 0; i < 5; i++) for (const [x, dz] of [[0.075, 0], [0.155, 0.06]]) {
      const z = -0.36 + i * 0.12 + dz + (sx > 0 ? 0.03 : 0), xx = sx * (x + (i % 2) * 0.012);
      if (z > 0.2) continue;
      spotP.push([xx, 0.78 * LL + 0.26 * Math.sqrt(Math.max(0, 1 - (xx / 0.28) ** 2 - (z / 0.46) ** 2)), z, 0.027 + ((i + (x > 0.1 ? 1 : 0)) % 2) * 0.006]);
    }
    const dapple = (v) => { let b = 1e9; for (const p of spotP) b = Math.min(b, Math.hypot(v.x - p[0], v.y - p[1], v.z - p[2]) - p[3]); return b; };
    const rib = (a, b) => (v) => {
      // distance to the midrib in the leaf plane (x/z), so it shows on both faces of the flat blade
      const ax = b[0] - a[0], az = b[2] - a[2], t = clamp(((v.x - a[0]) * ax + (v.z - a[2]) * az) / (ax * ax + az * az), 0, 1);
      return Math.hypot(v.x - a[0] - ax * t, v.z - a[2] - az * t) - 0.0065 * (1.2 - t);
    };
    const over = [
      { col: CR, sd: sdMax(dapple, (v) => 0.86 * LL - v.y) },
      { col: 0x2f9a3e, mat: 'leaf', sd: sdMax(sdMin(...ribs.map(([a, b]) => rib(a, b))), onPart('jaw')) },
    ];
    if (st === 2) over.push({ col: 0xdcffb8, mat: 'glow', em: 0.9, sd: sdMax((v) => hy + 0.66 - v.y, (v) => 0.06 - Math.abs(v.x)) });
    const look = { kind: 'fur', mats: { [LF]: 'leaf', [LF2]: 'leaf', [AN]: 'horn', [DK]: 'hoof', [NOSE]: 'nose' }, shade: { tint: [0.95, 0.7, 0.9], midTint: [1.12, 0.84, 0.74], hue: 0x6c4a86, hueK: 0.22 }, over };
    const face = {
      mouth: [0, hy - 0.118, hz + 0.22, 0.034], mouthK: 2, line: 0x3a1a10,
      blush: [0.15, hy - 0.06, hz + 0.1, 0.048], blushCol: 0xff8a84, blushEdge: 0.7, blushA: 0.4,
    };
    return { prims: K.prims, bounds: [-0.75, -0.05, -0.8, 0.75, (st === 2 ? 2.45 : 1.8) * LL, 0.95], hipY: 0.66 * LL, height: 1.6 * LL, stride: 0.14, look, face, socket: 0.35, lidFold: 0,
      earHinge: add3(hc, [0, 0.07, -0.03]), earAmp: 0.3,
      eyes: eyePair(hc, 0.118, 0.035, 0.192, 0.08, 0.34), hc };
  });
}
function fawnModel(r, st) {
  const D = dFawn(st);
  const B = buildCritter(r, { key: 'fawn' + st, design: D, scale: st === 2 ? 1.25 : 1, iris: 0x3c9a2e, iris2: 0xb4f07a, irisRim: 0x0f2e0c, lash: 0x24140c,
    eye: { open: st === 2 ? 0.72 : 0.84, tilt: st === 2 ? 0.1 : 0.04, wing: 1.0, irisR: 0.64 } });
  // crown sprout: a stem and two satin leaves in the same cel look, swaying
  const sp = grp(B, add3(D.hc, [0, 0.22, 0]));
  spiritPart(r, GEO.cyl, 0x4fbf5f, 'leaf', sp, [0, 0.08, 0], [0.02, 0.18, 0.02]);
  for (const s of [-1, 1]) spiritPart(r, GEO.sphere, 0x74e06a, 'leaf', sp, [s * 0.08, 0.18, 0], [0.1, 0.028, 0.055], [0, 0, s * 0.5]);
  wig(r, sp, 'z', 0.15, 2.8); r.glue(sp, 1);
  if (st === 2) {
    // antler blossoms: per side one merged leaf mesh + one merged petal mesh (+ glowing centres), swaying gently
    for (const sx of [-1, 1]) {
      const g = grp(B, add3(D.hc, [0, 0, 0]));
      const leaves = [], petals = [], centres = [];
      const M4 = new THREE.Matrix4(), Q = new THREE.Quaternion(), Ee = new THREE.Euler(), Vp = new THREE.Vector3(), Vs = new THREE.Vector3();
      const put = (list, geo, p, s, rot) => { Ee.set(rot[0], rot[1], rot[2]); Q.setFromEuler(Ee); M4.compose(Vp.set(p[0], p[1], p[2]), Q, Vs.set(s[0], s[1], s[2])); list.push(geo.clone().applyMatrix4(M4)); };
      for (const [x, y, z, k] of [[0.3, 0.88, -0.3, 0], [0.42, 0.58, -0.05, 1], [0.15, 0.8, -0.08, 2]]) {
        const c = [sx * x, y, z];
        for (let j = 0; j < 4; j++) { const a = j * 1.57 + k; put(leaves, GEO.sphereLo, add3(c, [Math.cos(a) * 0.07, 0.015 * j, Math.sin(a) * 0.07]), [0.1, 0.022, 0.05], [0.3, -a, 0.35]); }
        for (let j = 0; j < 5; j++) { const a = j * 1.2566 + k; put(petals, GEO.sphereLo, add3(c, [Math.cos(a) * 0.036, 0.05, Math.sin(a) * 0.036]), [0.03, 0.013, 0.03], [0, 0, 0]); }
        put(centres, GEO.sphereLo, add3(c, [0, 0.056, 0]), [0.022, 0.016, 0.022], [0, 0, 0]);
      }
      spiritPart(r, mergeGeometries(leaves), 0x5cc95a, 'leaf', g, [0, 0, 0], 1);
      spiritPart(r, mergeGeometries(petals), 0xffc4e6, 'skin', g, [0, 0, 0], 1);
      spiritPart(r, mergeGeometries(centres), 0xfff2a8, 'glow', g, [0, 0, 0], 1, [0, 0, 0], { em: 1.2, outline: false, shadow: false });
      wig(r, g, 'z', 0.03, 1.6, sx); r.glue(g, 1);
    }
  }
  r.size = 1.6 * (st === 2 ? 1.25 : 1);
}
MODELS.saessak = (r) => fawnModel(r, 1);
MODELS.supppul = (r) => fawnModel(r, 2);

// ---------------- 찌릿파리 : storm jelly — glassy bell, glowing lightning band, frilled rim, trailing tendrils
MODELS.jjirit = (r) => {
  const D = critter('jelly', () => {
    const K = critterKit(), Y = 0xf2b428, Y2 = 0xe8901a;
    K.el([0, 0.05, 0], [0.5, 0.46, 0.5], Y, { k: 0.08 });
    K.el([0, 0.3, 0], [0.32, 0.22, 0.32], 0xfff09a, { k: 0.12 });
    K.sub([0, -0.36, 0], [0.62, 0.36, 0.62], 0.09);
    for (let i = 0; i < 12; i++) { const a = (i / 12) * Math.PI * 2; K.el([Math.cos(a) * 0.46, -0.02, Math.sin(a) * 0.46], [0.075, 0.06, 0.075], Y2, { k: 0.05 }); }
    const cBolt = hexRGB(0xfffbe0), cDeep = hexRGB(0xe08a10), cCap = hexRGB(0xfff0a8);
    const paint = (v) => {
      // zig-zag lightning band around the bell
      const ang = Math.atan2(v.z, v.x), zz = Math.abs(((ang * 7 / Math.PI) % 2 + 2) % 2 - 1);
      const band = 1 - sst(0.012, 0.03, Math.abs(v.y - (0.16 + (zz - 0.5) * 0.12)));
      if (v.ny > -0.3) { v.g = Math.max(v.g, band); tintV(v, cBolt, band); }
      // deeper amber toward the rim, glowing dots on the frill
      if (v.y < 0.08) tintV(v, cDeep, sst(0.08, -0.05, v.y) * 0.45);
      if (Math.hypot(v.x, v.z) > 0.45 && v.y < 0.05) v.g = Math.max(v.g, 0.22);
      if (v.y > 0.3 && v.ny > 0.5) tintV(v, cCap, sst(0.5, 0.95, v.ny) * 0.5);
    };
    const face = { mouth: [0, 0.06, 0.38, 0.06], mouthK: 3, line: 0x4a2a00, blush: [0.25, 0.12, 0.3, 0.06], blushCol: 0xff8a5a };
    return { prims: K.prims, bounds: [-0.65, -0.25, -0.65, 0.65, 0.6, 0.65], hipY: 0, height: 1.0, paint, face,
      eyes: [-1, 1].map((sx) => ({ p: [sx * 0.165, 0.2, 0.41], r: 0.085, yaw: sx * 0.32, pitch: -0.25 })) };
  });
  const B = buildCritter(r, { key: 'jelly', design: D, float: 1.0, floatAmp: 0.12, iris: 0x3a2400, iris2: 0xffd84a, lash: 0x3a2000,
    eye: { open: 0.84, wing: 0.3, irisR: 0.64 },
    mat: { kind: 'jelly', rough: 0.14, coat: 1.0, coatRough: 0.04, sheen: 0, soft: 0.03, fuzz: 0.0, rimAmt: 0.22, rim: 0xfff2a0, env: 0.4, glow: 0xfff3a0, glowAmt: 2.4, innerCol: 0xffd870 } });
  const core = part(GEO.sphere, E(0xfff6c8, 3.0), B, [0, 0.12, -0.05], 0.11);
  r.fns.push((t) => core.scale.setScalar(0.11 * (1 + Math.sin(t * 9) * 0.18 * Math.max(0, Math.sin(t * 1.3)))));
  for (let i = 0; i < 7; i++) {
    const a = (i / 7) * Math.PI * 2 + 0.3, rr = i % 2 ? 0.3 : 0.2;
    let p = grp(B, [Math.cos(a) * rr, -0.06, Math.sin(a) * rr]);
    for (let k = 0; k < 4; k++) { part(GEO.cyl, E(0xfff0a0, 1.2), p, [0, -0.1, 0], [0.024 - k * 0.004, 0.2, 0.024 - k * 0.004]); wig(r, p, 'x', 0.22, 2.4, i + k * 0.8); wig(r, p, 'z', 0.18, 1.9, i * 2 + k); p = grp(p, [0, -0.2, 0]); }
    part(GEO.sphere, E(0xfffbd0, 2.6), p, [0, 0, 0], 0.032);
  }
  for (const s of [-1, 1]) {
    const an = grp(B, [s * 0.13, 0.46, 0], [0, 0, -s * 0.32]);
    part(GEO.cyl, M(0xffbf2e), an, [0, 0.08, 0], [0.018, 0.16, 0.018]);
    const bolt = grp(an, [0, 0.2, 0]);
    part(GEO.octa, E(0xffffff, 3), bolt, [0, 0, 0], [0.035, 0.05, 0.035]);
    wig(r, an, 'z', 0.2, 4, s);
  }
  r.size = 1.6;
};

// ---------------- 바위몽 : boulder golem — stacked boulders, brow ridge, knuckle fists, moss cap, glowing crystal veins
MODELS.bawimong = (r) => {
  const D = critter('rock', () => {
    const K = critterKit(), RK = 0x878992, RK2 = 0xa3a6ae, RK3 = 0x5f626c, MS = 0x6fa24a;
    K.el([0, 0.55, 0], [0.52, 0.45, 0.48], RK, { k: 0.1, nz: 0.09, nf: 4.5 });
    K.el([0, 0.86, -0.18], [0.36, 0.26, 0.32], RK2, { k: 0.1, nz: 0.06, nf: 6 });
    K.el([0, 0.58, 0.27], [0.33, 0.28, 0.2], RK2, { k: 0.08, nz: 0.025, nf: 8, s0: 1, s1: 1 });
    K.el([0, 0.75, 0.37], [0.34, 0.07, 0.11], RK3, { k: 0.06, nz: 0.03, nf: 9, s0: 1, s1: 1 });
    K.el([0.05, 0.98, -0.02], [0.3, 0.08, 0.26], MS, { k: 0.06, nz: 0.035, nf: 11 });
    for (const sx of [-1, 1]) K.sub([sx * 0.155, 0.612, 0.5], [0.088, 0.078, 0.07], 0.035);
    for (const sx of [-1, 1]) {
      K.el([sx * 0.47, 0.8, -0.04], [0.22, 0.2, 0.22], RK, { k: 0.08, nz: 0.06, nf: 6 });
      K.rc([sx * 0.55, 0.66, 0.04], [sx * 0.62, 0.3, 0.16], 0.16, 0.13, RK, { k: 0.08, nz: 0.04, nf: 7, leg: sx });
      K.el([sx * 0.63, 0.2, 0.2], [0.18, 0.16, 0.19], RK2, { k: 0.06, nz: 0.04, nf: 8, leg: sx });
      K.el([sx * 0.24, 0.12, 0.02], [0.17, 0.13, 0.2], RK3, { k: 0.06, nz: 0.03, nf: 8, leg: -sx });
    }
    const cWarm = hexRGB(0x9a8a7a), cMoss = hexRGB(0x7cb04e), cMoss2 = hexRGB(0x4f8a3a), cTop = hexRGB(0xb2b8c4), cLow = hexRGB(0x4e5262), cVein = hexRGB(0xd2b8ff);
    const paint = (v) => {
      // cool stone: lit tops, darker underside
      tintV(v, cTop, sst(0.3, 0.9, v.ny) * 0.3);
      tintV(v, cLow, sst(-0.2, -0.8, v.ny) * 0.5);
      // granite: crevices of the displaced surface darken, fine flecks and broad mineral patches
      shadeV(v, 1 - sst(0.5, 0.85, vn3js(v.x * 4.5, v.y * 4.5, v.z * 4.5)) * 0.4);
      shadeV(v, 0.86 + 0.28 * sst(0.25, 0.75, vn3js(v.x * 26 + 9, v.y * 26, v.z * 26)));
      tintV(v, cWarm, sst(0.55, 0.8, vn3js(v.x * 2.5 + 3, v.y * 2.5, v.z * 2.5 + 8)) * 0.35);
      // moss creeping over the top
      const mn = vn3js(v.x * 6 + 1, v.y * 6, v.z * 6 + 4);
      if (v.ny > 0.2 && v.y > 0.7) { const m = sst(0.2, 0.65, v.ny) * sst(0.3, 0.62, mn + (v.y - 0.8)); tintV(v, cMoss2, m); tintV(v, cMoss, m * sst(0.4, 0.75, vn3js(v.x * 14, v.y * 14, v.z * 14 + 2))); }
      // purple crystal veins cracking through the back and shoulders
      if (v.z < 0.25 || Math.abs(v.x) > 0.35) {
        const vn = Math.abs(vn3js(v.x * 5.5 + 7, v.y * 5.5 + 2, v.z * 5.5) - 0.5);
        const vein = (1 - sst(0.008, 0.022, vn)) * sst(0.58, 0.72, vn3js(v.x * 2.2, v.y * 2.2 + 5, v.z * 2.2)) * (1 - sst(0.3, 0.7, v.ny));
        if (vein > 0) { v.g = Math.max(v.g, vein * 0.6); tintV(v, cVein, vein * 0.6); }
      }
    };
    const face = { mouth: [0, 0.47, 0.42, 0.07], mouthK: 2, line: 0x1e1a24, blush: [0.21, 0.52, 0.38, 0.06], blushCol: 0xc88a9a, hatch: 0 };
    return { prims: K.prims, bounds: [-0.95, -0.05, -0.7, 0.95, 1.2, 0.75], hipY: 0.3, height: 1.3, stride: 0.08, paint, face,
      eyes: [-1, 1].map((sx) => ({ p: [sx * 0.155, 0.612, 0.425], r: 0.088, yaw: sx * 0.24 })) };
  });
  const B = buildCritter(r, { key: 'rock', design: D, hop: 0.35, iris: 0x1a1030, iris2: 0xa98bff, lash: 0x14101c, sway: 0.15,
    eye: { open: 0.66, tilt: -0.04, wing: 0.15, irisR: 0.62 },
    mat: { kind: 'rock', rough: 0.92, sheen: 0.05, coat: 0, soft: 0.02, fuzz: 0.0, env: 0.24, rimAmt: 0.03, glow: 0xa98bff, glowAmt: 2.0 } });
  const cm = E(0x9b7bff, 1.9), cm2 = E(0xc8b0ff, 2.2);
  for (const [x, y, z, w, h, rx, rz, b] of [[0, 1.02, -0.22, 0.12, 0.38, -0.35, 0, 0], [-0.22, 0.96, -0.3, 0.09, 0.27, -0.55, 0.5, 1], [0.24, 0.95, -0.28, 0.1, 0.25, -0.5, -0.55, 0], [0.06, 0.78, -0.52, 0.08, 0.22, -1.2, 0, 1], [-0.1, 1.04, -0.08, 0.06, 0.16, -0.2, 0.35, 1], [0.5, 0.95, -0.12, 0.07, 0.18, -0.3, -0.8, 0], [-0.48, 0.94, -0.1, 0.065, 0.16, -0.3, 0.8, 1]]) part(GEO.cone6, b ? cm2 : cm, B, [x, y, z], [w, h, w], [rx, 0, rz]);
  r.size = 1.3;
};

// ---------------- 반디루 : lantern firefly — fluffy collar, glowing banded lantern, gossamer wings
MODELS.bandiru = (r) => {
  const D = critter('firefly', () => {
    const K = critterKit(), CRM = 0xfff0c9, FL = 0xfffaf0;
    K.el([0, 0.02, 0.04], [0.3, 0.28, 0.29], CRM, { k: 0.08, s0: 1, s1: 1 });
    K.el([0, -0.12, 0.04], [0.29, 0.13, 0.27], 0xffe2a0, { k: 0.08, s0: 1, s1: 1 });
    K.el([0, -0.06, -0.24], [0.17, 0.16, 0.16], 0x6a4a34, { k: 0.08, s0: 0.4, s1: 0.4 });
    K.el([0, -0.12, -0.44], [0.2, 0.19, 0.24], 0xfff2a0, { k: 0.07, s0: 0.2, s1: 0.2, glow: 1 });
    for (let i = 0; i < 10; i++) {
      const a = (i / 10) * Math.PI * 2, c = [0, -0.04, -0.13];
      K.tuft(add3(c, [Math.cos(a) * 0.12, Math.sin(a) * 0.12, 0]), add3(c, [Math.cos(a) * 0.3, Math.sin(a) * 0.28 - 0.02, -0.06]), 0.07, FL, { s0: 0.6, s1: 0.6 });
    }
    K.tuft([0, 0.24, 0.08], [0.04, 0.36, 0.14], 0.055, CRM, { s0: 1, s1: 1 });
    for (const sx of [-1, 1]) for (const z of [-0.05, -0.2]) K.rc([sx * 0.12, -0.2, z], [sx * 0.2, -0.33, z + 0.03], 0.03, 0.022, 0x4a3426, { k: 0.02, s0: 0.5, s1: 0.5 });
    const cBand = hexRGB(0xa86a20);
    const paint = (v) => {
      if (v.z < -0.3) {
        const band = sst(0.6, 0.85, Math.sin((v.z + 0.3) * 48));
        tintV(v, cBand, band * 0.65 * sst(-0.3, -0.36, v.z) * sst(-0.2, 0.3, v.ny + 0.3));
        v.g = (1 - band * 0.7) * sst(-0.3, -0.38, v.z);
      }
    };
    const face = { mouth: [0, -0.055, 0.3, 0.04], mouthK: 1, line: 0x4a2a10, blush: [0.17, -0.02, 0.2, 0.055], blushCol: 0xff9a7a };
    return { prims: K.prims, bounds: [-0.5, -0.45, -0.75, 0.5, 0.48, 0.45], hipY: 0, height: 1.0, paint, face,
      eyes: [-1, 1].map((sx) => ({ p: [sx * 0.125, 0.04, 0.29], r: 0.095, yaw: sx * 0.32 })) };
  });
  const B = buildCritter(r, { key: 'firefly', design: D, float: 0.9, floatAmp: 0.1, iris: 0x2a1600, iris2: 0xffb84a, lash: 0x2a1808,
    eye: { open: 0.86, wing: 0.5, irisR: 0.64 },
    mat: { kind: 'plush', fur: 0.7, sheenCol: 0xfff2c0, sheen: 0.3, fuzz: 0.08, soft: 0.06, glow: 0xfff0a0, glowAmt: 3.2 } });
  for (const s of [-1, 1]) { const an = grp(B, [s * 0.1, 0.25, 0.1], [0.3, 0, -s * 0.35]); part(GEO.cyl, M(0x3a2c22), an, [0, 0.13, 0], [0.014, 0.26, 0.014]); part(GEO.sphere, E(0xfff3a0, 3), an, [0, 0.28, 0], 0.045); wig(r, an, 'z', 0.15, 3, s); }
  const wingM = toonMat({ color: 0xeaf6ff, transparent: true, opacity: 0.42, side: THREE.DoubleSide, depthWrite: false });
  const veinM = E(0xfff6d8, 1.1, { transparent: true, opacity: 0.6, depthWrite: false });
  for (const s of [-1, 1]) for (const k of [0, 1]) {
    const w = grp(B, [s * 0.12, 0.2 - k * 0.08, -0.14 - k * 0.05], [0, 0, s * (0.35 - k * 0.6)]);
    part(GEO.sphere, wingM, w, [s * 0.3, 0, -0.04], [0.32 - k * 0.08, 0.016, 0.13 - k * 0.02], [0, s * 0.25, 0]);
    part(GEO.cyl, veinM, w, [s * 0.3, 0.01, -0.04], [0.006, 0.6 - k * 0.15, 0.006], [0, s * 0.25, Math.PI / 2]);
    wig(r, w, 'z', 0.45, 22, k * 1.5 + (s > 0 ? 0 : Math.PI));
  }
  const pl = part(GEO.sphere, E(0xfff2a0, 2.0, { transparent: true, opacity: 0.35, depthWrite: false }), B, [0, -0.12, -0.46], [0.27, 0.26, 0.31]);
  r.fns.push((t) => { const k = 1 + Math.sin(t * 3) * 0.08; pl.scale.set(0.27 * k, 0.26 * k, 0.31 * k); });
  r.size = 1.35;
};

// ---------------- 그림냥 : shade cat — ear and cheek tufts, starlit speckles, glowing crescent, slit-pupil lantern eyes
MODELS.geurim = (r) => {
  const D = critter('cat', () => {
    const K = critterKit(), SH = 0x3a2a5c, SD = 0x221838, LT = 0x56437e;
    K.el([0, 0.45, 0], [0.28, 0.25, 0.43], SH, { k: 0.1 });
    K.el([0, 0.4, 0.2], [0.17, 0.18, 0.16], LT, { k: 0.1 });
    K.tuft([0, 0.46, 0.33], [0, 0.32, 0.44], 0.07, LT);
    for (const [sx, sz] of [[-1, 1], [1, 1], [-1, -1], [1, -1]]) {
      const leg = sx * sz > 0 ? 1 : -1;
      const hip = [sx * 0.15, 0.4, sz * 0.24], paw = [sx * 0.16, 0.06, sz * 0.25 + 0.03];
      K.rc(hip, paw, 0.085, 0.058, SH, { k: 0.06, leg });
      K.el([paw[0], 0.045, paw[2] + 0.02], [0.07, 0.045, 0.085], SD, { k: 0.03, leg });
    }
    const hc = [0, 0.86, 0.3];
    K.rc([0, 0.55, 0.25], add3(hc, [0, -0.1, -0.05]), 0.15, 0.14, SH, { k: 0.08, s0: 0.7, s1: 0.95 });
    K.el(hc, [0.32, 0.27, 0.28], SH, Object.assign({ k: 0.08 }, HEAD));
    K.el(add3(hc, [0, -0.1, 0.18]), [0.15, 0.1, 0.12], LT, Object.assign({ k: 0.06 }, HEAD));
    K.el(add3(hc, [0, -0.06, 0.295]), [0.035, 0.024, 0.02], 0x9a6ac8, Object.assign({ k: 0.02 }, HEAD));
    for (const sx of [-1, 1]) {
      K.rc(add3(hc, [sx * 0.15, 0.16, -0.02]), add3(hc, [sx * 0.25, 0.46, -0.04]), 0.115, 0.012, SH, Object.assign({ k: 0.05, jaw: 1 }, HEAD));
      K.tuft(add3(hc, [sx * 0.245, 0.42, -0.04]), add3(hc, [sx * 0.29, 0.58, -0.06]), 0.025, SH, Object.assign({ jaw: 1 }, HEAD));
      K.tuft(add3(hc, [sx * 0.24, -0.06, 0.02]), add3(hc, [sx * 0.43, -0.12, -0.04]), 0.07, SH, Object.assign({}, HEAD));
      K.tuft(add3(hc, [sx * 0.22, -0.13, 0.03]), add3(hc, [sx * 0.37, -0.23, -0.01]), 0.06, SH, Object.assign({}, HEAD));
    }
    const t0 = [0, 0.5, -0.42], t1 = [0, 0.64, -0.64], t2 = [0.05, 0.94, -0.74], t3 = [0.17, 1.16, -0.62], t4 = [0.27, 1.17, -0.48];
    K.rc(t0, t1, 0.08, 0.075, SH, { k: 0.05, s0: 0.32, s1: 0.24 });
    K.rc(t1, t2, 0.075, 0.068, SH, { k: 0.04, s0: 0.24, s1: 0.14 });
    K.rc(t2, t3, 0.068, 0.055, SH, { k: 0.04, s0: 0.14, s1: 0.05 });
    K.rc(t3, t4, 0.055, 0.025, LT, { k: 0.04, s0: 0.05, s1: 0 });
    const hy = hc[1], hz = hc[2];
    const cIn = hexRGB(0x9a64c8), cStar = hexRGB(0xf0e0ff), cSock = hexRGB(0x7a64aa), cBack = hexRGB(0x221838);
    const paint = (v) => {
      const ey = v.y - hy;
      if (ey > 0.16 && v.nz > 0.1 && Math.abs(v.x) > 0.08) tintV(v, cIn, sst(0.1, 0.55, v.nz) * sst(0.2, 0.28, ey) * (1 - sst(0.38, 0.44, ey)) * 0.85);
      if (v.ny > 0.4 && v.y < hy - 0.15) tintV(v, cBack, sst(0.4, 0.9, v.ny) * 0.5);
      if (v.y < 0.1) tintV(v, cSock, sst(0.1, 0.06, v.y) * 0.7);
      // starlight speckles across the coat
      const n = vn3js(v.x * 30 + 5, v.y * 30, v.z * 30 - 3);
      if (n > 0.86 && v.ny > 0.1 && v.y < hy - 0.12) { const s = sst(0.86, 0.92, n) * sst(0.1, 0.5, v.ny); v.g = Math.max(v.g, s); tintV(v, cStar, s * 0.8); }
    };
    const face = {
      mouth: [0, hy - 0.115, hz + 0.24, 0.042], mouthK: 1, line: 0xb89ae8,
      nose: [0.008, hy - 0.05, hz + 0.31, 0.012],
      blush: [0.18, hy - 0.07, hz + 0.1, 0.055], blushCol: 0xb45ac8, hatch: 0.6,
      mark: [0, hy + 0.165, hz + 0.12, 0.05], markK: 2, markCol: 0xffe08a, markGlow: 0xffc84a,
    };
    return { prims: K.prims, bounds: [-0.65, -0.05, -0.95, 0.65, 1.45, 0.75], hipY: 0.4, height: 1.3, stride: 0.12, tip: t4, paint, face,
      earHinge: add3(hc, [0, 0.15, -0.03]), earAmp: -0.2, lidFold: 0.6,
      eyes: eyePair(hc, 0.13, 0.025, 0.24, 0.088, 0.3, { roll: 0.12 }) };
  });
  const B = buildCritter(r, { key: 'cat', design: D, iris: 0xd88a10, iris2: 0xfff07a, lash: 0x0c0614,
    eye: { open: 0.62, tilt: 0.16, wing: 0.7, irisR: 0.95, glow: 1.4, slit: 1 },
    mat: { kind: 'fur', rimL: 0.7, sheenCol: 0xb48cff, sheen: 0.4, fuzz: 0.1, rim: 0xb48cff, rimAmt: 0.24, glow: 0xd8c0ff, glowAmt: 2.4, shadeCol: [0.95, 0.85, 1.25] } });
  const smoke = grp(B, D.tip);
  for (let k = 0; k < 4; k++) part(GEO.sphere, E([0x7a4bd6, 0xa77bff, 0x5b3f8f, 0xc7a6ff][k], 1.2 + k * 0.2, { transparent: true, opacity: 0.55 - k * 0.1, depthWrite: false }), smoke, [Math.sin(k) * 0.05, k * 0.08, -k * 0.03], 0.07 - k * 0.012);
  wig(r, smoke, 'z', 0.3, 2); r.glue(smoke, 0);
  const coll = grp(B, [0, 0.66, 0.24], [1.2, 0, 0]);
  part(GEO.torus, E(0xb48cff, 1.6), coll, [0, 0, 0], [0.18, 0.18, 0.5]);
  part(GEO.octa, E(0xffe08a, 2.4), B, [0, 0.55, 0.42], [0.03, 0.045, 0.02]);
  r.size = 1.3;
};

// ---------------- 솜구름 : cloud lamb — puffy wool with lavender shading, wool bangs, droopy ears, sleepy smile
MODELS.somgu = (r) => {
  const D = critter('lamb', () => {
    const K = critterKit(), W = 0xdcd8ea, LV = 0xcfc2f2, HF = 0x4a4368;
    for (const [x, y, z, s] of [[0, 0.62, 0, 0.4], [0.25, 0.7, 0.1, 0.24], [-0.25, 0.7, 0.1, 0.24], [0.2, 0.85, -0.15, 0.25], [-0.2, 0.85, -0.15, 0.25], [0, 0.96, 0.02, 0.26], [0.3, 0.52, -0.2, 0.21], [-0.3, 0.52, -0.2, 0.21], [0, 0.6, -0.35, 0.25], [0, 0.84, 0.22, 0.2], [0.18, 0.5, 0.2, 0.2], [-0.18, 0.5, 0.2, 0.2], [0.36, 0.72, -0.08, 0.17], [-0.36, 0.72, -0.08, 0.17], [0, 0.42, -0.1, 0.24]]) K.el([x, y, z], [s, s, s], W, { k: 0.05 });
    for (const [sx, sz] of [[-1, 1], [1, 1], [-1, -1], [1, -1]]) {
      const leg = sx * sz > 0 ? 1 : -1;
      K.rc([sx * 0.17, 0.32, sz * 0.18], [sx * 0.18, 0.05, sz * 0.19], 0.065, 0.055, HF, { k: 0.04, leg });
      K.el([sx * 0.18, 0.04, sz * 0.19 + 0.01], [0.062, 0.04, 0.07], 0x2e2844, { k: 0.02, leg });
    }
    const hc = [0, 0.66, 0.43];
    K.el(hc, [0.23, 0.21, 0.19], LV, Object.assign({ k: 0.07 }, HEAD));
    K.el(add3(hc, [0, -0.07, 0.12]), [0.12, 0.09, 0.1], 0xdcd2f8, Object.assign({ k: 0.06 }, HEAD));
    for (const [x, y, z, s] of [[0, 0.17, 0.02, 0.1], [0.1, 0.15, 0.0, 0.085], [-0.1, 0.15, 0.0, 0.085], [0.05, 0.19, -0.06, 0.08], [-0.06, 0.19, -0.06, 0.08]]) K.el(add3(hc, [x, y, z]), [s, s, s], W, Object.assign({ k: 0.04 }, HEAD));
    for (const sx of [-1, 1]) K.rc(add3(hc, [sx * 0.17, 0.03, -0.03]), add3(hc, [sx * 0.34, -0.06, -0.02]), 0.06, 0.035, LV, Object.assign({ k: 0.04, jaw: 1 }, HEAD));
    const cShade = hexRGB(0xc4b8ea), cPink = hexRGB(0xf6c8e0), cHoof = hexRGB(0x7a70a0);
    const paint = (v) => {
      // wool: lavender in the crevices (approximated by low-frequency noise and underside), soft pink sunrise on top
      if (v.y > 0.25 && Math.abs(v.x) + Math.abs(v.z - 0.43) > 0.1) {
        const n = vn3js(v.x * 9, v.y * 9 + 2, v.z * 9);
        tintV(v, cShade, sst(0.5, 0.25, n) * 0.35 + sst(0.0, -0.7, v.ny) * 0.45);
        if (v.ny > 0.5) tintV(v, cPink, sst(0.5, 0.95, v.ny) * 0.18);
      }
      if (v.y < 0.32 && v.y > 0.1) tintV(v, cHoof, sst(0.32, 0.12, v.y) * 0.3);
    };
    const face = { mouth: [0, hc[1] - 0.105, hc[2] + 0.17, 0.035], mouthK: 2, line: 0x4a3070, nose: [0.008, hc[1] - 0.06, hc[2] + 0.215, 0.012],
      blush: [0.14, hc[1] - 0.05, hc[2] + 0.08, 0.05], blushCol: 0xff9ac0 };
    return { prims: K.prims, bounds: [-0.7, -0.05, -0.72, 0.7, 1.32, 0.78], hipY: 0.32, height: 1.3, stride: 0.08, hc, paint, face,
      earHinge: add3(hc, [0, 0.03, -0.03]), earAmp: 0.35,
      eyes: eyePair(hc, 0.092, 0.02, 0.158, 0.074, 0.34) };
  });
  const B = buildCritter(r, { key: 'lamb', design: D, iris: 0x2a1c56, iris2: 0xa08cff, lash: 0x2a1840,
    eye: { open: 0.66, tilt: -0.04, wing: 0.25, irisR: 0.63 },
    mat: { kind: 'wool', rough: 0.85, sheen: 0.3, sheenCol: 0xfff4ff, coat: 0, fuzz: 0.08, soft: 0.04, env: 0.26 } });
  const horn = new THREE.TorusGeometry(0.1, 0.035, 8, 18, Math.PI * 1.35);
  for (const s of [-1, 1]) { const h = part(horn, M(0xe6c27a), B, add3(D.hc, [s * 0.2, 0.13, -0.05]), 1, [0, s * 1.3, s > 0 ? 0.5 : 2.6]); r.glue(h, 1); }
  r.size = 1.35;
};

// ---------------- 버섯콩 : mushroom sprite — spotted cap with gills, stubby arms, rosy face
MODELS.beoseot = (r) => {
  const D = critter('shroom', () => {
    const K = critterKit(), RD = 0xe63c52, CR = 0xf8ead2;
    // cap first, carve its underside, then the stem so the carve can't cut through it
    K.el([0, 0.7, 0], [0.62, 0.42, 0.62], RD, { k: 0.06, s0: 0.9, s1: 0.9 });
    K.sub([0, 0.49, 0], [0.68, 0.2, 0.68], 0.05);
    K.el([0, 0.66, 0], [0.5, 0.035, 0.5], 0xf2d6b0, { k: 0.04 });
    K.el([0, 0.37, 0.01], [0.3, 0.36, 0.28], CR, { k: 0.08 });
    for (const [a, ph, s] of [[0, 0.95, 1], [0.9, 0.55, 1.1], [2.1, 0.6, 0.9], [3.3, 0.5, 1.2], [4.4, 0.62, 1], [5.4, 0.55, 0.85], [1.5, 1.05, 0.8], [3.9, 1.0, 0.9], [2.7, 1.1, 0.7], [5.9, 1.05, 0.75], [0.3, 0.25, 1.0]]) K.el([Math.cos(a) * Math.sin(ph) * 0.6, 0.7 + Math.cos(ph) * 0.42, Math.sin(a) * Math.sin(ph) * 0.6], [0.085 * s, 0.045, 0.085 * s], 0xfff8ee, { k: 0.02, s0: 0.9, s1: 0.9 });
    for (const sx of [-1, 1]) {
      K.el([sx * 0.13, 0.06, 0.05], [0.1, 0.07, 0.13], 0xd9b98f, { k: 0.05, leg: sx });
      K.rc([sx * 0.24, 0.36, 0.02], [sx * 0.36, 0.26, 0.08], 0.06, 0.05, CR, { k: 0.05 });
    }
    const cGill = hexRGB(0xe8c89a), cGill2 = hexRGB(0xc89a70), cTop = hexRGB(0xff6070), cStem = hexRGB(0xe8d0b0);
    const paint = (v) => {
      // gills under the cap
      if (v.ny < -0.35 && v.y > 0.47 && v.y < 0.74 && Math.hypot(v.x, v.z) > 0.3) {
        const ang = Math.atan2(v.z, v.x);
        tintV(v, cGill, 0.85); tintV(v, cGill2, sst(0.5, 0.9, Math.sin(ang * 46)) * 0.7);
      }
      // cap: brighter crown, darker rim
      if (v.y > 0.72 && v.ny > 0.2) tintV(v, cTop, sst(0.3, 0.95, v.ny) * 0.25);
      if (v.y < 0.3 && v.ny < 0) tintV(v, cStem, 0.4);
    };
    const face = { mouth: [0, 0.3, 0.24, 0.048], mouthK: 3, line: 0x3a1a10, blush: [0.17, 0.33, 0.18, 0.058], blushCol: 0xff7a8a };
    return { prims: K.prims, bounds: [-0.78, -0.05, -0.78, 0.78, 1.2, 0.78], hipY: 0.2, height: 1.2, stride: 0.07, paint, face,
      eyes: [-1, 1].map((sx) => ({ p: [sx * 0.112, 0.4, 0.262], r: 0.08, yaw: sx * 0.3, pitch: -0.12 })) };
  });
  buildCritter(r, { key: 'shroom', design: D, iris: 0x3a1010, iris2: 0xff8a6a, lash: 0x2a1008, sway: 0.2,
    eye: { open: 0.86, wing: 0.4, irisR: 0.64 },
    mat: { kind: 'skin', rough: 0.5, coat: 0.5, coatRough: 0.3, sheen: 0.3, soft: 0.05 } });
  r.size = 1.2;
};

// ---------------- 별씨 : starseed plush — cream heart, gold glowing tips, rosy cheeks, halo
MODELS.byeolssi = (r) => {
  const D = critter('star', () => {
    const K = critterKit();
    K.el([0, 0, 0], [0.31, 0.31, 0.27], 0xfff3d0, { k: 0.1, s0: 1, s1: 1 });
    for (let i = 0; i < 5; i++) { const a = (i / 5) * Math.PI * 2 + Math.PI / 2; K.rc([0, 0, -0.02], [Math.cos(a) * 0.6, Math.sin(a) * 0.6, -0.04], 0.21, 0.065, 0xffe08a, { k: 0.12, s0: 1, s1: 1 }); }
    const cIn = hexRGB(0xfff8e6), cTip = hexRGB(0xffb83a), cGlow = hexRGB(0xfff0b0);
    const paint = (v) => {
      const rr = Math.hypot(v.x, v.y);
      tintV(v, cIn, sst(0.3, 0.1, rr) * 0.6);
      tintV(v, cTip, sst(0.32, 0.58, rr) * 0.7);
      v.g = sst(0.45, 0.62, rr) * 0.85; tintV(v, cGlow, v.g * 0.4);
      // a soft seam ridge highlight
      if (v.nz < 0.2 && v.nz > -0.2) tintV(v, cGlow, 0.15);
    };
    const face = { mouth: [0, -0.07, 0.2, 0.04], mouthK: 1, line: 0x5a3008, blush: [0.17, -0.03, 0.15, 0.055], blushCol: 0xff8a7a };
    return { prims: K.prims, bounds: [-0.78, -0.78, -0.42, 0.78, 0.78, 0.42], hipY: 0, height: 1.2, paint, face,
      eyes: [-1, 1].map((sx) => ({ p: [sx * 0.11, 0.045, 0.24], r: 0.074, yaw: sx * 0.3 })) };
  });
  const B = buildCritter(r, { key: 'star', design: D, float: 1.05, floatAmp: 0.12, iris: 0x4a2600, iris2: 0xffc04a, lash: 0x3a2008,
    eye: { open: 0.84, wing: 0.5, irisR: 0.64 },
    mat: { kind: 'plush', sheenCol: 0xfff0b0, soft: 0.08, rim: 0xffe08a, rimAmt: 0.2, glow: 0xffd070, glowAmt: 2.0 } });
  const halo = part(GEO.torus, E(0xffe08a, 2.4), B, [0, 0.64, 0], 0.2, [Math.PI / 2, 0, 0]);
  const tw = [];
  for (let i = 0; i < 3; i++) tw.push(part(GEO.octa, E(0xfff4c0, 2.6), B, [Math.cos(i * 2.1) * 0.75, Math.sin(i * 2.1) * 0.75, 0.1], [0.03, 0.06, 0.03]));
  r.fns.push((t) => {
    halo.position.y = 0.64 + Math.sin(t * 3) * 0.03; B.rotation.z = Math.sin(t * 0.8) * 0.15;
    tw.forEach((s, i) => { const k = Math.sin(t * 2.2 + i * 2.1); s.visible = k > 0.08; if (s.visible) s.scale.set(0.03 * k, 0.07 * k, 0.03 * k); });
  });
  r.size = 1.6;
};
