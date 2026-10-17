// Builds the arena: lighting, sky, textured geometry, props and the skyline.
import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { ARENA, BOXES } from './shared/map.js';
import { barrel, sandbags } from './models.js';

function rng(seed) {
  return () => { seed = (seed * 16807) % 2147483647; return (seed - 1) / 2147483646; };
}

// Scale box UVs to world units so textures keep a constant texel density.
function worldUV(geo, w, h, d, scale) {
  const uv = geo.attributes.uv;
  const dims = [[d, h], [d, h], [w, d], [w, d], [w, h], [w, h]];
  for (let f = 0; f < 6; f++) for (let i = 0; i < 4; i++) {
    const k = f * 4 + i;
    uv.setXY(k, uv.getX(k) * dims[f][0] / scale, uv.getY(k) * dims[f][1] / scale);
  }
  return geo;
}

export function buildWorld(scene, T, M, { shadowSize = 2048 } = {}) {
  const FOG = new THREE.Color(0xc9d6e2);
  scene.fog = new THREE.Fog(FOG, 50, 210);

  const sunDir = new THREE.Vector3(0.45, 0.75, 0.35).normalize();
  const sky = new THREE.Mesh(
    new THREE.SphereGeometry(420, 40, 20),
    new THREE.ShaderMaterial({
      side: THREE.BackSide,
      depthWrite: false,
      uniforms: {
        top: { value: new THREE.Color(0x2c68b8) },
        bottom: { value: FOG.clone() },
        sunDir: { value: sunDir },
        time: { value: 0 },
      },
      vertexShader: `varying vec3 vDir;
        void main() { vDir = normalize(position); gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }`,
      fragmentShader: `uniform vec3 top; uniform vec3 bottom; uniform vec3 sunDir; uniform float time; varying vec3 vDir;
        float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
        float vn(vec2 p) { vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
          return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y); }
        float fbm(vec2 p) { float s = 0.0, a = 0.5; for (int i = 0; i < 5; i++) { s += vn(p) * a; p *= 2.03; a *= 0.5; } return s; }
        void main() {
          vec3 d = normalize(vDir);
          float h = clamp(d.y * 1.4, 0.0, 1.0);
          vec3 c = mix(bottom, top, pow(h, 0.55));
          float s = max(dot(d, sunDir), 0.0);
          c += vec3(1.0, 0.92, 0.75) * (pow(s, 1200.0) * 8.0 + pow(s, 16.0) * 0.35 + pow(s, 3.0) * 0.08);
          if (d.y > 0.0) {
            vec2 uv = d.xz / (d.y + 0.12) * 1.6 + vec2(time * 0.004, 0.0);
            float cl = smoothstep(0.48, 0.78, fbm(uv));
            float lit = 0.75 + 0.25 * fbm(uv + sunDir.xz * 0.15);
            c = mix(c, vec3(1.0, 0.99, 0.97) * lit, cl * smoothstep(0.0, 0.25, d.y) * 0.85);
          }
          gl_FragColor = vec4(c, 1.0);
          #include <tonemapping_fragment>
          #include <colorspace_fragment>
        }`,
    }),
  );
  sky.renderOrder = -1;
  scene.add(sky);

  scene.add(new THREE.HemisphereLight(0xd6e6ff, 0x6e5f4c, 0.75));
  const sun = new THREE.DirectionalLight(0xfff0d8, 3.0);
  sun.position.copy(sunDir).multiplyScalar(90);
  sun.castShadow = true;
  sun.shadow.mapSize.set(shadowSize, shadowSize);
  Object.assign(sun.shadow.camera, { left: -58, right: 58, top: 58, bottom: -58, near: 1, far: 230 });
  sun.shadow.bias = -0.0003;
  sun.shadow.normalBias = 0.04;
  scene.add(sun);

  const env = 0.45;
  const mat = (tex, o = {}) => new THREE.MeshStandardMaterial({ map: tex.map, normalMap: tex.normalMap, envMapIntensity: env, ...o });
  const MATS = {
    wall: mat(T.wall, { roughness: 0.9 }),
    concrete: mat(T.concrete, { roughness: 0.86 }),
    crate: mat(T.crate, { roughness: 0.78 }),
    coping: new THREE.MeshStandardMaterial({ color: 0x8d877c, roughness: 0.8, map: T.concrete.map, normalMap: T.concrete.normalMap, envMapIntensity: env }),
  };

  // --- ground ---
  {
    const size = ARENA * 2 + 2;
    const geo = new THREE.PlaneGeometry(size, size);
    geo.attributes.uv.array.forEach((_, i, a) => { a[i] *= size / 8; });
    const ground = new THREE.Mesh(geo, mat(T.ground, { roughness: 0.92 }));
    ground.rotation.x = -Math.PI / 2;
    ground.receiveShadow = true;
    scene.add(ground);

    const outer = new THREE.Mesh(new THREE.PlaneGeometry(1000, 1000), new THREE.MeshStandardMaterial({ color: 0x7d7a72, roughness: 1 }));
    outer.rotation.x = -Math.PI / 2;
    outer.position.y = -0.03;
    scene.add(outer);

    // oil stains / tyre marks
    const stainTex = (() => {
      const c = document.createElement('canvas'); c.width = c.height = 128;
      const g = c.getContext('2d');
      const grd = g.createRadialGradient(64, 64, 4, 64, 64, 62);
      grd.addColorStop(0, 'rgba(20,18,15,.55)'); grd.addColorStop(0.6, 'rgba(25,22,18,.25)'); grd.addColorStop(1, 'rgba(25,22,18,0)');
      g.fillStyle = grd; g.fillRect(0, 0, 128, 128);
      return new THREE.CanvasTexture(c);
    })();
    const stainMat = new THREE.MeshBasicMaterial({ map: stainTex, transparent: true, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -2 });
    const r = rng(7);
    for (let i = 0; i < 28; i++) {
      const s = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), stainMat);
      s.rotation.set(-Math.PI / 2, 0, r() * 6);
      const k = 0.8 + r() * 2.5;
      s.scale.set(k * (0.6 + r()), k, 1);
      s.position.set((r() - 0.5) * ARENA * 1.9, 0.01, (r() - 0.5) * ARENA * 1.9);
      s.receiveShadow = true;
      scene.add(s);
    }
  }

  // --- map geometry, merged per material ---
  const groups = new Map();
  const push = (m, g) => { if (!groups.has(m)) groups.set(m, []); groups.get(m).push(g.index ? g.toNonIndexed() : g); };
  const containerMats = new Map();
  const r = rng(13);
  for (const b of BOXES) {
    const w = b.max[0] - b.min[0], h = b.max[1] - b.min[1], d = b.max[2] - b.min[2];
    const cx = (b.min[0] + b.max[0]) / 2, cy = (b.min[1] + b.max[1]) / 2, cz = (b.min[2] + b.max[2]) / 2;
    if (b.kind === 'barrel') {
      const colors = [0x8b2f22, 0x2a4d7a, 0x4a5a32, 0x9a6a1c];
      const m = barrel(M, colors[Math.floor(r() * colors.length)]);
      m.position.set(cx, b.min[1], cz);
      m.rotation.y = r() * 6;
      scene.add(m);
      continue;
    }
    if (b.kind === 'sandbag') {
      const m = sandbags(M, w, d, h);
      m.position.set(cx, b.min[1], cz);
      scene.add(m);
      continue;
    }
    const geo = new THREE.BoxGeometry(w, h, d);
    let m;
    if (b.kind === 'crate') m = MATS.crate;
    else if (b.kind === 'container') {
      worldUV(geo, w, h, d, 2.5);
      if (!containerMats.has(b.tint)) {
        containerMats.set(b.tint, new THREE.MeshStandardMaterial({
          map: T.container.map, normalMap: T.container.normalMap, color: b.tint, roughness: 0.55, metalness: 0.35, envMapIntensity: env,
        }));
      }
      m = containerMats.get(b.tint);
    } else {
      worldUV(geo, w, h, d, 4);
      m = MATS[b.kind];
    }
    geo.translate(cx, cy, cz);
    push(m, geo);

    // Concrete coping on top of walls/covers, a plinth at the base, and container frames.
    if (b.kind === 'wall' || (b.kind === 'concrete' && h > 0.9 && b.min[1] === 0 && Math.min(w, d) < 1.5)) {
      const cap = worldUV(new THREE.BoxGeometry(w + 0.08, 0.12, d + 0.08), w + 0.08, 0.12, d + 0.08, 4);
      cap.translate(cx, b.max[1] + 0.05, cz);
      push(MATS.coping, cap);
      if (b.min[1] === 0) {
        const base = worldUV(new THREE.BoxGeometry(w + 0.04, 0.18, d + 0.04), w + 0.04, 0.18, d + 0.04, 4);
        base.translate(cx, 0.09, cz);
        push(MATS.coping, base);
      }
    }
    if (b.kind === 'container') {
      const frameMat = containerMats.get(b.tint);
      for (const sx of [-1, 1]) for (const sz of [-1, 1]) {
        const post = new THREE.BoxGeometry(0.12, h + 0.02, 0.12);
        post.translate(cx + sx * (w / 2 - 0.04), cy, cz + sz * (d / 2 - 0.04));
        push(frameMat, post);
      }
      for (const y of [b.min[1] + 0.06, b.max[1] - 0.06]) for (const sz of [-1, 1]) {
        const rail = new THREE.BoxGeometry(w + 0.02, 0.12, 0.1);
        rail.translate(cx, y, cz + sz * (d / 2 - 0.03));
        push(frameMat, rail);
      }
    }
  }
  for (const [m, list] of groups) {
    const mesh = new THREE.Mesh(mergeGeometries(list), m);
    mesh.castShadow = mesh.receiveShadow = true;
    scene.add(mesh);
  }

  // --- skyline outside the arena (decorative) ---
  {
    const list = [];
    const rr = rng(99);
    for (let i = 0; i < 64; i++) {
      const a = (i / 64) * Math.PI * 2 + rr() * 0.05;
      const dist = 80 + rr() * 90;
      const w = 10 + rr() * 14, h = 18 + rr() * 60, d = 10 + rr() * 14;
      const g = worldUV(new THREE.BoxGeometry(w, h, d), w, h, d, 16);
      g.rotateY(rr() * Math.PI);
      g.translate(Math.cos(a) * dist, h / 2, Math.sin(a) * dist);
      list.push(g.toNonIndexed());
    }
    const city = new THREE.Mesh(mergeGeometries(list), new THREE.MeshStandardMaterial({
      map: T.facade.map, emissiveMap: T.facade.emissiveMap, emissive: 0xffffff, emissiveIntensity: 0.25,
      roughness: 0.4, metalness: 0.3, envMapIntensity: 0.6,
    }));
    scene.add(city);
  }

  return {
    sky, sun,
    update(cameraPos, t) {
      sky.position.copy(cameraPos);
      sky.material.uniforms.time.value = t;
    },
  };
}
