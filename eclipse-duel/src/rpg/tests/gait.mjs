// Gait check (no rendering): each hero runs and sprints in a straight line at full speed; while a foot sole is on the
// floor (socket height < 1.2 cm: the planted phase proper) its world position must not move. Prints the worst slide per contact and the mean
// slip speed, plus the automatic pelvis drop and the planted-foot IK error of the rig (char.diag).
//
//   node tools/shot.mjs game --as rpg-core --size 320x180 --scenario src/rpg/tests/gait.mjs

export default async ({ page, evalJs, log }) => {
  const heroes = (process.env.HEROES || 'kael,iska,vorn').split(',');
  for (const hero of heroes) {
    await evalJs(`__ED.rpg.start('${hero}', { sandbox: true })`);
    const res = await page.evaluate(() => {
      const ED = window.__ED, ctx = ED.ctx, r = ED.rpg, THREE = ED.THREE;
      r.clear();
      const out = {};
      const v = new THREE.Vector3();
      for (const gait of ['run', 'sprint']) {
        r.tp(-12, 0, 0);
        r.give({ stamina: true });
        r.move(0, 1);
        if (gait === 'sprint') ctx.input.setVirtual('dodge', true, 0);
        const w = r.world(), h = w.hero;
        for (let i = 0; i < 45; i++) { ctx.frame(1 / 60, false); if (gait === 'sprint') h.stamina = h.staminaMax; }
        const feet = { footL: null, footR: null };
        let worst = 0, slip = 0, n = 0, contacts = 0, drop = 0, footErr = 0, minY = 1, maxStride = 0;
        const last = { footL: null, footR: null };
        for (let i = 0; i < 150; i++) {
          ctx.frame(1 / 60, false);
          if (gait === 'sprint') h.stamina = h.staminaMax;
          const d = h.char.diag;
          if (d) { drop = Math.max(drop, d.drop || 0); footErr = Math.max(footErr, d.footErr || 0); }
          for (const f of ['footL', 'footR']) {
            h.char.sockets[f].getWorldPosition(v);
            minY = Math.min(minY, v.y);
            if (v.y < 0.012) {
              if (!feet[f]) { feet[f] = { x: v.x, z: v.z }; contacts++; if (last[f]) maxStride = Math.max(maxStride, Math.hypot(v.x - last[f].x, v.z - last[f].z)); last[f] = { x: v.x, z: v.z }; }
              const dd = Math.hypot(v.x - feet[f].x, v.z - feet[f].z);
              worst = Math.max(worst, dd);
              slip += dd; n++;
            } else feet[f] = null;
          }
        }
        ctx.input.setVirtual('dodge', false, 0);
        r.move(0, 0);
        for (let i = 0; i < 40; i++) ctx.frame(1 / 60, false);
        out[gait] = { speed: +h.moveSpeed.toFixed(2), gaitSeen: h.gait, worstSlideCm: +(worst * 100).toFixed(1), meanCm: +((slip / Math.max(1, n)) * 100).toFixed(2), contacts, strideM: +maxStride.toFixed(2),
          pelvisDropCm: +(drop * 100).toFixed(1), footErrCm: +(footErr * 100).toFixed(1), minFootY: +minY.toFixed(3), plantedFrames: n };
      }
      return out;
    });
    log(`${hero} run    ${JSON.stringify(res.run)}`);
    log(`${hero} sprint ${JSON.stringify(res.sprint)}`);
  }
};
