// Post-processing lab: HDR emissive shapes on the neutral stage to check bloom, tone mapping and the screen FX.
import * as THREE from 'three';
import { createLab } from '../core/lab.js';

createLab({
  view: { target: [0, 1.2, 0], dist: 8, yaw: 12, pitch: 8 },
  setup(ctx) {
    const { scene } = ctx;
    const cols = [[4, 0.9, 0.25], [0.3, 1.6, 5], [3, 0.6, 5], [6, 5, 3], [0.4, 4, 1.2]];
    cols.forEach((c, i) => {
      const m = new THREE.Mesh(new THREE.SphereGeometry(0.22, 24, 16), new THREE.MeshBasicMaterial({ color: new THREE.Color(c[0], c[1], c[2]) }));
      m.position.set(-3 + i * 1.5, 1.2 + (i % 2) * 0.6, 0);
      scene.add(m);
    });
    const knight = new THREE.Mesh(new THREE.CapsuleGeometry(0.35, 1.1, 8, 16), new THREE.MeshStandardMaterial({ color: 0x8a8f9c, metalness: 0.9, roughness: 0.35 }));
    knight.position.set(0, 0.9, 1.5); knight.castShadow = true;
    scene.add(knight);
    const blade = new THREE.Mesh(new THREE.BoxGeometry(0.06, 1.6, 0.01), new THREE.MeshBasicMaterial({ color: new THREE.Color(8, 3, 0.6) }));
    blade.position.set(0.7, 1.4, 1.5); blade.rotation.z = -0.5;
    scene.add(blade);
    const ring = new THREE.Mesh(new THREE.RingGeometry(0.6, 0.9, 48), new THREE.ShaderMaterial({
      transparent: true, blending: THREE.AdditiveBlending, depthTest: false,
      vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }',
      fragmentShader: 'varying vec2 vUv; void main(){ vec2 d = normalize(vUv - 0.5); gl_FragColor = vec4(d * 0.03, 0.0, 1.0); }',
    }));
    ring.position.set(-1.5, 1.3, 1.0);
    ring.visible = false;
    ctx.post.distortionScene.add(ring);
    ctx._ring = ring;
  },
  scenarios: {
    hit(ctx) { ctx.post.pulse('chroma', 1, { release: 0.4 }); ctx.post.pulse('radial', 0.8, { release: 0.35 }); ctx.post.flash(0xfff2d0, 0.6); },
    impact(ctx) { ctx.post.impactFrame({ duration: 0.1 }); },
    dim(ctx) { ctx.post.to({ exposure: 0.45, saturation: 0.5, letterbox: 1, tint: 0x9fb4ff }, 0.3); },
    reset(ctx) { ctx.post.reset(0.3); },
    distort(ctx) { ctx._ring.visible = true; },
  },
});
