// GLSL of the post pipeline (see index.js for the pass order). Fullscreen passes draw one big triangle.
// Tier-dependent loop counts are compile-time defines, so each pass compiles exactly one program per tier (prewarmed).

export const VERT = /* glsl */ `
varying vec2 vUv;
void main() { vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }`;

/** Composite vertex shader: also interpolates the world-space view ray (view-space z = -1 -> length = 1/cos). */
export const VERT_RAY = /* glsl */ `
uniform vec3 uRay00, uRay10, uRay01;
varying vec2 vUv;
varying vec3 vRay;
void main() {
  vUv = uv;
  vRay = uRay00 + (uRay10 - uRay00) * uv.x + (uRay01 - uRay00) * uv.y;
  gl_Position = vec4(position.xy, 0.0, 1.0);
}`;

const COMMON = /* glsl */ `
float hash12(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
// interleaved gradient noise: well-distributed per-pixel rotation for sparse kernels (the blur that follows hides it)
float ign(vec2 p) { return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715)))); }
float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }
`;

const TAPS13 = /* glsl */ `
  vec3 a = S(vUv + uTexel * vec2(-2.0,  2.0));
  vec3 b = S(vUv + uTexel * vec2( 0.0,  2.0));
  vec3 c = S(vUv + uTexel * vec2( 2.0,  2.0));
  vec3 d = S(vUv + uTexel * vec2(-2.0,  0.0));
  vec3 e = S(vUv);
  vec3 f = S(vUv + uTexel * vec2( 2.0,  0.0));
  vec3 g = S(vUv + uTexel * vec2(-2.0, -2.0));
  vec3 h = S(vUv + uTexel * vec2( 0.0, -2.0));
  vec3 i = S(vUv + uTexel * vec2( 2.0, -2.0));
  vec3 j = S(vUv + uTexel * vec2(-1.0,  1.0));
  vec3 k = S(vUv + uTexel * vec2( 1.0,  1.0));
  vec3 l = S(vUv + uTexel * vec2(-1.0, -1.0));
  vec3 m = S(vUv + uTexel * vec2( 1.0, -1.0));`;

export const PREFILTER = /* glsl */ `
precision highp float;
uniform sampler2D tSrc; uniform vec2 uTexel; uniform float uThreshold; uniform float uKnee;
varying vec2 vUv;
vec3 S(vec2 uv) { return min(texture2D(tSrc, uv).rgb, vec3(48.0)); }
float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }
vec3 thresh(vec3 c) {
  float br = max(c.r, max(c.g, c.b));
  float soft = clamp(br - uThreshold + uKnee, 0.0, 2.0 * uKnee);
  soft = soft * soft / (4.0 * uKnee + 1e-4);
  return c * (max(soft, br - uThreshold) / max(br, 1e-4));
}
void main() {
  ${TAPS13}
  // Karis-weighted groups kill single-pixel fireflies
  vec3 g0 = (a + b + d + e) * 0.25, g1 = (b + c + e + f) * 0.25, g2 = (d + e + g + h) * 0.25, g3 = (e + f + h + i) * 0.25, g4 = (j + k + l + m) * 0.25;
  float w0 = 0.125 / (1.0 + luma(g0)), w1 = 0.125 / (1.0 + luma(g1)), w2 = 0.125 / (1.0 + luma(g2)), w3 = 0.125 / (1.0 + luma(g3)), w4 = 0.5 / (1.0 + luma(g4));
  vec3 col = (g0 * w0 + g1 * w1 + g2 * w2 + g3 * w3 + g4 * w4) / (w0 + w1 + w2 + w3 + w4);
  gl_FragColor = vec4(thresh(max(col, vec3(0.0))), 1.0);
}`;

export const DOWN = /* glsl */ `
precision highp float;
uniform sampler2D tSrc; uniform vec2 uTexel;
varying vec2 vUv;
vec3 S(vec2 uv) { return texture2D(tSrc, uv).rgb; }
void main() {
  ${TAPS13}
  vec3 col = e * 0.125 + (a + c + g + i) * 0.03125 + (b + d + f + h) * 0.0625 + (j + k + l + m) * 0.125;
  gl_FragColor = vec4(col, 1.0);
}`;

export const UP = /* glsl */ `
precision highp float;
uniform sampler2D tSrc; uniform vec2 uTexel; uniform float uRadius; uniform float uWeight;
varying vec2 vUv;
void main() {
  vec2 o = uTexel * uRadius;
  vec3 col = texture2D(tSrc, vUv).rgb * 4.0;
  col += (texture2D(tSrc, vUv + vec2(-o.x, 0.0)).rgb + texture2D(tSrc, vUv + vec2(o.x, 0.0)).rgb + texture2D(tSrc, vUv + vec2(0.0, -o.y)).rgb + texture2D(tSrc, vUv + vec2(0.0, o.y)).rgb) * 2.0;
  col += texture2D(tSrc, vUv + vec2(-o.x, -o.y)).rgb + texture2D(tSrc, vUv + vec2(o.x, -o.y)).rgb + texture2D(tSrc, vUv + vec2(-o.x, o.y)).rgb + texture2D(tSrc, vUv + vec2(o.x, o.y)).rgb;
  gl_FragColor = vec4(col * (uWeight / 16.0), 1.0);
}`;

/** Full-res hardware depth -> half-res linear view depth (metres, R16F). Keeps the nearest of the 2x2 footprint. */
export const DEPTH_DOWN = /* glsl */ `
precision highp float;
uniform highp sampler2D tDepth; uniform vec2 uTexel; uniform vec2 uNearFar;
varying vec2 vUv;
float lin(float d) { return uNearFar.x * uNearFar.y / (uNearFar.y - d * (uNearFar.y - uNearFar.x)); }
void main() {
  vec2 o = uTexel * 0.5;
  float d = min(min(texture2D(tDepth, vUv + vec2(-o.x, -o.y)).r, texture2D(tDepth, vUv + vec2(o.x, -o.y)).r),
                min(texture2D(tDepth, vUv + vec2(-o.x, o.y)).r, texture2D(tDepth, vUv + vec2(o.x, o.y)).r));
  gl_FragColor = vec4(lin(d), 0.0, 0.0, 1.0);
}`;

/**
 * Half-res ambient occlusion (Alchemy-style obscurance on a golden-angle spiral, per-pixel rotation), normals rebuilt
 * from the depth neighbours with the smaller step (no smearing across silhouettes). Out: r = AO, g = linear depth.
 */
export const AO = /* glsl */ `
precision highp float;
${COMMON}
uniform sampler2D tDepthH; uniform vec2 uTexel; uniform vec2 uRes;
uniform vec4 uProj;        // P[0], P[5], P[8], P[9] of the camera projection
uniform vec4 uAo;          // radius (m), intensity, bias (m per m of depth), max radius (px)
uniform float uFadeFar;    // m: AO fades out toward this distance
varying vec2 vUv;
float Z(vec2 uv) { return texture2D(tDepthH, uv).r; }
vec3 viewPos(vec2 uv, float z) { vec2 n = uv * 2.0 - 1.0; return vec3((n.x + uProj.z) * z / uProj.x, (n.y + uProj.w) * z / uProj.y, -z); }
void main() {
  float z = Z(vUv);
  if (z > uFadeFar) { gl_FragColor = vec4(1.0, z, 0.0, 1.0); return; }
  vec3 P = viewPos(vUv, z);
  vec2 dx = vec2(uTexel.x, 0.0), dy = vec2(0.0, uTexel.y);
  float zr = Z(vUv + dx), zl = Z(vUv - dx), zu = Z(vUv + dy), zd = Z(vUv - dy);
  vec3 ex = abs(zr - z) < abs(zl - z) ? viewPos(vUv + dx, zr) - P : P - viewPos(vUv - dx, zl);
  vec3 ey = abs(zu - z) < abs(zd - z) ? viewPos(vUv + dy, zu) - P : P - viewPos(vUv - dy, zd);
  vec3 N = normalize(cross(ex, ey));
  float rad = uAo.x;
  float rPx = min(rad * uProj.y * 0.5 * uRes.y / z, uAo.w);
  if (rPx < 1.5) { gl_FragColor = vec4(1.0, z, 0.0, 1.0); return; }
  float a = ign(gl_FragCoord.xy) * 6.2831853;
  vec2 v = vec2(cos(a), sin(a));
  const mat2 GOLD = mat2(-0.7373688, 0.6754903, -0.6754903, -0.7373688);
  float sum = 0.0;
  float r2 = rad * rad;
  for (int i = 0; i < AO_N; i++) {
    float t = (float(i) + 0.5) / float(AO_N);
    vec2 suv = vUv + v * (sqrt(t) * rPx) * uTexel;
    v = GOLD * v;
    vec3 S = viewPos(suv, Z(suv)) - P;
    float vv = dot(S, S);
    float vn = dot(S, N);
    sum += max(vn - uAo.z * z, 0.0) / (vv + 0.1 * r2) * max(0.0, 1.0 - vv / (4.0 * r2));
  }
  float ao = clamp(1.0 - uAo.y * rad * sum * (2.0 / float(AO_N)), 0.0, 1.0);
  ao = mix(ao, 1.0, smoothstep(uFadeFar * 0.55, uFadeFar, z));
  gl_FragColor = vec4(ao, z, 0.0, 1.0);
}`;

/** Separable depth-aware blur of the AO buffer (r = AO, g = depth). uDir = texel * axis. */
export const AO_BLUR = /* glsl */ `
precision highp float;
uniform sampler2D tSrc; uniform vec2 uDir;
varying vec2 vUv;
void main() {
  vec2 c = texture2D(tSrc, vUv).rg;
  float k = 1.0 / (c.g * 0.035 + 0.02);
  float acc = c.r, ws = 1.0;
  for (int i = 1; i <= AO_BLUR_R; i++) {
    float g = exp(-float(i * i) / float(AO_BLUR_R * AO_BLUR_R));
    vec2 s0 = texture2D(tSrc, vUv + uDir * float(i)).rg, s1 = texture2D(tSrc, vUv - uDir * float(i)).rg;
    float w0 = g * max(0.0, 1.0 - abs(s0.g - c.g) * k), w1 = g * max(0.0, 1.0 - abs(s1.g - c.g) * k);
    acc += s0.r * w0 + s1.r * w1; ws += w0 + w1;
  }
  gl_FragColor = vec4(acc / ws, c.g, 0.0, 1.0);
}`;

/**
 * Light-shaft source mask at quarter res: far / sky pixels brighter than the threshold near the sun, plus a soft
 * synthetic glow so a dark (eclipsed) disc still radiates; anything near (fighters, ruins) occludes.
 */
export const SHAFT_MASK = /* glsl */ `
precision highp float;
uniform sampler2D tScene, tDepthH;
uniform vec2 uSunUv; uniform float uAspect;
uniform vec4 uShaftP;   // threshold, radius (uv, aspect-corrected), sky depth start (m), synthetic glow
uniform vec3 uSunCol;
varying vec2 vUv;
void main() {
  float z = texture2D(tDepthH, vUv).r;
  float sky = smoothstep(uShaftP.z, uShaftP.z * 2.0, z);
  vec2 d = (vUv - uSunUv) * vec2(uAspect, 1.0);
  float r = length(d) / uShaftP.y;
  float fall = max(0.0, 1.0 - r);
  fall *= fall;
  vec3 c = max(texture2D(tScene, vUv).rgb, vec3(0.0));
  float br = max(c.r, max(c.g, c.b));
  vec3 m = c * (max(br - uShaftP.x, 0.0) / max(br, 1e-3));
  m = min(m, vec3(6.0)) + uSunCol * uShaftP.w * fall * fall;
  gl_FragColor = vec4(m * sky * fall, 1.0);
}`;

/** Radial blur toward the sun (one pass of the light-shaft chain), jittered start, exponential decay. */
export const SHAFT_BLUR = /* glsl */ `
precision highp float;
${COMMON}
uniform sampler2D tSrc; uniform vec2 uSunUv; uniform float uLength; uniform float uDecay;
varying vec2 vUv;
void main() {
  vec2 delta = (uSunUv - vUv) * (uLength / float(SHAFT_N));
  vec2 uv = vUv + delta * ign(gl_FragCoord.xy);
  vec3 acc = vec3(0.0);
  float w = 1.0, ws = 0.0;
  for (int i = 0; i < SHAFT_N; i++) {
    acc += texture2D(tSrc, uv).rgb * w;
    ws += w; w *= uDecay; uv += delta;
  }
  gl_FragColor = vec4(acc / ws, 1.0);
}`;

/** DOF prep at half res: colour (2x2 box via bilinear) + signed circle of confusion in half-res px (far +, near -). */
export const DOF_PREP = /* glsl */ `
precision highp float;
uniform sampler2D tScene, tDepthH;
uniform vec4 uDof;      // focus (m), in-focus half range (m), max CoC (half-res px) * aperture, near-blur scale
varying vec2 vUv;
float coc(float z) {
  float far = max(0.0, 1.0 - (uDof.x + uDof.y) / z);
  float near = max(0.0, (uDof.x - uDof.y) / max(z, 0.05) - 1.0) * uDof.w;
  return uDof.z * (far - min(near, 1.0));
}
void main() {
  vec3 c = min(texture2D(tScene, vUv).rgb, vec3(32.0));
  gl_FragColor = vec4(c, coc(texture2D(tDepthH, vUv).r));
}`;

/**
 * Bokeh gather (single pass, golden-angle spiral; each tap contributes if its own CoC covers the distance, taps behind
 * the centre are limited to twice the centre's CoC). Out: rgb blurred, a = max(|centre CoC|, near-field coverage).
 */
export const DOF_GATHER = /* glsl */ `
precision highp float;
uniform sampler2D tSrc; uniform vec2 uTexel; uniform float uMaxR;
varying vec2 vUv;
void main() {
  vec4 c0 = texture2D(tSrc, vUv);
  float cs = abs(c0.a);
  vec3 col = c0.rgb;
  float tot = 1.0, nearCov = 0.0;
  vec2 v = vec2(1.0, 0.0);
  const mat2 GOLD = mat2(-0.7373688, 0.6754903, -0.6754903, -0.7373688);
  for (int i = 0; i < DOF_N; i++) {
    float rad = sqrt((float(i) + 0.5) / float(DOF_N)) * uMaxR;
    vec4 s = texture2D(tSrc, vUv + v * rad * uTexel);
    v = GOLD * v;
    float ss = abs(s.a);
    if (s.a > c0.a) ss = min(ss, cs * 2.0);
    float m = smoothstep(rad - 0.5, rad + 0.5, ss);
    col += mix(col / tot, s.rgb, m);
    tot += 1.0;
    nearCov += m * step(s.a, -1.0);
  }
  gl_FragColor = vec4(col / tot, max(cs, nearCov / float(DOF_N) * uMaxR * 2.0));
}`;

/**
 * Composite: distortion / radial blur / chroma -> DOF -> AO -> height fog + in-scattering (sun lobe, point lights)
 * -> light shafts -> bloom -> exposure / tint / lift -> ACES -> sRGB -> grade (lift / gamma / gain, split toning,
 * saturation, contrast) -> impact frame (mono / invert) -> flash -> vignette -> grain + dither -> letterbox.
 */
export const COMPOSITE = /* glsl */ `
precision highp float;
${COMMON}
uniform sampler2D tScene; uniform sampler2D tBloom; uniform sampler2D tDist;
uniform vec2 uRes; uniform float uTime;
uniform float uBloom, uExposure, uChroma, uRadial, uVignette, uGrain, uSat, uContrast, uInvert, uMono, uLetterbox, uDist, uFlash, uUseDist, uHdr;
uniform vec2 uRadialCenter; uniform vec3 uTint, uLift, uFlashColor;
uniform vec2 uSceneTexel; uniform float uSharpen;
uniform vec3 uGLift, uGGamma, uGGain, uToneSh, uToneHi; uniform vec2 uTone;
#ifdef HAS_DEPTH
uniform highp sampler2D tDepth;
uniform vec2 uNearFar; uniform vec3 uCamPos;
uniform float uDebug;
#endif
#ifdef HAS_AO
uniform sampler2D tAO; uniform float uAoStr;
#endif
#ifdef HAS_FOG
uniform vec4 uFogA;      // density at the floor (1/m), height falloff (1/m), distance haze (1/m), max opacity
uniform vec4 uFogB;      // floor y, start distance, max distance, sky distance
uniform vec3 uFogCol;    // ambient in-scatter (linear HDR)
uniform vec3 uSunDir; uniform vec3 uSunCol; uniform float uSunG;
uniform float uFogOn, uFogSky;
#if FOG_LIGHTS > 0
uniform vec4 uFL[FOG_LIGHTS];   // xyz world pos, w core radius (m)
uniform vec3 uFLc[FOG_LIGHTS];  // colour * intensity (cd) * scale
#endif
#endif
#ifdef HAS_SHAFTS
uniform sampler2D tShaft; uniform vec3 uShaftTint; uniform float uShaftOn;
#endif
#ifdef HAS_DOF
uniform sampler2D tDof; uniform vec4 uDof; uniform float uDofOn;
#endif
varying vec2 vUv;
varying vec3 vRay;

vec3 RRTAndODTFit(vec3 v) { vec3 a = v * (v + 0.0245786) - 0.000090537; vec3 b = v * (0.983729 * v + 0.4329510) + 0.238081; return a / b; }
vec3 ACESFilmic(vec3 color) {
  const mat3 ACESInputMat = mat3(vec3(0.59719, 0.07600, 0.02840), vec3(0.35458, 0.90834, 0.13383), vec3(0.04823, 0.01566, 0.83777));
  const mat3 ACESOutputMat = mat3(vec3(1.60475, -0.10208, -0.00327), vec3(-0.53108, 1.10813, -0.07276), vec3(-0.07367, -0.00605, 1.07602));
  color *= 1.0 / 0.6;
  color = ACESInputMat * color; color = RRTAndODTFit(color); color = ACESOutputMat * color;
  return clamp(color, 0.0, 1.0);
}
vec3 lin2srgb(vec3 c) { return mix(c * 12.92, 1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c)); }

void main() {
  vec2 uv = vUv;
  if (uUseDist > 0.5) uv += texture2D(tDist, uv).rg * uDist;
  vec3 col;
  if (uRadial > 0.001) {
    vec2 toC = uv - uRadialCenter;
    float jitter = hash12(vUv * uRes + uTime * 61.0);
    float wsum = 0.0; col = vec3(0.0);
    for (int n = 0; n < 10; n++) {
      float f = (float(n) + jitter) / 10.0;
      float w = 1.0 - f * 0.6;
      col += texture2D(tScene, uRadialCenter + toC * (1.0 - uRadial * 0.35 * f)).rgb * w; wsum += w;
    }
    col /= wsum;
  } else {
    col = texture2D(tScene, uv).rgb;
    if (uSharpen > 0.001) {
      // contrast-adaptive sharpening (after the dynamic-resolution upscale): clamped to the cross neighbourhood
      vec3 n0 = texture2D(tScene, uv + vec2(uSceneTexel.x, 0.0)).rgb, n1 = texture2D(tScene, uv - vec2(uSceneTexel.x, 0.0)).rgb;
      vec3 n2 = texture2D(tScene, uv + vec2(0.0, uSceneTexel.y)).rgb, n3 = texture2D(tScene, uv - vec2(0.0, uSceneTexel.y)).rgb;
      vec3 mn = min(min(n0, n1), min(min(n2, n3), col)), mx = max(max(n0, n1), max(max(n2, n3), col));
      float l = luma(col), amp = clamp(1.0 - (luma(mx) - luma(mn)) / max(luma(mx), 1e-3), 0.0, 1.0);
      col = clamp(col + (col * 4.0 - n0 - n1 - n2 - n3) * (0.25 * uSharpen * amp), mn, mx);
    }
  }
  if (uChroma > 0.001) {
    vec2 c = uv - 0.5;
    vec2 off = c * uChroma * 0.03 * (0.3 + length(c));
    col.r = mix(col.r, texture2D(tScene, uv + off).r, 0.85);
    col.b = mix(col.b, texture2D(tScene, uv - off).b, 0.85);
  }
  // bright pixels are emitters / VFX: AO and fog extinction leave them alone
  float emit = smoothstep(0.7, 2.2, max(col.r, max(col.g, col.b)));

#ifdef HAS_DEPTH
  float dRaw = texture2D(tDepth, vUv).r;
  bool sky = dRaw >= 0.99999;
  float z = uNearFar.x * uNearFar.y / (uNearFar.y - dRaw * (uNearFar.y - uNearFar.x));
#endif

#ifdef HAS_DOF
  if (uDofOn > 0.5) {
    vec4 db = texture2D(tDof, vUv);
    float cf = abs(uDof.z * (max(0.0, 1.0 - (uDof.x + uDof.y) / z) - min(max(0.0, (uDof.x - uDof.y) / max(z, 0.05) - 1.0) * uDof.w, 1.0)));
    float m = smoothstep(0.4, 1.6, max(cf, db.a * step(cf, 0.4)));
    col = mix(col, db.rgb, m);
  }
#endif

#ifdef HAS_AO
  vec2 ao = texture2D(tAO, vUv).rg;
  float aw = exp(-abs(ao.g - z) / (0.04 * z + 0.02));
  col *= mix(1.0, ao.r, uAoStr * aw * (1.0 - emit));
#endif

#ifdef HAS_FOG
  if (uFogOn > 0.5) {
    vec3 dir = normalize(vRay);
    float L = sky ? uFogB.w : z * length(vRay);
    L = min(L, uFogB.z);
    float Ls = max(L - uFogB.y, 0.0);
    float h0 = max(uCamPos.y - uFogB.x, 0.0);
    float h1 = max(uCamPos.y + dir.y * L - uFogB.x, 0.0);
    float dh = h1 - h0;
    float e0 = exp(-uFogA.y * h0);
    float avg = abs(dh) < 1e-3 ? e0 : (e0 - exp(-uFogA.y * h1)) / (uFogA.y * dh);
    float od = (uFogA.x * avg + uFogA.z) * Ls;
    float op = min(1.0 - exp(-od), uFogA.w) * (sky ? uFogSky : 1.0);
    float mu = dot(dir, uSunDir);
    float g = uSunG;
    float phase = (1.0 - g * g) / pow(max(1.0 + g * g - 2.0 * g * mu, 1e-4), 1.5);
    vec3 ins = uFogCol + uSunCol * phase;
    col = col * (1.0 - op * (1.0 - emit)) + ins * op;
#if FOG_LIGHTS > 0
    // single scattering from point lights, closed form along the (unattenuated) view segment
    vec3 add = vec3(0.0);
    for (int i = 0; i < FOG_LIGHTS; i++) {
      vec3 lp = uFL[i].xyz - uCamPos;
      float b = dot(lp, dir);
      float hh = sqrt(max(dot(lp, lp) - b * b, 0.0) + uFL[i].w * uFL[i].w);
      float sc = (atan((L - b) / hh) + atan(b / hh)) / hh;
      float dens = uFogA.x * exp(-uFogA.y * max(uFL[i].y - uFogB.x, 0.0)) + uFogA.z;
      add += uFLc[i] * (sc * dens);
    }
    col += add * 0.0795775;
#endif
  }
#endif

#ifdef HAS_SHAFTS
  if (uShaftOn > 0.5) col += texture2D(tShaft, vUv).rgb * uShaftTint * mix(0.4, 1.0, smoothstep(3.0, 14.0, z));
#endif

  vec3 bloom = texture2D(tBloom, uv).rgb;
  if (uChroma > 0.001) {
    vec2 c = uv - 0.5;
    vec2 off = c * uChroma * 0.045 * (0.3 + length(c));
    bloom.r = texture2D(tBloom, uv + off).r;
    bloom.b = texture2D(tBloom, uv - off).b;
  }
  col += bloom * uBloom;
  col *= uExposure;
  col = col * uTint + uLift;
  if (uHdr > 0.5) col = ACESFilmic(col); else col = clamp(col, 0.0, 1.0);
  col = lin2srgb(col);

  // ---- grade (display-referred): lift / gamma / gain, split toning, saturation, contrast ----------------------------
  col = max(col * uGGain + uGLift * (1.0 - col), 0.0);
  col = pow(col, 1.0 / max(uGGamma, vec3(0.05)));
  float l = luma(col);
  float bal = 0.42 + 0.2 * uTone.y;
  float wS = smoothstep(0.0, 0.12, l) * (1.0 - smoothstep(0.06, bal, l));
  float wH = smoothstep(bal, 0.95, l);
  col += ((uToneSh - luma(uToneSh)) * wS + (uToneHi - luma(uToneHi)) * wH) * uTone.x;
  l = luma(col);
  col = mix(vec3(l), col, uSat);
  col = (col - 0.5) * uContrast + 0.5;

  if (uMono > 0.001) col = mix(col, vec3(smoothstep(0.28, 0.52, l)), uMono);
  if (uInvert > 0.001) col = mix(col, 1.0 - col, uInvert);
  col = mix(col, uFlashColor, clamp(uFlash, 0.0, 1.0));
  vec2 vc = vUv - 0.5;
  col *= 1.0 - uVignette * smoothstep(0.3, 0.95, length(vc) * 1.3);
  vec2 fc = vUv * uRes;
  col += (hash12(fc + fract(uTime) * 517.0) - 0.5) * uGrain;
  // triangular dither (+-1 LSB): no banding in the fog and the dark gradients
  col += (hash12(fc + 71.3) + hash12(fc.yx + 13.7) - 1.0) / 255.0;
  if (uLetterbox > 0.001) {
    float bar = uLetterbox * 0.115;
    col *= smoothstep(bar - 0.0015, bar + 0.0015, min(vUv.y, 1.0 - vUv.y));
  }
#ifdef HAS_DEPTH
  // debug views (post.debugView): 1 AO, 2 linear depth, 3 light shafts, 4 DOF blur mix
  if (uDebug > 0.5) {
    if (uDebug < 1.5) {
#ifdef HAS_AO
      col = vec3(texture2D(tAO, vUv).r);
#endif
    } else if (uDebug < 2.5) col = vec3(pow(clamp(z / 60.0, 0.0, 1.0), 0.5));
    else if (uDebug < 3.5) {
#ifdef HAS_SHAFTS
      col = lin2srgb(clamp(texture2D(tShaft, vUv).rgb * uShaftTint, 0.0, 1.0));
#endif
    } else {
#ifdef HAS_DOF
      col = vec3(texture2D(tDof, vUv).a / 12.0, abs(uDof.z) > 0.0 ? 0.2 : 0.0, 0.0);
#endif
    }
  }
#endif
  gl_FragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}`;
