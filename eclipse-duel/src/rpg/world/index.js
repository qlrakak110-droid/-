// World dressing of 강호행 (README of src/rpg, §8): the meditation stone 「정심석 靜心石」 and the mist gate.
//   정심석   a low, water-worn boulder on a ring of cairn stones, an incense bowl with a pale wisp of 氣 over it
//   mist gate two knee-high boundary stones with a lamp each and a low bank of mist between them that thins away
//            once the hero has walked through (nothing tall: the fight is never hidden behind the gate)
// A handful of meshes, three materials, no textures; colliders for everything solid.

import * as THREE from 'three';

const PLACES = { altar: { x: -11, z: 6.5, yaw: -0.5 }, heroSpawn: { x: -9.6, z: 5.6, yaw: -0.52 }, gate: { x: -5, z: 2.4, yaw: -0.5, r: 2.6 } };

export default function install(rpg) {
  rpg.world((ctx, world) => {
    const group = new THREE.Group();
    group.name = 'rpg-world';
    const stone = new THREE.MeshStandardMaterial({ color: 0x35373d, roughness: 0.9, metalness: 0.04, flatShading: true });
    const moss = new THREE.MeshStandardMaterial({ color: 0x2c3a2e, roughness: 1, metalness: 0, flatShading: true });
    const bronze = new THREE.MeshStandardMaterial({ color: 0x5d4526, roughness: 0.5, metalness: 0.85 });
    const light = new THREE.MeshBasicMaterial({ color: new THREE.Color(1.2, 2.3, 4.6) });
    const mistMat = new THREE.MeshBasicMaterial({ color: new THREE.Color(0.5, 0.62, 0.8), transparent: true, opacity: 0.12, vertexColors: true, depthWrite: false, side: THREE.DoubleSide, blending: THREE.AdditiveBlending });
    const mats = [stone, moss, bronze, light, mistMat], geos = [];
    let seed = 7;
    const rnd = () => { seed = (seed * 16807) % 2147483647; return seed / 2147483647; };
    /** a boulder: an icosphere pushed around by a little noise, squashed */
    const rock = (r, sx, sy, sz, detail = 1) => {
      const g = new THREE.IcosahedronGeometry(r, detail);
      const p = g.attributes.position;
      for (let i = 0; i < p.count; i++) {
        const x = p.getX(i), y = p.getY(i), z = p.getZ(i);
        const k = 1 + (Math.sin(x * 5.1 + y * 3.3) * Math.cos(z * 4.7 + x * 2.1)) * 0.09;
        p.setXYZ(i, x * k * sx, y * k * sy, z * k * sz);
      }
      g.computeVertexNormals();
      return g;
    };
    const add = (g, m, x, y, z, ry = 0, rz = 0, rx = 0, shadow = true) => {
      geos.push(g);
      const o = new THREE.Mesh(g, m);
      o.position.set(x, y, z); o.rotation.set(rx, ry, rz);
      o.castShadow = shadow; o.receiveShadow = shadow;
      group.add(o);
      return o;
    };

    // ---- 정심석 ----------------------------------------------------------------------------------------------------
    const a = PLACES.altar;
    add(rock(0.95, 1.05, 0.42, 0.9, 2), stone, a.x, 0.26, a.z, 0.4);
    add(rock(0.6, 1.1, 0.16, 1.0, 1), moss, a.x - 0.1, 0.58, a.z + 0.05, 1.1);
    for (let i = 0; i < 7; i++) {
      const an = (i / 7) * Math.PI * 2 + rnd() * 0.5, d = 1.25 + rnd() * 0.35, r = 0.14 + rnd() * 0.14;
      add(rock(r, 1, 0.7, 0.9, 0), stone, a.x + Math.cos(an) * d, r * 0.5, a.z + Math.sin(an) * d, rnd() * 3);
    }
    // a little cairn and the incense bowl
    add(rock(0.2, 1, 0.6, 1, 0), stone, a.x + 0.95, 0.5, a.z - 0.75, 0.3);
    add(rock(0.14, 1, 0.6, 1, 0), stone, a.x + 0.96, 0.68, a.z - 0.74, 1.3);
    add(rock(0.09, 1, 0.7, 1, 0), stone, a.x + 0.95, 0.8, a.z - 0.75, 2.3);
    add(new THREE.CylinderGeometry(0.17, 0.1, 0.14, 10), bronze, a.x - 0.62, 0.66, a.z - 0.3);
    const wisp = add(new THREE.SphereGeometry(0.075, 10, 8), light, a.x - 0.62, 0.95, a.z - 0.3, 0, 0, 0, false);
    const motes = [];
    for (let i = 0; i < 5; i++) motes.push(add(new THREE.SphereGeometry(0.018, 6, 4), light, a.x, 1, a.z, 0, 0, 0, false));

    // ---- the mist gate ---------------------------------------------------------------------------------------------
    const g = PLACES.gate;
    const cs = Math.cos(g.yaw), sn = Math.sin(g.yaw);
    const posts = [];
    // two knee-high boundary stones with a lamp each: low enough that the fight is never hidden behind them
    for (const s of [-1, 1]) {
      const px = g.x + sn * s * (g.r - 0.3), pz = g.z + cs * s * (g.r - 0.3);
      posts.push([px, pz]);
      add(rock(0.42, 1, 0.5, 1, 1), stone, px, 0.12, pz, rnd() * 3);
      add(new THREE.CylinderGeometry(0.2, 0.3, 0.8, 6), stone, px, 0.5, pz, g.yaw + s * 0.3).rotation.set(cs * s * 0.05, g.yaw + s * 0.3, -sn * s * 0.05);
      add(new THREE.CylinderGeometry(0.27, 0.27, 0.07, 6), bronze, px, 0.72, pz, g.yaw + s * 0.3);
      add(new THREE.ConeGeometry(0.3, 0.26, 6), stone, px, 1.04, pz, g.yaw + s * 0.3);
      add(new THREE.SphereGeometry(0.05, 8, 6), light, px, 1.24, pz, 0, 0, 0, false);
      add(rock(0.24, 1.2, 0.5, 1, 0), moss, px + cs * 0.45, 0.1, pz - sn * 0.45 * s, rnd() * 3);
    }
    const veils = [];
    for (let i = 0; i < 6; i++) {
      const vg = new THREE.PlaneGeometry((g.r - 0.5) * 2, 1.5, 8, 4);
      {
        // soft edges: additive vertex colours fall to black at the rim, drifting bands inside
        const p = vg.attributes.position, c = new Float32Array(p.count * 3), W = (g.r - 0.5) * 2;
        for (let k = 0; k < p.count; k++) {
          const u = p.getX(k) / W + 0.5, w = p.getY(k) / 1.5 + 0.5;
          const b = Math.pow(Math.sin(Math.PI * u), 1.6) * Math.pow(Math.sin(Math.PI * Math.min(1, w * 1.1)), 1.4) * (0.55 + 0.45 * Math.sin(u * 9 + i * 2.1 + w * 4));
          c[k * 3] = c[k * 3 + 1] = c[k * 3 + 2] = Math.max(0, b);
        }
        vg.setAttribute('color', new THREE.BufferAttribute(c, 3));
      }
      const v = add(vg, mistMat, g.x + cs * (i - 2.5) * 0.2, 0.72, g.z - sn * (i - 2.5) * 0.2, g.yaw + Math.PI / 2, 0, 0, false);
      v.renderOrder = 12;
      veils.push(v);
    }

    ctx.scene.add(group);
    const removers = [
      world.addCollider({ type: 'circle', x: a.x, z: a.z, r: 0.95 }),
      ...posts.map(([px, pz]) => world.addCollider({ type: 'circle', x: px, z: pz, r: 0.42, blocksCamera: false })),
    ];
    let t = 0, open = 0, passed = false;
    const off = world.on('gate', () => { passed = true; });
    const offRest = world.on('heroRest', () => { passed = false; });

    return {
      altar: PLACES.altar, heroSpawn: PLACES.heroSpawn, gate: PLACES.gate,
      update(dtGame) {
        t += dtGame;
        const st = world.flow ? world.flow.state : '';
        open += ((passed || st === 'encounter' || st === 'boss' || st === 'victory' ? 1 : 0) - open) * Math.min(1, dtGame * 1.2);
        wisp.position.y = 0.95 + Math.sin(t * 1.3) * 0.05;
        wisp.scale.setScalar(1 + Math.sin(t * 3.1) * 0.12);
        for (let i = 0; i < motes.length; i++) {
          const ph = t * (0.35 + i * 0.07) + i * 1.9, r = 0.9 + 0.5 * Math.sin(ph * 0.7 + i);
          motes[i].position.set(a.x + Math.cos(ph) * r, 0.9 + 0.5 * Math.sin(ph * 1.3 + i) + i * 0.12, a.z + Math.sin(ph) * r);
        }
        mistMat.opacity = 0.1 * (1 - open) * (0.85 + 0.15 * Math.sin(t * 0.9));
        for (let i = 0; i < veils.length; i++) veils[i].visible = open < 0.98;
        for (let i = 0; i < veils.length; i++) veils[i].position.y = 0.72 + Math.sin(t * 0.5 + i * 1.3) * 0.08;
      },
      dispose() {
        off(); offRest();
        for (const r of removers) r();
        group.removeFromParent();
        for (const x of geos) x.dispose();
        for (const m of mats) m.dispose();
      },
    };
  });
}
