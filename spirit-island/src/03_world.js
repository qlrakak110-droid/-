// ============================================================================
//  world: the island of the boundary — terrain, sea, cracked sky, meadows, rifts, altar
// ============================================================================
const GLSL_NOISE = `
  float hash12(vec2 p){ vec3 p3 = fract(vec3(p.xyx) * .1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
  float vnoise(vec2 p){ vec2 i = floor(p), f = fract(p); vec2 u = f*f*(3.0-2.0*f);
    return mix(mix(hash12(i), hash12(i+vec2(1,0)), u.x), mix(hash12(i+vec2(0,1)), hash12(i+vec2(1,1)), u.x), u.y); }
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
  scene.fog = new THREE.Fog(0x6a4a7a, 70, 300);

  // ---------------- lights
  W.hemi = new THREE.HemisphereLight(0xb9b0ff, 0x5a463a, 1.15); scene.add(W.hemi);
  W.sunDir = new THREE.Vector3(-0.62, 0.32, -0.55).normalize();
  const sun = W.sun = new THREE.DirectionalLight(0xffb98a, 2.7);
  sun.castShadow = true; sun.shadow.mapSize.set(isTouch ? 1024 : 2048, isTouch ? 1024 : 2048);
  const sc = sun.shadow.camera; sc.left = -34; sc.right = 34; sc.top = 34; sc.bottom = -34; sc.near = 1; sc.far = 160;
  sun.shadow.bias = -0.0006; sun.shadow.normalBias = 0.04;
  scene.add(sun); scene.add(sun.target);
  W.rim = new THREE.DirectionalLight(0x8f7bff, 0.7); W.rim.position.set(30, 20, 40); scene.add(W.rim);

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
  const terrain = new THREE.Mesh(geo, new THREE.MeshLambertMaterial({ vertexColors: true }));
  terrain.receiveShadow = true; scene.add(terrain); W.terrain = terrain;

  // height texture for the sea shader
  const HT = 256, hd = new Uint8Array(HT * HT);
  for (let i = 0; i < HT; i++) for (let j = 0; j < HT; j++) {
    const x = -S / 2 + (j + 0.5) * S / HT, z = -S / 2 + (i + 0.5) * S / HT;
    hd[i * HT + j] = Math.round(clamp((groundY(x, z) + 8) / 12, 0, 1) * 255);
  }
  const htex = new THREE.DataTexture(hd, HT, HT, THREE.RedFormat); htex.magFilter = htex.minFilter = THREE.LinearFilter; htex.needsUpdate = true;

  // ---------------- sea
  W.skyU = makeSkyUniforms();
  W.waterU = {
    uTime: Shared.time, uH: { value: htex }, uTop: W.skyU.uTop, uMid: W.skyU.uMid, uHor: W.skyU.uHor,
    uDeep: { value: new THREE.Color(0x0e2a55) }, uShallow: { value: new THREE.Color(0x2cc3c9) }, uFoam: { value: new THREE.Color(0xf4f0ff) },
    uSky: { value: new THREE.Color(0xb48ad0) }, uSunDir: { value: W.sunDir }, uSunCol: { value: new THREE.Color(0xffc29a) },
  };
  const water = new THREE.Mesh(new THREE.PlaneGeometry(1400, 1400, 1, 1).rotateX(-Math.PI / 2), new THREE.ShaderMaterial({
    uniforms: THREE.UniformsUtils.merge([THREE.UniformsLib.fog]), transparent: true, fog: true,
    vertexShader: `varying vec3 vW; ${FOG_V}
      void main(){ vec4 w = modelMatrix*vec4(position,1.0); vW = w.xyz; vec4 mvPosition = viewMatrix*w; gl_Position = projectionMatrix*mvPosition;
        #include <fog_vertex>
      }`,
    fragmentShader: `uniform float uTime; uniform sampler2D uH; uniform vec3 uDeep, uShallow, uFoam, uSky, uSunDir, uSunCol, uTop, uMid, uHor; varying vec3 vW;
      vec3 skyCol(vec3 d){ float y = max(d.y, 0.0); vec3 c = mix(uHor, uMid, smoothstep(-0.04, 0.3, y)); return mix(c, uTop, smoothstep(0.3, 0.9, y)); }
      ${GLSL_NOISE}
      ${FOG_F}
      void main(){
        vec2 uv = (vW.xz + 150.0) / 300.0; float h = -8.0;
        if (uv.x > 0.0 && uv.y > 0.0 && uv.x < 1.0 && uv.y < 1.0) h = texture2D(uH, uv).r * 12.0 - 8.0;
        float depth = clamp(-h, 0.0, 8.0); float t = uTime;
        vec2 p = vW.xz * 0.16;
        float n1 = vnoise(p + vec2(t*0.09, t*0.05)), n2 = vnoise(p*2.3 - vec2(t*0.07, -t*0.1)), n3 = vnoise(p*5.1 + vec2(-t*0.15, t*0.12));
        vec3 N = normalize(vec3((n1-0.5)*0.55 + (n3-0.5)*0.25, 1.0, (n2-0.5)*0.55 - (n3-0.5)*0.2));
        vec3 V = normalize(cameraPosition - vW);
        float fres = pow(1.0 - max(dot(N, V), 0.0), 4.0);
        vec3 col = mix(uShallow, uDeep, smoothstep(0.0, 4.5, depth));
        vec3 Rf = reflect(-V, N);
        col = mix(col, mix(skyCol(Rf) * 1.08, uSky, 0.3), clamp(fres * 0.85, 0.0, 0.9));
        col += uSunCol * pow(max(dot(Rf, uSunDir), 0.0), 90.0) * 2.6;
        float shore = 1.0 - smoothstep(0.0, 1.1, depth);
        float wave = sin(depth * 7.0 - t * 1.8 + vnoise(vW.xz*0.3)*4.0) * 0.5 + 0.5;
        float fo = smoothstep(0.62, 0.9, wave * shore + vnoise(vW.xz * 0.9 + t * 0.3) * 0.35);
        col = mix(col, uFoam * 1.3, clamp(fo + smoothstep(0.25, 0.0, depth) * 0.7, 0.0, 1.0) * shore);
        col += vec3(1.6) * step(0.986, vnoise(vW.xz * 2.4 + vec2(t * 0.5, 0.0))) * (1.0 - shore) * fres * 3.0;
        float a = mix(0.55, 0.96, smoothstep(0.0, 2.2, depth));
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
  W.grass = buildGrass(scene, ZONES);
  W.fireflies = buildFireflies(scene);
  buildTown(scene);
  buildAltar(scene);
  for (const r of SITES.rifts) buildRift(scene, r);
  W.fx = new Particles(scene, 1600);
  buildLegendSites();

  // ---------------- player & follower
  W.player = buildPerson({ top: 0xf1f3fb, bottom: 0x2b2f4a, accent: 0x7d55f0, hair: 0x2a2238, pin: 0xffd98a });
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
function recolorTerrain() {
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
    uSunDir: { value: new THREE.Vector3(-0.62, 0.32, -0.55).normalize() }, uMoonDir: { value: new THREE.Vector3(0.55, 0.42, -0.72).normalize() },
    uCrackDir: { value: new THREE.Vector3(0.08, 0.5, -1).normalize() }, uCrack: { value: 1 }, uStars: { value: 1 }, uCloud: { value: 1 }, uSunAmt: { value: 1 },
  };
}
function makeSky(U) {
  const g = new THREE.Group();
  const mat = new THREE.ShaderMaterial({
    uniforms: U, side: THREE.BackSide, depthWrite: false, fog: false,
    vertexShader: `varying vec3 vDir; void main(){ vDir = position; vec4 p = projectionMatrix * modelViewMatrix * vec4(position,1.0); gl_Position = p.xyww; }`,
    fragmentShader: `uniform vec3 uTop, uMid, uHor, uSunDir, uMoonDir, uCrackDir; uniform float uTime, uCrack, uStars, uCloud, uSunAmt; varying vec3 vDir;
      ${GLSL_NOISE}
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
        vec3 col = mix(uHor, uMid, smoothstep(-0.04, 0.3, y));
        col = mix(col, uTop, smoothstep(0.3, 0.9, y));
        col = mix(col, uHor * 0.45, smoothstep(0.0, -0.25, y));
        float s = max(dot(d, uSunDir), 0.0);
        col += (vec3(1.0, 0.55, 0.32) * pow(s, 5.0) * 0.5 + vec3(1.0, 0.82, 0.6) * pow(s, 900.0) * 5.0) * uSunAmt;
        float bands = vnoise(vec2(atan(d.z, d.x) * 3.0, y * 14.0)) * smoothstep(0.02, 0.12, y) * smoothstep(0.35, 0.12, y);
        col = mix(col, col * 1.25 + vec3(0.06, 0.02, 0.05), bands * 0.6);
        float md = dot(d, uMoonDir);
        float moon = smoothstep(0.99935, 0.99955, md);
        vec3 mc = vec3(0.92, 0.9, 1.0) * (0.85 + 0.15 * vnoise(d.xz * 900.0));
        col = mix(col, mc * 1.4, moon * uStars);
        col += vec3(0.5, 0.45, 0.8) * pow(max(md, 0.0), 220.0) * 0.6 * uStars;
        if (y > 0.0 && uCloud > 0.001) {
          vec2 cp = d.xz / (y + 0.11) * 1.45 + vec2(uTime * 0.011, uTime * 0.004);
          float cn = vnoise(cp) * 0.5 + vnoise(cp * 2.1 + 3.7) * 0.27 + vnoise(cp * 4.3 + 9.1) * 0.15 + vnoise(cp * 8.9 + 1.3) * 0.08;
          float cov = smoothstep(0.47, 0.76, cn) * smoothstep(0.0, 0.07, y) * (1.0 - smoothstep(0.5, 0.92, y)) * min(uCloud, 1.0);
          vec3 hd = normalize(vec3(d.x, 0.0, d.z) + 1e-4), sd = normalize(vec3(uSunDir.x, 0.0, uSunDir.z) + 1e-4);
          float sunSide = pow(max(dot(hd, sd), 0.0), 2.0);
          vec3 lit = mix(uMid * 1.25 + vec3(0.06), uHor * 1.4 + vec3(0.12, 0.06, 0.05), sunSide * 0.85 + 0.15);
          vec3 shade = uMid * 0.62 + uTop * 0.38;
          float rimC = smoothstep(0.47, 0.56, cn) - smoothstep(0.56, 0.7, cn);
          vec3 cc = mix(shade, lit, 0.35 + 0.65 * smoothstep(0.85, 0.5, cn) * (0.4 + 0.6 * sunSide)) + uHor * rimC * (0.25 + sunSide) * 0.7;
          col = mix(col, cc, cov * (0.82 + 0.1 * uCloud));
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
    const sm = new THREE.SpriteMaterial({ map: TEX.cloud, color: new THREE.Color(0xf0a6c0), transparent: true, opacity: rand(0.35, 0.6), depthWrite: false, fog: false });
    const spr = new THREE.Sprite(sm);
    spr.position.set(Math.cos(a) * dist * Math.cos(el), Math.sin(el) * dist, Math.sin(a) * dist * Math.cos(el));
    spr.scale.set(rand(160, 280), rand(50, 90), 1); spr.renderOrder = -8; g.add(spr); g.userData.clouds.push(spr);
  }
  return g;
}

// ---------------- trees (instanced)
function buildTrees(scene) {
  const rng = mulberry32(1337);
  const round = [], pine = [];
  const ok = (x, z) => {
    const h = groundY(x, z); if (h < 1.3 || h > 13) return false;
    if (pathDist(x, z) < 4.5) return false;
    for (const zz of ZONES) if (Math.hypot(x - zz.x, z - zz.z) < zz.r + 2.5) return false;
    if (Math.hypot(x - SITES.town.x, z - SITES.town.z) < 22) return false;
    if (Math.hypot(x - SITES.altar.x, z - SITES.altar.z) < 15) return false;
    for (const r of SITES.rifts) if (Math.hypot(x - r.x, z - r.z) < 12) return false;
    for (const t of round.concat(pine)) if (Math.hypot(x - t.x, z - t.z) < 3.6) return false;
    return true;
  };
  for (let k = 0; k < 2600 && round.length + pine.length < 230; k++) {
    const x = (rng() - 0.5) * 190, z = (rng() - 0.5) * 190;
    if (!ok(x, z)) continue;
    const s = 0.8 + rng() * 0.7;
    const isPine = z < -18 ? rng() < 0.75 : rng() < 0.18;
    (isPine ? pine : round).push({ x, z, s, r: rng() * 6.28, blossom: !isPine && z > 20 && rng() < 0.35, v: rng() });
    World.colliders.push({ x, z, r: 0.7 * s });
  }
  const trunkG = new THREE.CylinderGeometry(0.18, 0.3, 2.2, 7).translate(0, 1.1, 0);
  const trunkM = new THREE.MeshToonMaterial({ color: 0x6b4a33, gradientMap: toonGrad });
  const all = round.concat(pine);
  const trunks = new THREE.InstancedMesh(trunkG, trunkM, all.length);
  const canG = new THREE.IcosahedronGeometry(1, 1);
  const canM = new THREE.MeshLambertMaterial({ color: 0xffffff, flatShading: true });
  canM.onBeforeCompile = (sh) => {
    sh.uniforms.uTime = Shared.time;
    sh.vertexShader = 'uniform float uTime;\n' + sh.vertexShader.replace('#include <begin_vertex>', `#include <begin_vertex>
      #ifdef USE_INSTANCING
        float wph = instanceMatrix[3].x * 0.21 + instanceMatrix[3].z * 0.17;
        float wk = position.y + 1.0;
        transformed.x += (sin(uTime * 1.3 + wph) * 0.05 + sin(uTime * 2.7 + wph * 2.0) * 0.015) * wk;
        transformed.z += cos(uTime * 1.1 + wph) * 0.035 * wk;
      #endif`);
  };
  const cans = new THREE.InstancedMesh(canG, canM, round.length * 3);
  const pineG = new THREE.ConeGeometry(1, 1.6, 7);
  const pines = new THREE.InstancedMesh(pineG, canM, pine.length * 3);
  const m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), e = new THREE.Euler(), v = new THREE.Vector3(), sc = new THREE.Vector3(), c = new THREE.Color();
  all.forEach((t, i) => {
    const y = groundY(t.x, t.z) - 0.1;
    m4.compose(v.set(t.x, y, t.z), q.setFromEuler(e.set(0, t.r, 0)), sc.set(t.s, t.s * (pine.includes(t) ? 1.1 : 1), t.s));
    trunks.setMatrixAt(i, m4);
  });
  const greens = [0x3e8f4a, 0x4fa857, 0x5cb25a, 0x357d47], pinks = [0xf2a6c8, 0xf7bfd8, 0xe68fb6];
  round.forEach((t, i) => {
    const y = groundY(t.x, t.z) + 2.0 * t.s;
    const offs = [[0, 0.5, 0, 1.25], [0.7, 0.05, 0.3, 0.95], [-0.6, 0.1, -0.35, 0.9]];
    offs.forEach(([ox, oy, oz, s], k) => {
      m4.compose(v.set(t.x + ox * t.s, y + oy * t.s, t.z + oz * t.s), q.setFromEuler(e.set(t.r, t.r * 2, 0)), sc.setScalar(s * t.s * 1.15));
      cans.setMatrixAt(i * 3 + k, m4);
      c.setHex(t.blossom ? pinks[(i + k) % 3] : greens[(i + k) % 4]); cans.setColorAt(i * 3 + k, c);
    });
  });
  pine.forEach((t, i) => {
    const y = groundY(t.x, t.z);
    for (let k = 0; k < 3; k++) {
      const s = (1.6 - k * 0.38) * t.s;
      m4.compose(v.set(t.x, y + (1.9 + k * 1.05) * t.s, t.z), q.setFromEuler(e.set(0, t.r + k, 0)), sc.set(s, s, s));
      pines.setMatrixAt(i * 3 + k, m4);
      c.setHex([0x2f6b4a, 0x3a7a55, 0x2a5f44][(i + k) % 3]); pines.setColorAt(i * 3 + k, c);
    }
  });
  for (const im of [trunks, cans, pines]) { im.castShadow = true; im.receiveShadow = true; im.instanceMatrix.needsUpdate = true; if (im.instanceColor) im.instanceColor.needsUpdate = true; scene.add(im); }
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
  const rm = new THREE.InstancedMesh(GEO.dodeca, new THREE.MeshLambertMaterial({ color: 0xffffff, flatShading: true }), rocks.length);
  const m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), e = new THREE.Euler(), v = new THREE.Vector3(), sc = new THREE.Vector3(), c = new THREE.Color();
  rocks.forEach((r, i) => {
    m4.compose(v.set(r.x, r.h + r.s * 0.2, r.z), q.setFromEuler(e.set(r.r, r.r * 1.7, r.r * 0.3)), sc.set(r.s, r.s * 0.75, r.s));
    rm.setMatrixAt(i, m4); c.setHex([0x8c8378, 0x9a9184, 0x7b746c][i % 3]); rm.setColorAt(i, c);
  });
  rm.castShadow = rm.receiveShadow = true; scene.add(rm);
  // flowers: little glowing dots that catch the bloom at dusk
  const fl = [];
  for (let k = 0; k < 3000 && fl.length < 700; k++) {
    const x = (rng() - 0.5) * 180, z = (rng() - 0.5) * 180, h = groundY(x, z);
    if (h < 1.1 || h > 9 || pathDist(x, z) < 2.4) continue;
    fl.push({ x, z, h });
  }
  const fm = new THREE.InstancedMesh(new THREE.OctahedronGeometry(0.11, 0), new THREE.MeshBasicMaterial({ color: new THREE.Color(1.3, 1.3, 1.3) }), fl.length);
  const fc = [0xffc6e0, 0xfff1a8, 0xd9c8ff, 0xffffff, 0xa8e6ff];
  fl.forEach((f, i) => { m4.compose(v.set(f.x, f.h + 0.15, f.z), q.identity(), sc.setScalar(0.7 + rng() * 0.6)); fm.setMatrixAt(i, m4); c.setHex(fc[i % fc.length]); fm.setColorAt(i, c); });
  scene.add(fm);
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
    const n = Math.floor(Math.PI * z.r * z.r * dens);
    for (let i = 0; i < n; i++) {
      const a = Math.random() * Math.PI * 2, rr = Math.sqrt(Math.random()) * z.r;
      const x = z.x + Math.cos(a) * rr, zz = z.z + Math.sin(a) * rr;
      const edge = 1 - smooth(z.r * 0.75, z.r, rr);
      list.push([x, zz, (0.9 + Math.random() * 0.7) * (0.45 + edge * 0.55)]);
    }
  }
  const im = new THREE.InstancedMesh(blade, mat, list.length);
  const m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), e = new THREE.Euler(), v = new THREE.Vector3(), sc = new THREE.Vector3();
  list.forEach(([x, z, h], i) => { m4.compose(v.set(x, groundY(x, z) - 0.05, z), q.setFromEuler(e.set(rand(-0.15, 0.15), rand(0, 6.28), rand(-0.15, 0.15))), sc.set(1.1, h, 1)); im.setMatrixAt(i, m4); });
  im.frustumCulled = false; im.receiveShadow = false;
  scene.add(im);
  if (Settings.high) {
    const lawn = [], rng = mulberry32(4242);
    for (let k = 0; k < 90000 && lawn.length < (isTouch ? 12000 : 26000); k++) {
      const x = (rng() - 0.5) * 176, z = (rng() - 0.5) * 176, h = groundY(x, z);
      if (h < 1.05 || h > 9.5 || pathDist(x, z) < 2.4) continue;
      if (Math.hypot(x - SITES.town.x, z - SITES.town.z) < 10.5 || Math.hypot(x - SITES.altar.x, z - SITES.altar.z) < 10.5) continue;
      let bad = false;
      for (const zz of zones) if (Math.hypot(x - zz.x, z - zz.z) < zz.r) { bad = true; break; }
      for (const r of SITES.rifts) if (Math.hypot(x - r.x, z - r.z) < 15) { bad = true; break; }
      if (bad) continue;
      lawn.push([x, z, h, 0.28 + rng() * 0.3, rng() * 6.28]);
    }
    const lm = new THREE.InstancedMesh(blade, mat, lawn.length);
    lawn.forEach(([x, z, h, s, r], i) => { m4.compose(v.set(x, h - 0.04, z), q.setFromEuler(e.set(rand(-0.2, 0.2), r, rand(-0.2, 0.2))), sc.set(1.25, s, 1)); lm.setMatrixAt(i, m4); });
    lm.frustumCulled = false; scene.add(lm);
  }
  return { mesh: im, U: mat.uniforms };
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

// ---------------- town
function house(scene, x, z, rot, wall, roof, s = 1, opts = {}) {
  const g = grp(scene, [x, groundY(x, z), z], [0, rot, 0]); g.scale.setScalar(s);
  part(GEO.box, M(0x8a7f74), g, [0, 0.2, 0], [5.4, 0.4, 4.6]);
  part(GEO.box, M(wall), g, [0, 2.0, 0], [5, 3.4, 4.2]);
  for (const sx of [-1, 1]) part(GEO.box, M(0x7a5236), g, [sx * 2.5, 2.0, 2.1], [0.3, 3.4, 0.3]);
  const rf = part(new THREE.ConeGeometry(4.1, 2.6, 4), M(roof), g, [0, 5.0, 0], [1.05, 1, 0.92], [0, Math.PI / 4, 0]);
  rf.userData.noOl = true;
  part(GEO.box, M(0x5a3b26), g, [0, 1.25, 2.12], [1.1, 2.1, 0.12]);
  part(GEO.sphere, E(0xffd27a, 2), g, [0.38, 1.25, 2.2], 0.06);
  for (const sx of [-1.6, 1.6]) { part(GEO.box, E(0xffc46b, 1.7), g, [sx, 2.4, 2.12], [0.8, 0.8, 0.08]); part(GEO.box, M(0x5a3b26), g, [sx, 2.4, 2.15], [0.9, 0.08, 0.06]); }
  part(GEO.box, E(0xffc46b, 1.5), g, [2.52, 2.4, 0], [0.08, 0.8, 0.9]);
  part(GEO.box, M(0x9a8f88), g, [1.4, 5.4, -0.8], [0.6, 1.6, 0.6]);
  if (opts.crystal) {
    const c = part(GEO.octa, E(0x8ff3ff, 2.6), g, [0, 7.4, 0], [0.45, 0.8, 0.45]);
    World.spinners.push(c);
    part(GEO.box, E(0x8ff3ff, 1.6), g, [0, 3.95, 2.13], [1.6, 0.35, 0.08]);
  }
  g.traverse((o) => { if (o.isMesh && !o.material.isMeshBasicMaterial) { o.castShadow = true; o.receiveShadow = true; } });
  World.colliders.push({ x, z, r: 3.2 * s });
  // extra colliders along the long side
  const cs = Math.cos(rot), sn = Math.sin(rot);
  for (const off of [-1.8, 1.8]) World.colliders.push({ x: x + cs * off * s, z: z - sn * off * s, r: 2.4 * s });
  return g;
}
function lantern(scene, x, z) {
  const y = groundY(x, z);
  const g = grp(scene, [x, y, z]);
  part(GEO.cyl, M(0x3a3046), g, [0, 1.2, 0], [0.07, 2.4, 0.07]);
  part(GEO.box, M(0x3a3046), g, [0, 2.45, 0], [0.42, 0.06, 0.42]);
  part(GEO.sphere, E(0xffcf8a, 3), g, [0, 2.2, 0], 0.17);
  part(GEO.cone4, M(0x3a3046), g, [0, 2.62, 0], [0.32, 0.3, 0.32], [0, Math.PI / 4, 0]);
  World.colliders.push({ x, z, r: 0.3 });
}
function buildTown(scene) {
  World.spinners = [];
  const T = SITES.town;
  World.healHouse = house(scene, T.x - 13, T.z - 3, Math.PI / 2, 0xf3e6d2, 0x4e5aa8, 1, { crystal: true });
  house(scene, T.x + 13, T.z - 4, -Math.PI / 2, 0xf0dcc8, 0xc4584a, 0.95);
  house(scene, T.x - 12, T.z + 11, Math.PI * 0.85, 0xe8e0d0, 0x4f8a5a, 0.9);
  house(scene, T.x + 12, T.z + 10, -Math.PI * 0.85, 0xf3e6d2, 0x8a5aa8, 0.9);
  house(scene, T.x + 10, T.z - 15, -Math.PI * 0.2, 0xe8e0d0, 0xc4584a, 0.85);
  // fountain of healing
  const fy = groundY(T.x, T.z);
  const f = grp(scene, [T.x, fy, T.z]);
  part(GEO.cyl, M(0xb8b0a8), f, [0, 0.3, 0], [2.4, 0.6, 2.4]);
  part(GEO.cyl, M(0xa29a92), f, [0, 0.62, 0], [2.5, 0.12, 2.5]);
  part(GEO.circle, E(0x5fd8ff, 1.15), f, [0, 0.58, 0], 2.15, [-Math.PI / 2, 0, 0]);
  part(GEO.cyl, M(0xb8b0a8), f, [0, 1.1, 0], [0.35, 1.2, 0.35]);
  const cr = part(GEO.octa, E(0x8ff3ff, 3), f, [0, 2.4, 0], [0.42, 0.75, 0.42]);
  World.spinners.push(cr); World.fountainCrystal = cr;
  f.traverse((o) => { if (o.isMesh && !o.material.isMeshBasicMaterial) { o.castShadow = true; o.receiveShadow = true; } });
  World.colliders.push({ x: T.x, z: T.z, r: 2.6 });
  World.fountain = f;
  const pl = new THREE.PointLight(0x8ff3ff, 18, 16, 1.6); pl.position.set(T.x, fy + 2.6, T.z); scene.add(pl);
  // lanterns along the paths
  for (const P of PATHS) for (let i = 0; i < P.length - 1; i++) {
    const [ax, az] = P[i], [bx, bz] = P[i + 1], L = Math.hypot(bx - ax, bz - az), n = Math.floor(L / 13);
    for (let k = 1; k <= n; k++) {
      const t = k / (n + 1), x = lerp(ax, bx, t), z = lerp(az, bz, t), nx = -(bz - az) / L, nz = (bx - ax) / L, side = k % 2 ? 1 : -1;
      const lx = x + nx * 3 * side, lz = z + nz * 3 * side;
      if (Math.hypot(lx - T.x, lz - T.z) < 14) continue;
      lantern(scene, lx, lz);
    }
  }
  // starter pedestals
  World.pedestals = [];
  [[-3.4, 57.6], [0, 58.4], [3.4, 57.6]].forEach(([x, z], i) => {
    const y = groundY(x, z);
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
    part(GEO.cyl, ST, g, [Math.cos(a) * 7.2, h / 2 + 0.4, Math.sin(a) * 7.2], [0.5, h, 0.5]);
    part(GEO.box, ST2, g, [Math.cos(a) * 7.2, 0.6, Math.sin(a) * 7.2], [1.3, 0.4, 1.3], [0, -a, 0]);
    if (!broken) part(GEO.box, ST2, g, [Math.cos(a) * 7.2, h + 0.55, Math.sin(a) * 7.2], [1.2, 0.35, 1.2], [0, -a, 0]);
    else part(GEO.cyl, ST, g, [Math.cos(a) * 7.2, h + 2.2, Math.sin(a) * 7.2], [0.5, 1.2, 0.5], [0.3, 0, 0.2]);
    World.colliders.push({ x: A.x + Math.cos(a) * 7.2, z: A.z + Math.sin(a) * 7.2, r: 0.75 });
  }
  World.colliders.push({ x: A.x, z: A.z, r: 1.4 });
  const fl = grp(g, [0, 0, 0]);
  for (let i = 0; i < 7; i++) {
    const a = (i / 7) * Math.PI * 2, R = 10 + (i % 3) * 2;
    const rk = grp(fl, [Math.cos(a) * R, 5 + (i % 3) * 2.5, Math.sin(a) * R]);
    part(GEO.dodeca, M(0x8e88a0), rk, [0, 0, 0], [0.9, 0.6, 0.8]);
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
  recolorTerrain();
}
function fragCount() { return SITES.rifts.reduce((s, r) => s + (S.flags['closed_' + r.id] ? 1 : 0), 0); }

// ---------------- atmosphere: lerp between corrupted dusk, healed sunset, and dawn
const ATMOS = {
  dark:  { top: 0x0c0a2a, mid: 0x4a2a6a, hor: 0xe0728a, fog: 0x6a4a7a, sun: 0xffa27a, hemiS: 0xb0a4ff, hemiG: 0x5a463a, sea: 0xb48ad0, cloud: 0xf0a6c0, sunI: 2.5, stars: 1 },
  heal:  { top: 0x15204a, mid: 0x6a4a9a, hor: 0xffa47a, fog: 0x8a6a8a, sun: 0xffc08a, hemiS: 0xc8c0ff, hemiG: 0x6a5440, sea: 0xd0a0c8, cloud: 0xffc0b0, sunI: 2.9, stars: 0.8 },
  dawn:  { top: 0x2f62b0, mid: 0x8fb4ea, hor: 0xffd6a8, fog: 0xc8d0e8, sun: 0xfff0d8, hemiS: 0xe4ecff, hemiG: 0x7a6a50, sea: 0xbfe2ff, cloud: 0xffffff, sunI: 3.3, stars: 0 },
};
function applyAtmos() {
  const W = World, a = ATMOS.dark, b = ATMOS.heal, d = ATMOS.dawn, h = W.heal, k = W.dawn;
  const mix = (key) => new THREE.Color(a[key]).lerp(new THREE.Color(b[key]), h).lerp(new THREE.Color(d[key]), k);
  const num = (key) => lerp(lerp(a[key], b[key], h), d[key], k);
  W.skyU.uTop.value.copy(mix('top')); W.skyU.uMid.value.copy(mix('mid')); W.skyU.uHor.value.copy(mix('hor'));
  W.skyU.uStars.value = num('stars');
  W.scene.fog.color.copy(mix('fog'));
  W.sun.color.copy(mix('sun')); W.sun.intensity = num('sunI');
  W.hemi.color.copy(mix('hemiS')); W.hemi.groundColor.copy(mix('hemiG'));
  W.waterU.uSky.value.copy(mix('sea'));
  const cc = mix('cloud'); for (const c of W.sky.userData.clouds) c.material.color.copy(cc);
  if (!W.crackOverride) W.skyU.uCrack.value = S.flags.ending ? 0 : S.flags.awakened ? 2.2 : (1 - h * 0.65);
  const sd = W.sunDir.clone(); sd.y = lerp(0.32, 0.5, k); sd.normalize(); W.skyU.uSunDir.value.copy(sd);
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
  const add = (x, z, y, color) => { const g = buildMarker(color); g.position.set(x, y, z); World.markers.push({ g, y }); };
  if (!S.party.length) { add(0, 55, groundY(0, 55) + 4.2, 0xffd98a); return; }
  for (const r of SITES.rifts) if (!S.flags['closed_' + r.id]) add(r.x, r.z, groundY(r.x, r.z) + 12, 0xc77dff);
  if (fragCount() >= 3 && !S.flags.ending) add(SITES.altar.x, SITES.altar.z, World.altarY + 9, 0xffd98a);
  const LC = { asterion: 0x8fe0ff, abyssea: 0x4ff0ff, danha: 0xffa860, limina: 0xffffff };
  for (const sp in LC) if (legendPresent(sp)) { const st = World.legendSites[sp]; add(st.x, st.z, st.y + 9, LC[sp]); }
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
      if (W.stepAcc > (ax.run ? 2.4 : 1.7)) { W.stepAcc = 0; Snd.fx('step'); }
      onPlayerMoved(moved);
    }
  } else { Input.dragDX = 0; Input.zoom = 0; }
  P.moving = damp(P.moving, moving, 10, dt);
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
  if (W.fountainCrystal) W.fountainCrystal.position.y = 2.4 + Math.sin(W.t * 2) * 0.15;
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
  applyAtmos();
  W.fx.update(dt);

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
  const sh = grp(W.scene, [hill.x, hill.y, hill.z]);
  part(GEO.cyl, M(0xa8a2b8), sh, [0, 0.3, 0], [1.3, 0.6, 1.3]);
  part(GEO.box, M(0x8e88a0), sh, [0, 1.3, 0], [0.7, 1.6, 0.5]);
  W.dawnStone = part(GEO.octa, E(0xffa860, 2.2), sh, [0, 2.6, 0], [0.32, 0.55, 0.32]);
  W.colliders.push({ x: hill.x, z: hill.z, r: 1.2 });
  // the whale rock on the west cliff
  const wr = grp(W.scene, [west.x + 6.5, groundY(west.x + 6.5, west.z + 2.5), west.z + 2.5]);
  part(GEO.dodeca, M(0x6f6a78), wr, [0, 0.9, 0], [1.6, 1.2, 1.1]);
  part(GEO.dodeca, M(0x7f7a88), wr, [0.9, 1.9, 0.2], [0.8, 0.7, 0.7]);
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
