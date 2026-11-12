// Sky dome: horizon "eclipse sunset" band, black sun with an animated HDR corona, chromosphere and diamond-ring bead,
// two thin drifting cloud layers and anti-aliased stars. Drawn after the opaque world at the far plane (only visible
// sky pixels pay for the shader). The same material, in "env" mode, feeds the PMREM environment map.

import * as THREE from 'three';
import { NOISE, SKY_BASE } from './glsl.js';
import { SUN_RADIUS, DIAMOND_PHI } from './config.js';

const VERT = /* glsl */ `
varying vec3 vDir;
uniform float uEnvMode;
void main() {
  vDir = position;
  vec4 p = projectionMatrix * viewMatrix * vec4(position + cameraPosition, 1.0);
  if (uEnvMode < 0.5) p.z = p.w * 0.999995;
  gl_Position = p;
}`;

const FRAG = /* glsl */ `
${NOISE}
${SKY_BASE}
uniform float uTime, uEnvMode;
uniform vec4 uMood;
uniform vec3 uCorona, uChromo, uWind;
varying vec3 vDir;
#ifndef OCT
#define OCT 5
#endif
const float SUN_R = ${SUN_RADIUS.toFixed(6)};
const float DPHI = ${DIAMOND_PHI.toFixed(6)};

float stars(vec3 dir) {
  vec3 sd = dir * 220.0;
  vec3 cell = floor(sd);
  float h = hash13(cell);
  if (h < 0.9) return 0.0;
  vec3 sp = cell + 0.2 + 0.6 * hash33(cell + 3.1);
  float d = length(sd - sp);
  float fw = max(fwidth(sd.x) + fwidth(sd.y), 1e-3) * 0.9;
  float b = smoothstep(fw * 1.6, 0.0, d);
  float mag = pow((h - 0.9) / 0.1, 3.0);
  float tw = 0.75 + 0.25 * sin(uTime * (1.3 + h * 3.0) + h * 91.0);
  return b * (0.04 + 0.9 * mag) * tw;
}

void main() {
  vec3 dir = normalize(vDir);
  vec3 col = skyBase(dir);
  float env = uEnvMode;

  // ---- eclipse geometry -----------------------------------------------------------------------------------------
  float cs = dot(dir, uSunDir);
  float ang = acos(clamp(cs, -1.0, 1.0));
  float rr = ang / SUN_R;
  vec3 tu = normalize(cross(uSunDir, vec3(0.0, 1.0, 0.0)));
  vec3 tv = cross(tu, uSunDir);
  vec2 q = vec2(dot(dir, tu), dot(dir, tv));
  float phi = atan(q.y, q.x);
  vec2 cp = vec2(cos(phi), sin(phi));
  float k = max(rr - 1.0, 0.0);
  float lr = log(1.0 + k);
  float t = uTime;

  // streamers flowing slowly outward, brighter along a tilted "equator"
  float st1 = fbm3(vec3(cp * 2.2, lr * 1.6 - t * 0.035), 4);
  float st2 = vnoise3(vec3(cp * 7.0, lr * 3.0 - t * 0.06));
  float eq = 0.55 + 0.45 * pow(abs(cos(phi - 0.35)), 2.0);
  float streak = smoothstep(0.3, 0.85, st1) * eq;
  float shimmer = 0.85 + 0.15 * sin(t * 2.3 + st2 * 9.0);
  float corona = exp(-k * 11.0) * 7.0 * shimmer
               + exp(-k * 3.2) * (0.55 + 1.6 * streak) * (0.8 + 0.4 * st2)
               + exp(-k * 0.85) * streak * 0.32
               + exp(-k * 0.3) * 0.035;
  float aa = max(fwidth(rr), 1e-3) * 1.2;
  float disc = smoothstep(1.0 + aa, 1.0 - aa, rr);
  corona *= 1.0 - disc;
  // chromosphere rim + prominences
  float promN = smoothstep(0.62, 0.9, vnoise(cp * 5.0 + 3.0 + t * 0.02));
  float chromo = exp(-k * 90.0) * 1.8 + exp(-k * 22.0) * promN * 2.4;
  chromo *= 1.0 - disc;
  // diamond ring bead on the limb
  vec2 b0 = vec2(cos(DPHI), sin(DPHI)) * SUN_R * 1.005;
  vec2 dq = q - b0;
  float bd = length(dq);
  float bead = exp(-bd * bd / (0.0024 * 0.0024)) * 70.0 + exp(-bd / 0.012) * 2.2 + exp(-bd / 0.05) * 0.25;
  vec2 rq = mat2(0.7071, 0.7071, -0.7071, 0.7071) * dq;
  float rays = (exp(-abs(rq.x) / 0.0009) * exp(-abs(rq.y) / 0.07) + exp(-abs(rq.y) / 0.0009) * exp(-abs(rq.x) / 0.07)) * 3.5;
  rays += (exp(-abs(dq.y) / 0.0007) * exp(-abs(dq.x) / 0.16)) * 1.4;
  float beadPulse = 0.85 + 0.15 * sin(t * 1.7) * sin(t * 2.9 + 1.0);
  bead = (bead + rays) * beadPulse * (1.0 - disc * 0.97);

  // ---- clouds: two thin layers projected on planes, drifting with the wind ----------------------------------------
  float cloudA = 0.0;
  vec3 cloudC = vec3(0.0);
  if (dir.y > -0.04) {
    float py = max(dir.y + 0.07, 0.02);
    vec2 cuv = dir.xz / py;
    vec2 w = uWind.xz * t * 0.004;
    float n1 = fbm2(cuv * 0.55 + w + vec2(0.0, 3.0), OCT);
    float n2 = fbm2(vec2(cuv.x * 0.22, cuv.y * 1.1) * 1.4 + w * 1.6 + 7.0, OCT);
    float d1 = smoothstep(0.52, 0.8, n1) * 0.8;
    float d2 = smoothstep(0.5, 0.78, n2) * 0.55;
    float hf = smoothstep(-0.03, 0.05, dir.y) * (1.0 - smoothstep(0.55, 0.9, dir.y) * 0.6);
    cloudA = clamp(d1 + d2 * (1.0 - d1), 0.0, 1.0) * hf;
    // lighting: dark bodies, horizon-glow undersides, silver lining toward the corona
    float edge = 1.0 - smoothstep(0.0, 0.6, d1 + d2);
    vec3 body = mix(uHorizon * 0.9 + uGlow * 0.35, uSkyMid * 1.15, smoothstep(0.02, 0.3, dir.y));
    float fwd = pow(max(cs, 0.0), 14.0);
    cloudC = body + uCorona * (fwd * (0.6 + 2.2 * edge) + pow(max(cs, 0.0), 120.0) * 3.0 * edge) * 0.35;
  }

  // ---- stars ------------------------------------------------------------------------------------------------------
  float glare = smoothstep(0.9, 0.995, cs);
  float sv = env > 0.5 ? 0.0 : stars(dir) * smoothstep(0.03, 0.3, dir.y) * (1.0 - glare);
  col += vec3(0.75, 0.82, 1.0) * sv * (1.0 - cloudA);

  // ---- composite ------------------------------------------------------------------------------------------------
  vec3 sun = uCorona * corona + uChromo * chromo + vec3(1.0, 0.96, 0.9) * bead;
  sun *= 1.0 - cloudA * 0.55;
  col = mix(col, cloudC, cloudA * 0.9);
  col = col * (1.0 - disc) + vec3(0.0006, 0.0007, 0.001) * disc;
  col += sun;
  if (env > 0.5) col = min(col, vec3(6.0));
  float d = uMood.a;
  col *= mix(vec3(1.0), uMood.rgb, d) * (1.0 - 0.8 * d);
  col += sun * d * 0.5;
  gl_FragColor = vec4(col, 1.0);
}`;

/**
 * Create the sky dome mesh. `U` is the shared env uniform object.
 * @returns {THREE.Mesh}
 */
export function createSky(U, { octaves = 5, envMode = false } = {}) {
  const mat = new THREE.ShaderMaterial({
    name: envMode ? 'env.skyEnv' : 'env.sky',
    vertexShader: VERT,
    fragmentShader: FRAG,
    uniforms: {
      uTime: U.uTime, uSunDir: U.uSunDir, uMood: envMode ? { value: new THREE.Vector4(1, 1, 1, 0) } : U.uMood,
      uZenith: U.uZenith, uSkyMid: U.uSkyMid, uHorizon: U.uHorizon, uGlow: U.uGlow, uSunHalo: U.uSunHalo,
      uCorona: U.uCorona, uChromo: U.uChromo, uWind: U.uWind,
      uEnvMode: { value: envMode ? 1 : 0 },
    },
    defines: { OCT: envMode ? 3 : octaves },
    side: THREE.BackSide,
    depthWrite: false,
    depthTest: !envMode,
    fog: false,
  });
  const mesh = new THREE.Mesh(new THREE.SphereGeometry(400, 48, 24), mat);
  mesh.frustumCulled = false;
  mesh.renderOrder = envMode ? -100 : 1000; // world: drawn after the opaques (far plane, early-z rejects hidden sky)
  mesh.name = envMode ? 'env.skyEnv' : 'env.sky';
  return mesh;
}
