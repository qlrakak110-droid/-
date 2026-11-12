// EffectPool: the pooled-effect base. A fixed number of slots (allocated once), each with a birth time on the game or
// real clock, a lifetime, an optional follow target and a generation serial so stale handles never touch a reused slot.
// Allocation takes a free slot or steals the oldest one. Modules keep their GPU data per slot (an instance in an
// InstanceRing, a pooled Mesh ...) and use pool.forEach() each frame to update live slots and free expired ones.
//
//   const pool = new EffectPool(shared, 32, (i) => ({ mesh: makeMesh(i) }));
//   const { slot, handle } = pool.alloc({ life: 0.6, realtime: false });
//   pool.forEach((slot, age, t) => { ... }, (slot) => { /* freed: hide it */ });

import * as THREE from 'three';
import { toVec3 } from './util.js';

export class EffectPool {
  /**
   * @param {object} shared    vfx shared resources (needs clock, track)
   * @param {number} capacity  number of slots
   * @param {(i:number) => object} make  per-slot user data factory (merged into the slot)
   */
  constructor(shared, capacity, make = () => ({})) {
    this.shared = shared;
    this.clock = shared.clock;
    this.slots = [];
    for (let i = 0; i < capacity; i++) {
      this.slots.push(Object.assign({ i, live: false, t0: 0, life: 0, realtime: false, serial: 0, stopping: false, stopT: 0, follow: null, offset: new THREE.Vector3(), pos: new THREE.Vector3() }, make(i)));
    }
    this.serial = 1;
    this.live = 0;
  }

  /** Age of a slot in seconds on its clock. */
  age(s) { return (s.realtime ? this.clock.real : this.clock.game) - s.t0; }

  /**
   * Take a slot: { life (s, Infinity = until stop/kill), realtime, last }. Returns { slot, handle }. The handle has
   * alive, kill(), stop(), follow(target, offset?) and is tracked into the running preset group.
   * Extend the handle with module-specific methods before returning it.
   */
  alloc({ life = 1, realtime = false, last = false } = {}) {
    let s = null;
    const sl = this.slots;
    // `last`: take the highest free slot (drawn after the others in an instanced layer: occluders such as the eclipse disc)
    if (last) { for (let i = sl.length - 1; i >= 0; i--) if (!sl[i].live) { s = sl[i]; break; } } else for (const x of sl) if (!x.live) { s = x; break; }
    if (!s) { s = this.slots[0]; for (const x of this.slots) if (x.t0 < s.t0) s = x; this._free(s); }
    s.live = true;
    this.live++;
    s.realtime = realtime;
    s.t0 = realtime ? this.clock.real : this.clock.game;
    s.life = life;
    s.stopping = false;
    s.follow = null;
    s.offset.set(0, 0, 0);
    s.serial = this.serial++;
    const my = s.serial, pool = this;
    const handle = {
      slot: s,
      get alive() { return s.live && s.serial === my; },
      kill() { if (s.live && s.serial === my) pool._free(s); },
      stop() { if (s.live && s.serial === my && !s.stopping) { s.stopping = true; s.stopT = pool.age(s); } },
      follow(target, offset) { if (s.serial === my) { s.follow = target; if (offset) toVec3(offset, s.offset); pool.place(s); } return handle; },
    };
    this.shared.track(handle);
    return { slot: s, handle };
  }

  /** Update a following slot's `pos` from its target (Object3D: offset is local to it; else world offset). */
  place(s) {
    const f = s.follow;
    if (!f) return false;
    if (f.isObject3D) { f.updateWorldMatrix(true, false); s.pos.copy(s.offset).applyMatrix4(f.matrixWorld); }
    else toVec3(f, s.pos).add(s.offset);
    return true;
  }

  _free(s) {
    if (!s.live) return;
    s.live = false;
    s.serial = 0;
    this.live--;
    if (this.onFree) this.onFree(s);
  }

  /**
   * Visit live slots: fn(slot, age, t) with t = age / life (0 for infinite lives). Slots whose age reaches their life
   * are freed first (onFree is called). Set pool.onFree = (slot) => {} to hide freed instances.
   */
  forEach(fn) {
    for (const s of this.slots) {
      if (!s.live) continue;
      const age = this.age(s);
      if (age >= s.life) { this._free(s); continue; }
      fn(s, age, Number.isFinite(s.life) ? age / s.life : 0);
    }
  }

  /** Free every slot. */
  clear() { for (const s of this.slots) this._free(s); }
}
