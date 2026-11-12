// Meters: HP, FP, ULT and the guard gauge. Discrete changes emit 'meter' events; continuous regeneration does not
// (read fighter.fp / fighter.guard every frame for the HUD).

function meterEvent(m, f, kind, delta) {
  const max = kind === 'hp' ? f.hpMax : kind === 'fp' ? f.fpMax : kind === 'ult' ? f.ultMax : f.guardMax;
  m.emit('meter', { fighter: f.index, kind, value: f[kind], delta, max });
}

/** Lose HP (never below `minHp`). Returns the HP actually lost. */
export function loseHp(m, f, amount, minHp = 0) {
  if (amount <= 0) return 0;
  const before = f.hp;
  f.hp = Math.max(Math.min(minHp, before), before - amount);
  const d = before - f.hp;
  if (d > 0) meterEvent(m, f, 'hp', -d);
  return d;
}

/** Gain ULT (clamped); emits 'ultReady' when the bar fills. */
export function gainUlt(m, f, amount) {
  if (!(amount > 0)) return;
  const before = f.ult;
  f.ult = Math.min(f.ultMax, f.ult + amount);
  if (f.ult === before) return;
  meterEvent(m, f, 'ult', f.ult - before);
  if (before < f.ultMax && f.ult >= f.ultMax) m.emit('ultReady', { fighter: f.index });
}

/** Spend ULT (`all` empties the bar). */
export function spendUlt(m, f, amount, all) {
  const before = f.ult;
  f.ult = all ? 0 : Math.max(0, f.ult - amount);
  if (f.ult !== before) meterEvent(m, f, 'ult', f.ult - before);
}

/** Gain FP (clamped). */
export function gainFp(m, f, amount) {
  if (!(amount > 0)) return;
  const before = f.fp;
  f.fp = Math.min(f.fpMax, f.fp + amount);
  if (f.fp !== before) meterEvent(m, f, 'fp', f.fp - before);
}

/** Spend FP and pause its regeneration for `rules.meters.fpRegenDelay`. */
export function spendFp(m, f, amount) {
  if (!(amount > 0)) return;
  f.fp = Math.max(0, f.fp - amount);
  f.fpRegenWait = m.rules.meters.fpRegenDelay;
  meterEvent(m, f, 'fp', -amount);
}

/** Drain the guard gauge. Returns true when it is empty (guard break). */
export function drainGuard(m, f, amount) {
  if (amount > 0) {
    f.guard = Math.max(0, f.guard - amount);
    meterEvent(m, f, 'guard', -amount);
  }
  f.guardRegenWait = m.rules.meters.guardRegenDelay;
  return f.guard <= 0;
}

/** Refill the guard gauge completely (after a guard break). */
export function refillGuard(m, f) {
  const d = f.guardMax - f.guard;
  f.guard = f.guardMax;
  if (d > 0) meterEvent(m, f, 'guard', d);
}

/** Continuous regeneration for one substep of `h` seconds (fight phase only). */
export function regenMeters(m, f, h) {
  const R = m.rules.meters;
  if (f.fpRegenWait > 0) f.fpRegenWait -= h;
  else if (f.fp < f.fpMax) f.fp = Math.min(f.fpMax, f.fp + R.fpRegen * h);
  if (f.state === 'guardbreak') return;
  if (f.guardRegenWait > 0) { f.guardRegenWait -= h; return; }
  if (f.guard < f.guardMax) {
    const k = f.state === 'guard' || f.state === 'blockstun' ? R.guardRegenWhileGuarding : 1;
    f.guard = Math.min(f.guardMax, f.guard + R.guardRegen * k * h);
  }
}
