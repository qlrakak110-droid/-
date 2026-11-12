// VORN variants of the generic reaction / knockdown clips (src/game/clips.js game.*): the same motion with VORN's spear
// grip (the 42 deg tilt of the spear in the fist + the choke grip point), so every state the rules can put him in holds
// the spear the way his own clips do and a fade between them never rolls the spear in the fist.
//   vorn.guardBreak vorn.crumple vorn.launched vorn.fall vorn.down vorn.getup vorn.tech vorn.ko vorn.locked

import { defineClip } from '../../../char/index.js';
import { getClipDef, getPoseDef } from '../../../char/anim.js';
import '../../../game/clips.js';
import { GRIP_TILT, sp } from './common.js';

/** A generic key re-expressed with VORN's grip: poses expanded, spear-hand aims (+ `lift`) turned into the tilted fist frame. */
function tiltKey(k, lift) {
  let key = k;
  if (k.pose) {
    const p = getPoseDef(k.pose === 'demo.stance' || k.pose === 'demo.low' ? 'vorn.stance' : k.pose) || {};
    key = { ...p, ...k, bones: { ...(p.bones || {}), ...(k.bones || {}) }, ik: { ...(p.ik || {}), ...(k.ik || {}) }, hips: k.hips || p.hips };
    delete key.pose;
    if (!key.hips) delete key.hips;
  }
  const out = { ...key, bones: { ...(key.bones || {}), weaponR: [0, 0, -GRIP_TILT] } };
  let h = key.ik && key.ik.handR;
  if (h && h.aim && lift) h = { ...h, aim: h.aim.map((x, i) => x + lift[i]) };
  if (h && h.aim) out.ik = { ...key.ik, handR: { ...h, ...sp(h.pos, h.aim, { up: h.up }), ...(h.space ? { space: h.space } : {}), ...(h.w !== undefined ? { w: h.w } : {}) } };
  if (h && !h.pos && out.ik && out.ik.handR) delete out.ik.handR.pos;
  return out;
}

/** `lift` (chest-frame vector) is added to the spear aim of every key: lying poses keep the spear off the floor. */
function variant(dst, src, lift) {
  const d = getClipDef(src);
  if (!d) return;
  defineClip(dst, { ...d, gripAt: 'choke', base: 'vorn.stance', keys: d.keys.map((k) => tiltKey(k, lift)) });
}

variant('vorn.guardBreak', 'game.guardbreak');
variant('vorn.crumple', 'game.crumple');
variant('vorn.launched', 'game.airRise');
variant('vorn.fall', 'game.airFall');
variant('vorn.down', 'game.down', [0.24, 0, 0]);
variant('vorn.getup', 'game.getup');
variant('vorn.tech', 'game.getup');
variant('vorn.ko', 'game.koDown', [0.24, 0, 0]);
variant('vorn.locked', 'game.locked');
