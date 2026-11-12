// Game clock with hit-stop and slow-motion.
//   real time  : wall clock (UI, camera shake, post pulses)
//   game time  : real time * scale, frozen during hit-stop (fighters, animation, most VFX)

import { clamp, lerp } from './math.js';

export class Time {
  constructor() {
    this.real = 0;      // seconds since start (real)
    this.game = 0;      // seconds since start (game)
    this.dtReal = 0;
    this.dtGame = 0;
    this.scale = 1;     // effective time scale this frame (0 during hit-stop)
    this.baseScale = 1; // persistent scale (pause = 0, training slow = 0.5 ...)
    this.frame = 0;
    this._hitstop = 0;
    this._slow = [];
  }

  /** Freeze game time for `sec` real seconds (does not stack: keeps the longer one). */
  hitstop(sec) {
    if (sec > this._hitstop) this._hitstop = sec;
  }

  /**
   * Slow motion: game time runs at `scale` for `dur` real seconds, easing in/out. Multiple requests: the slowest wins.
   * Returns a handle with cancel().
   */
  slowmo(scale, dur, { easeIn = 0.0, easeOut = 0.25 } = {}) {
    const s = { scale, t: 0, dur, easeIn, easeOut, dead: false };
    this._slow.push(s);
    return { cancel: () => { s.dead = true; } };
  }

  get inHitstop() { return this._hitstop > 0; }

  tick(dtReal) {
    this.dtReal = dtReal;
    this.real += dtReal;
    this.frame++;
    let scale = this.baseScale;
    for (let i = this._slow.length - 1; i >= 0; i--) {
      const s = this._slow[i];
      s.t += dtReal;
      if (s.dead || s.t >= s.dur) { this._slow.splice(i, 1); continue; }
      let k = 1;
      if (s.easeIn > 0 && s.t < s.easeIn) k = s.t / s.easeIn;
      const left = s.dur - s.t;
      if (s.easeOut > 0 && left < s.easeOut) k = Math.min(k, left / s.easeOut);
      scale = Math.min(scale, lerp(1, s.scale, clamp(k)));
    }
    if (this._hitstop > 0) {
      this._hitstop -= dtReal;
      scale = 0;
    }
    this.scale = scale;
    this.dtGame = dtReal * scale;
    this.game += this.dtGame;
  }
}
