// Stand-in world dressing used until src/rpg/world registers the real one (README §8): a plain altar plinth with a
// starlit bowl and two leaning stones marking the mist gate. A handful of meshes, 2 materials, no textures.

import * as THREE from 'three';

/**
 * @param {object} ctx
 * @param {object} world
 * @param {object} places resolved { altar, gate, heroSpawn }
 * @returns {{ update(dtGame: number, dtReal: number): void, dispose(): void }}
 */
export function createStandinWorld(ctx, world, places) {
  const group = new THREE.Group();
  group.name = 'rpg-standin-world';
  const stone = new THREE.MeshStandardMaterial({ color: 0x3b3d44, roughness: 0.86, metalness: 0.05 });
  const light = new THREE.MeshBasicMaterial({ color: new THREE.Color(1.4, 2.4, 5.2) });
  const geos = [];
  const mesh = (g, m, x, y, z, ry = 0, rz = 0) => { geos.push(g); const o = new THREE.Mesh(g, m); o.position.set(x, y, z); o.rotation.set(0, ry, rz); o.castShadow = m === stone; o.receiveShadow = m === stone; group.add(o); return o; };
  const a = places.altar;
  mesh(new THREE.CylinderGeometry(0.72, 0.86, 0.5, 10), stone, a.x, 0.25, a.z);
  mesh(new THREE.CylinderGeometry(0.42, 0.6, 0.42, 10), stone, a.x, 0.71, a.z);
  const bowl = mesh(new THREE.SphereGeometry(0.2, 10, 8), light, a.x, 1.08, a.z);
  const g = places.gate;
  const cs = Math.cos(g.yaw), sn = Math.sin(g.yaw);
  // posts to the left / right of the road direction (the gate's forward)
  for (const s of [-1, 1]) {
    const px = g.x + sn * s * (g.r - 0.35), pz = g.z + cs * s * (g.r - 0.35);
    mesh(new THREE.BoxGeometry(0.5, 2.9, 0.62), stone, px, 1.4, pz, g.yaw + s * 0.2, s * 0.07);
    mesh(new THREE.SphereGeometry(0.09, 8, 6), light, px, 2.95, pz);
  }
  ctx.scene.add(group);
  const removers = [
    ...[-1, 1].map((s) => world.addCollider({ type: 'circle', x: g.x + sn * s * (g.r - 0.35), z: g.z + cs * s * (g.r - 0.35), r: 0.42 })),
  ];
  let t = 0;
  return {
    update(dtGame) { t += dtGame; bowl.position.y = 1.08 + Math.sin(t * 1.3) * 0.04; },
    dispose() {
      for (const r of removers) r();
      group.removeFromParent();
      for (const x of geos) x.dispose();
      stone.dispose(); light.dispose();
    },
  };
}
