// Event stream of a match. Events raised while the match steps are queued and dispatched once the step has finished,
// so listeners never observe (or mutate) a half-resolved simulation, and a throwing listener cannot corrupt it.

/** Subscription aliases: CONTRACT.md calls timeline markers 'moveEvent'; they are emitted as 'marker'. */
const ALIASES = { moveEvent: 'marker' };

/**
 * @returns {{on: Function, off: Function, has: Function, push: Function, flush: Function, clear: Function}}
 *   on(name | '*', fn) -> off()   fn(payload) for a name, fn(name, payload) for '*'
 *   has(name)                     true if anybody listens to `name` (or to '*')
 *   push(name, payload)           queue an event
 *   flush()                       dispatch the queue (returns the number of events dispatched)
 */
export function createEventQueue() {
  const map = new Map();
  const any = [];
  let queue = [];
  const remove = (arr, fn) => { const i = arr.indexOf(fn); if (i >= 0) arr.splice(i, 1); };
  return {
    on(name, fn) {
      if (name === '*') { any.push(fn); return () => remove(any, fn); }
      if (ALIASES[name]) name = ALIASES[name];
      let a = map.get(name);
      if (!a) map.set(name, (a = []));
      a.push(fn);
      return () => remove(a, fn);
    },
    off(name, fn) {
      if (ALIASES[name]) name = ALIASES[name];
      if (name === '*') remove(any, fn);
      else if (map.has(name)) remove(map.get(name), fn);
    },
    has(name) {
      if (any.length) return true;
      const a = map.get(name);
      return !!(a && a.length);
    },
    push(name, payload) {
      queue.push(name, payload);
    },
    flush() {
      if (!queue.length) return 0;
      const q = queue;
      queue = [];
      let firstError = null;
      for (let i = 0; i < q.length; i += 2) {
        const name = q[i], payload = q[i + 1];
        const a = map.get(name);
        if (a) for (const fn of a.slice()) { try { fn(payload); } catch (e) { if (!firstError) firstError = e; } }
        for (const fn of any.slice()) { try { fn(name, payload); } catch (e) { if (!firstError) firstError = e; } }
      }
      if (firstError) throw firstError;
      return q.length / 2;
    },
    clear() { queue = []; },
  };
}
