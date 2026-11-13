// Cut-based cinematics for 강호행: a list of shots played as one world-space camera take (src/rpg/camera.js worldShot),
// with hard cuts between shots, letterbox bars and optional depth of field, then a blend back to the follow camera.
//
//   sequence(ctx, world, [{ dur, frame(e, out, u) }, ...], { clock: 'game' | 'real', blendOut, dof, letterbox, onDone })
//     frame(e, out, u)   e = eased 0..1 inside the shot (u = linear): write out.pos, out.look (Vector3) and out.fov
//   around(actor)        -> (f, u, s, out) => world point in the actor's frame (forward, up, right; metres)

import * as THREE from 'three';

export function around(a) {
  const yaw = a.yaw, x = a.pos.x, z = a.pos.z, fx = Math.cos(yaw), fz = -Math.sin(yaw), rx = Math.sin(yaw), rz = Math.cos(yaw);
  return (f, u, s, out) => out.set(x + fx * f + rx * s, u, z + fz * f + rz * s);
}

export function sequence(ctx, world, shots, o = {}) {
  const cam = world.camera;
  if (!cam || !cam.worldShot || !shots.length) return null;
  const starts = [];
  let total = 0;
  for (const s of shots) { starts.push(total); total += s.dur; }
  const bars = o.letterbox !== false && ctx.cam && ctx.cam.letterbox;
  const dof = o.dof && ctx.post && ctx.post.dof;
  if (bars) ctx.cam.letterbox(true, 0.25);
  if (dof) ctx.post.dof(o.dof, 0.3);
  let ended = false;
  const done = (completed) => {
    if (ended) return;
    ended = true;
    if (bars) ctx.cam.letterbox(false, 0.5);
    if (dof) ctx.post.dof(null, 0.4);
    if (o.onDone) o.onDone(completed);
  };
  return cam.worldShot((t, out) => {
    let k = shots.length - 1;
    while (k > 0 && t < starts[k]) k--;
    const s = shots[k], u = Math.min(1, Math.max(0, (t - starts[k]) / s.dur));
    s.frame(u * u * (3 - 2 * u), out, u);
  }, { dur: total, blendOut: o.blendOut ?? 0.8, clock: o.clock || 'game', onDone: done });
}

export const V3 = () => new THREE.Vector3();
