// Post-processing lab: HDR emissive shapes, carved blocks, two stand-in fighters, braziers and a far eclipse ring on the
// neutral stage to check bloom, tone mapping, AO, fog + in-scattering, light shafts, depth of field, grading, shadows
// and the screen FX. Debug views: __ED.lab.play('debug', 'ao' | 'depth' | 'shafts' | 'dof' | 'off').
import * as THREE from 'three';
import { createLab } from '../core/lab.js';

createLab({
  view: { target: [0, 1.2, 0], dist: 8, yaw: 12, pitch: 8 },
  setup(ctx, lab) {
    const { scene } = ctx;
    const stone = new THREE.MeshStandardMaterial({ color: 0x5b5a58, roughness: 0.8, metalness: 0.0 });
    const add = (mesh, x, y, z, ry = 0) => { mesh.position.set(x, y, z); mesh.rotation.y = ry; scene.add(mesh); return mesh; };
    // HDR emissive spheres (bloom / tone mapping)
    const cols = [[4, 0.9, 0.25], [0.3, 1.6, 5], [3, 0.6, 5], [6, 5, 3], [0.4, 4, 1.2]];
    cols.forEach((c, i) => add(new THREE.Mesh(new THREE.SphereGeometry(0.22, 24, 16), new THREE.MeshBasicMaterial({ color: new THREE.Color(c[0], c[1], c[2]) })), -3 + i * 1.5, 1.2 + (i % 2) * 0.6, -1.2));
    // carved architecture stand-ins: a column row, a stepped plinth, an arch (AO creases)
    for (let i = 0; i < 4; i++) {
      const col = add(new THREE.Mesh(new THREE.CylinderGeometry(0.42, 0.5, 4.2, 20), stone), -5 + i * 3.4, 2.1, -4.2);
      const base = add(new THREE.Mesh(new THREE.BoxGeometry(1.3, 0.35, 1.3), stone), col.position.x, 0.175, -4.2);
      base.receiveShadow = col.receiveShadow = true;
    }
    for (let s = 0; s < 3; s++) add(new THREE.Mesh(new THREE.BoxGeometry(3.4 - s * 0.8, 0.22, 1.6 - s * 0.35), stone), 3.6, 0.11 + s * 0.22, 1.2).receiveShadow = true;
    const arch = add(new THREE.Mesh(new THREE.TorusGeometry(1.6, 0.32, 12, 32, Math.PI), stone), -3.6, 0, -2.0, 0.25);
    arch.receiveShadow = true;
    // stand-in fighters (shadow casters): a metal knight + a darker one with a blade
    const metal = new THREE.MeshStandardMaterial({ color: 0x8a8f9c, metalness: 0.9, roughness: 0.35 });
    const dark = new THREE.MeshStandardMaterial({ color: 0x2c2a30, metalness: 0.6, roughness: 0.5 });
    const knight = add(new THREE.Mesh(new THREE.CapsuleGeometry(0.35, 1.1, 8, 16), metal), -0.6, 0.9, 1.5);
    const knight2 = add(new THREE.Mesh(new THREE.CapsuleGeometry(0.33, 1.1, 8, 16), dark), 1.6, 0.9, 1.0);
    const head2 = add(new THREE.Mesh(new THREE.SphereGeometry(0.2, 16, 12), dark), 1.6, 1.85, 1.0);
    for (const m of [knight, knight2, head2]) { m.castShadow = true; m.receiveShadow = true; }
    const blade = add(new THREE.Mesh(new THREE.BoxGeometry(0.06, 1.6, 0.01), new THREE.MeshBasicMaterial({ color: new THREE.Color(8, 3, 0.6) })), 0.1, 1.4, 1.5);
    blade.rotation.z = -0.5;
    // braziers: emissive bowls + point lights (the fog scatters them)
    const bowlMat = new THREE.MeshBasicMaterial({ color: new THREE.Color(6, 2.2, 0.5) });
    const braziers = [[-2.6, 1.2, -1.6], [4.2, 1.1, -2.6]];
    lab.fires = braziers.map(([x, y, z]) => {
      add(new THREE.Mesh(new THREE.CylinderGeometry(0.06, 0.08, y, 8), dark), x, y / 2, z);
      add(new THREE.Mesh(new THREE.SphereGeometry(0.16, 12, 8), bowlMat), x, y + 0.08, z);
      const l = new THREE.PointLight(0xff8a3a, 22, 14, 2);
      l.position.set(x, y + 0.4, z);
      scene.add(l);
      return l;
    });
    // a far eclipse: black disc + HDR corona ring (unfogged, depth 150 m: counts as sky for the light shafts)
    const sunDir = new THREE.Vector3(0.08, 0.12, -1).normalize();
    const eclipse = new THREE.Group();
    eclipse.position.copy(sunDir).multiplyScalar(150);
    eclipse.lookAt(0, 0, 0);
    const ringMat = new THREE.MeshBasicMaterial({ color: new THREE.Color(2.4, 2.6, 3.0), fog: false, side: THREE.DoubleSide });
    eclipse.add(new THREE.Mesh(new THREE.RingGeometry(7.6, 9.4, 64), ringMat));
    eclipse.add(new THREE.Mesh(new THREE.CircleGeometry(7.6, 48), new THREE.MeshBasicMaterial({ color: 0x000000, fog: false })));
    scene.add(eclipse);
    ctx.post.setSun(sunDir, [0.8, 0.88, 1.0], 1.2);
    // distortion ring
    const ring = new THREE.Mesh(new THREE.RingGeometry(0.6, 0.9, 48), new THREE.ShaderMaterial({
      transparent: true, blending: THREE.AdditiveBlending, depthTest: false,
      vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }',
      fragmentShader: 'varying vec2 vUv; void main(){ vec2 d = normalize(vUv - 0.5); gl_FragColor = vec4(d * 0.03, 0.0, 1.0); }',
    }));
    ring.position.set(-1.5, 1.3, 1.0);
    ring.visible = false;
    ctx.post.distortionScene.add(ring);
    // soft-particle probe: a camera-facing card crossing the floor, faded with post.DEPTH_GLSL (in-scene depth)
    const card = new THREE.Mesh(new THREE.PlaneGeometry(2.4, 1.2), new THREE.ShaderMaterial({
      transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
      uniforms: { ...ctx.post.depthUniforms },
      vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }',
      fragmentShader: ctx.post.DEPTH_GLSL + 'varying vec2 vUv; void main(){ float r = length(vUv - 0.5) * 2.0; float a = (1.0 - smoothstep(0.2, 1.0, r)) * edSoftFade(0.5); gl_FragColor = vec4(vec3(0.5, 0.7, 1.2) * a, 1.0); }',
    }));
    card.position.set(-0.4, 0.15, 3.2);
    card.visible = false;
    scene.add(card);
    Object.assign(lab, { ring, card, knight, knight2, head2, eclipse });
    ctx._ring = ring;
  },
  scenarios: {
    hit(ctx) { ctx.post.pulse('chroma', 1, { release: 0.4 }); ctx.post.pulse('radial', 0.8, { release: 0.35 }); ctx.post.flash(0xfff2d0, 0.6); },
    impact(ctx) { ctx.post.impactFrame({ duration: 0.1 }); },
    dim(ctx) { ctx.post.to({ exposure: 0.45, saturation: 0.5, letterbox: 1, tint: 0x9fb4ff }, 0.3); },
    reset(ctx) { ctx.post.reset(0.3); ctx.post.dof(null, 0.3); },
    distort(ctx, lab) { lab.ring.visible = true; },
    /** AO / fog / shafts on-off: __ED.lab.play('feature', 'ao', 0) */
    feature(ctx, lab, key, v) { ctx.post.fx[key] = v; },
    /** everything off except tone mapping (before / after reference) */
    bare(ctx) { Object.assign(ctx.post.fx, { ao: 0, fog: 0, shafts: 0 }); ctx.post.grade('neutral', 0.01); },
    full(ctx) { Object.assign(ctx.post.fx, { ao: 1, fog: 1, shafts: 1 }); ctx.post.grade('night', 0.01); },
    thickFog(ctx) { ctx.post.fog({ density: 0.09, falloff: 0.45, haze: 0.012 }, 0.3); },
    dofNear(ctx, lab) { ctx.post.dof({ focus: lab.knight, aperture: 1, range: 0.4 }, 0.3); },
    dofFar(ctx) { ctx.post.dof({ focus: 12, aperture: 1.2, range: 1 }, 0.3); },
    dofOff(ctx) { ctx.post.dof(null, 0.3); },
    grade(ctx, lab, name = 'night') { ctx.post.grade(name, 0.01); },
    softCard(ctx, lab) { lab.card.visible = true; },
    debug(ctx, lab, mode = 'off') { ctx.post.debugView(mode); },
    shadowInfo(ctx) { return ctx.shadows.info; },
    /** spread the stand-in fighters `sep` metres apart (the fitted shadow window follows) */
    moveFighters(ctx, lab, sep = 6) { lab.knight.position.x = -sep / 2; lab.knight2.position.x = sep / 2; lab.head2.position.x = sep / 2; },
  },
});
