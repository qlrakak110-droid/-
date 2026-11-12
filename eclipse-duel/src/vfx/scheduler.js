// Deferred callbacks on the game clock (honours hit-stop and slow motion) or, with { realtime: true }, on real time.
// A callback scheduled while a preset runs belongs to that preset's group: group.kill() cancels it, and when it fires
// it runs inside the same group so whatever it spawns is killed with the group too.

/**
 * @param {object} vfx
 * @param {object} shared
 */
export function installScheduler(vfx, shared) {
  const { clock } = shared;
  const list = [];

  /**
   * Run fn after `delay` game-seconds (or real seconds with opts.realtime). Returns { cancel(), kill(), alive }.
   */
  function schedule(delay, fn, opts = {}) {
    const realtime = !!opts.realtime;
    const e = { at: (realtime ? clock.real : clock.game) + Math.max(0, delay), fn, realtime, group: shared.currentGroup(), dead: false };
    const h = {
      get alive() { return !e.dead; },
      cancel() { e.dead = true; },
      kill() { e.dead = true; },
      stop() {},
    };
    e.handle = h;
    list.push(e);
    shared.track(h);
    return h;
  }

  function update() {
    // callbacks may schedule more callbacks: loop until nothing due remains (new zero-delay entries run this frame)
    for (let guard = 0; guard < 8; guard++) {
      let ran = false;
      for (let i = 0; i < list.length; i++) {
        const e = list[i];
        if (e.dead) { list.splice(i--, 1); continue; }
        if ((e.realtime ? clock.real : clock.game) + 1e-9 < e.at) continue;
        list.splice(i--, 1);
        e.dead = true;
        shared.runInGroup(e.group, e.fn);
        ran = true;
      }
      if (!ran) break;
    }
  }

  return {
    name: 'scheduler',
    api: { schedule },
    update,
    clear() { for (const e of list) e.dead = true; list.length = 0; },
  };
}
