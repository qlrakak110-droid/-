// Debug overlay of the RPG combat volumes (`#rpgdebug`, `world.debugShapes(true)`): body cylinders (white: free,
// cyan: invulnerable, yellow: guarding), live hit shapes of every running attack (red while active, dim red while
// winding up), hurt spheres, projectiles, static colliders (grey) and triggers (green). One LineSegments, rebuilt
// every frame; costs nothing while it is off.

import * as THREE from 'three';
import { fwdX, fwdZ, rightX, rightZ } from './math3.js';

const MAX = 12000;

/**
 * @param {object} ctx
 * @param {object} world
 * @returns {{ set(on: boolean): void, update(): void, dispose(): void, on: boolean }}
 */
export function createDebugShapes(ctx, world) {
  let mesh = null, pos = null, col = null, n = 0;
  const V = new THREE.Vector3(), W = new THREE.Vector3();
  const api = { on: false, set, update, dispose };

  function ensure() {
    if (mesh) return;
    const g = new THREE.BufferGeometry();
    pos = new Float32Array(MAX * 3); col = new Float32Array(MAX * 3);
    g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    g.setAttribute('color', new THREE.BufferAttribute(col, 3));
    mesh = new THREE.LineSegments(g, new THREE.LineBasicMaterial({ vertexColors: true, depthTest: false, transparent: true }));
    mesh.frustumCulled = false;
    mesh.renderOrder = 999;
    mesh.name = 'rpg-debug-shapes';
    ctx.scene.add(mesh);
  }
  function set(on) {
    api.on = !!on;
    if (on) ensure();
    if (mesh) mesh.visible = api.on;
  }
  function line(x0, y0, z0, x1, y1, z1, c) {
    if (n + 2 > MAX) return;
    let k = n * 3;
    pos[k] = x0; pos[k + 1] = y0; pos[k + 2] = z0; col[k] = c[0]; col[k + 1] = c[1]; col[k + 2] = c[2];
    k += 3;
    pos[k] = x1; pos[k + 1] = y1; pos[k + 2] = z1; col[k] = c[0]; col[k + 1] = c[1]; col[k + 2] = c[2];
    n += 2;
  }
  function circle(x, y, z, r, c, seg = 20, a0 = 0, a1 = Math.PI * 2, yaw = 0) {
    let px = 0, pz = 0;
    for (let i = 0; i <= seg; i++) {
      const a = a0 + ((a1 - a0) * i) / seg;
      // angle a measured from the actor's forward toward its right
      const cx = x + r * (Math.cos(a) * fwdX(yaw) + Math.sin(a) * rightX(yaw)), cz = z + r * (Math.cos(a) * fwdZ(yaw) + Math.sin(a) * rightZ(yaw));
      if (i > 0) line(px, y, pz, cx, y, cz, c);
      px = cx; pz = cz;
    }
  }
  function cylinder(x, z, r, y0, y1, c) {
    circle(x, y0 + 0.02, z, r, c, 16); circle(x, y1, z, r, c, 16);
    for (let i = 0; i < 4; i++) { const a = i * Math.PI * 0.5; line(x + Math.cos(a) * r, y0, z + Math.sin(a) * r, x + Math.cos(a) * r, y1, z + Math.sin(a) * r, c); }
  }
  function sphere(p, r, c) {
    circle(p.x, p.y, p.z, r, c, 16);
    for (let i = 0; i < 16; i++) {
      const a = (i / 16) * Math.PI * 2, b = ((i + 1) / 16) * Math.PI * 2;
      line(p.x + Math.cos(a) * r, p.y + Math.sin(a) * r, p.z, p.x + Math.cos(b) * r, p.y + Math.sin(b) * r, p.z, c);
      line(p.x, p.y + Math.sin(a) * r, p.z + Math.cos(a) * r, p.x, p.y + Math.sin(b) * r, p.z + Math.cos(b) * r, c);
    }
  }
  function shape(a, s, c, t, t0) {
    const y0 = a.pos.y + (s.u0 || 0), y1 = a.pos.y + (s.u1 || 0);
    switch (s.type) {
      case 'arc': {
        for (const y of [y0 + 0.02, y1]) {
          circle(a.pos.x, y, a.pos.z, s.r1, c, 24, s.a0, s.a1, a.yaw);
          if (s.r0 > 0.05) circle(a.pos.x, y, a.pos.z, s.r0, c, 12, s.a0, s.a1, a.yaw);
          if (s.a1 - s.a0 < Math.PI * 2 - 0.01) for (const ang of [s.a0, s.a1]) {
            const dx = Math.cos(ang) * fwdX(a.yaw) + Math.sin(ang) * rightX(a.yaw), dz = Math.cos(ang) * fwdZ(a.yaw) + Math.sin(ang) * rightZ(a.yaw);
            line(a.pos.x + dx * s.r0, y, a.pos.z + dz * s.r0, a.pos.x + dx * s.r1, y, a.pos.z + dz * s.r1, c);
          }
        }
        break;
      }
      case 'box': {
        const P = [[s.f0, s.s0], [s.f1, s.s0], [s.f1, s.s1], [s.f0, s.s1]];
        for (const y of [y0 + 0.02, y1]) for (let i = 0; i < 4; i++) {
          const p = P[i], q = P[(i + 1) % 4];
          a.at(p[0], 0, p[1], V); a.at(q[0], 0, q[1], W);
          line(V.x, y, V.z, W.x, y, W.z, c);
        }
        break;
      }
      case 'ring': {
        a.at(s.at[0], 0, s.at[2], V);
        const k = Math.max(0, t - t0);
        circle(V.x, y0 + 0.03, V.z, s.r0 + s.g0 * k, c, 28); circle(V.x, y0 + 0.03, V.z, s.r1 + s.g1 * k, c, 28);
        circle(V.x, y1, V.z, s.r1 + s.g1 * k, c, 28);
        break;
      }
      case 'sphere':
        if (s.socket) a.socket(s.socket, V); else a.at(s.at[0], s.at[1], s.at[2], V);
        sphere(V, s.r * (s.socket ? a.scale : 1), c);
        break;
      case 'capsule': {
        const pa = typeof s.a === 'string' ? a.socket(s.a, V) : a.at(s.a[0], s.a[1], s.a[2], V);
        const pb = typeof s.b === 'string' ? a.socket(s.b, W) : a.at(s.b[0], s.b[1], s.b[2], W);
        line(pa.x, pa.y, pa.z, pb.x, pb.y, pb.z, c); sphere(pa, s.r, c); sphere(pb, s.r, c);
        break;
      }
      default:
    }
  }
  const C = { body: [0.9, 0.9, 0.9], inv: [0.2, 0.9, 1], guard: [1, 0.9, 0.2], hit: [1, 0.15, 0.1], wind: [0.45, 0.12, 0.1], hurt: [1, 0.5, 0.9], weak: [1, 1, 0.3], col: [0.5, 0.5, 0.55], trig: [0.2, 0.9, 0.3], proj: [1, 0.6, 0.1] };

  function update() {
    if (!api.on || !mesh) return;
    n = 0;
    for (const a of world.actors) {
      if (a.gone) continue;
      cylinder(a.pos.x, a.pos.z, a.radius, a.pos.y, a.pos.y + a.height, a.invuln ? C.inv : a.guarding ? C.guard : C.body);
      line(a.pos.x, a.pos.y + 0.05, a.pos.z, a.pos.x + fwdX(a.yaw) * (a.radius + 0.4), a.pos.y + 0.05, a.pos.z + fwdZ(a.yaw) * (a.radius + 0.4), C.body);
      if (a.spec.hurt) for (const h of a.spec.hurt) { if (h.socket) a.socket(h.socket, V); else a.at(h.at[0], h.at[1], h.at[2], V); sphere(V, h.r * (h.socket ? a.scale : 1), h.weak ? C.weak : C.hurt); }
      const inst = a.attack;
      if (inst) for (const h of inst.def.hits) {
        const active = inst.t >= h.t0 && inst.t <= h.t1 + 1 / 60;
        if (active || inst.t < h.t0) shape(a, h.shape, active ? C.hit : C.wind, inst.t, h.t0);
      }
    }
    for (const p of world.projectiles.list) cylinder(p.x, p.z, p.radius, p.y + p.h0, p.y + p.h1, p.armed ? C.proj : C.wind);
    for (const c of world.colliders) {
      if (c.type === 'circle') circle(c.x, 0.03, c.z, c.r, C.col, 20);
      else { const cs = Math.cos(c.yaw), sn = Math.sin(c.yaw); const P = [[-c.hx, -c.hz], [c.hx, -c.hz], [c.hx, c.hz], [-c.hx, c.hz]].map(([x, z]) => [c.x + x * cs + z * sn, c.z - x * sn + z * cs]); for (let i = 0; i < 4; i++) line(P[i][0], 0.03, P[i][1], P[(i + 1) % 4][0], 0.03, P[(i + 1) % 4][1], C.col); }
    }
    for (const t of world.triggers) circle(t.x, 0.03, t.z, t.r, C.trig, 24);
    circle(0, 0.03, 0, world.arena.radius, C.col, 64);
    const g = mesh.geometry;
    g.setDrawRange(0, n);
    g.attributes.position.needsUpdate = true;
    g.attributes.color.needsUpdate = true;
  }
  function dispose() {
    if (!mesh) return;
    mesh.removeFromParent(); mesh.geometry.dispose(); mesh.material.dispose();
    mesh = null;
  }
  return api;
}
