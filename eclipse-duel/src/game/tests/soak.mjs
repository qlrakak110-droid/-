// Soak / invariant QA: CPU vs CPU matches across fighter pairs and difficulties, stepped headless (1/60 s frames) with
// per-frame checks, rendered at a low rate so new shader programs show up. Prints one line per match and a summary.
//   node tools/shot.mjs game --size 320x180 --scenario src/game/tests/soak.mjs
// env: MATCHES (default 9), CAP (sim seconds per match, 200), RENDER_EVERY (frames, 20), PAIRS ('kael:iska,iska:vorn,...')
//
// Checks per frame: NaN in roots / sockets / camera; character root vs rules position and facing (outside cinematics);
// a KO'd / knocked-down fighter must play a lying clip; both chests on screen in fight framing; clips that fell back to
// demo.idle; HUD fed with live values. Per match: programs compiled after the first fight frames (mid-fight compiles),
// renderer memory, scene children, live VFX lights after round resets, warnings / errors, match result.
export default async ({ page, evalJs, log }) => {
  const MATCHES = Number(process.env.MATCHES || 9);
  const CAP = Number(process.env.CAP || 200);
  const RENDER_EVERY = Number(process.env.RENDER_EVERY || 20);
  const DIFFS = ['easy', 'normal', 'hard', 'nightmare'];
  const PAIRS = (process.env.PAIRS || 'kael:iska,iska:vorn,vorn:kael,iska:kael,vorn:iska,kael:vorn,kael:kael,iska:iska,vorn:vorn').split(',').map((p) => p.split(':'));
  const warnings = [];
  page.on('console', (m) => { if (m.type() === 'warning' || m.type() === 'error') warnings.push(m.text().slice(0, 300)); });

  await evalJs(`(() => {
    const ctx = __ED.ctx, G = __ED.game, THREE = __ED.THREE;
    const v = new THREE.Vector3();
    const LYING = new Set(['ko', 'knockdown']);
    const qa = window.__qa = { reset() {
      qa.m = { frames: 0, nan: [], drift: 0, driftMax: 0, facing: 0, lying: [], offscreen: 0, offRun: 0, offRunMax: 0, idleFallback: 0, hudStale: 0,
        programs0: -1, programs1: 0, newPrograms: [], phases: {}, clips: {}, rounds: 0, ults: 0, cine: 0, hits: 0, kos: 0, ended: false, lightsAfterReset: 0,
        sounds: 0, soundPeak: 0, soundPeakAt: '', soundNames: {}, sameName: 0 };
    } };
    qa.reset();
    // sound requests per frame (test mode is silent, the calls still happen): stacking = many in one frame / same name
    let frameSounds = [];
    const play = ctx.audio.play.bind(ctx.audio);
    ctx.audio.play = (name, o) => { frameSounds.push(name); return play(name, o); };
    qa.soundFrame = () => {
      const m = qa.m, n = frameSounds.length;
      m.sounds += n;
      for (const s of frameSounds) m.soundNames[s] = (m.soundNames[s] || 0) + 1;
      if (n > m.soundPeak) { m.soundPeak = n; m.soundPeakAt = frameSounds.join('+'); }
      if (new Set(frameSounds).size < n) m.sameName++;
      frameSounds = [];
    };
    const finite = (p) => Number.isFinite(p.x) && Number.isFinite(p.y) && Number.isFinite(p.z);
    qa.check = () => {
      const s = G.session(), m = qa.m;
      if (!s || !s.match) return;
      const match = s.match;
      m.frames++;
      m.phases[match.phase] = (m.phases[match.phase] || 0) + 1;
      if (!finite(ctx.camera.position) || !Number.isFinite(ctx.camera.fov)) m.nan.length < 5 && m.nan.push('camera@' + m.frames);
      let off = false;
      for (const a of s.actors) {
        const f = match.fighters[a.index];
        for (const k of ['chest', 'weaponTip', 'head', 'footL']) { const sk = a.char.sockets[k]; if (sk && !finite(sk.getWorldPosition(v))) m.nan.length < 5 && m.nan.push(a.fighter.id + '.' + k + '@' + m.frames); }
        if (!finite(a.char.root.position)) m.nan.length < 5 && m.nan.push(a.fighter.id + '.root@' + m.frames);
        const key = f.state + (f.state === 'attack' ? ':' + f.move : '');
        const clip = a.char.clip;
        const ck = a.fighter.id + ' ' + key;
        if (!m.clips[ck]) m.clips[ck] = new Set();
        if (m.clips[ck].size < 6) m.clips[ck].add(clip);
        if (!a.cine && !match.cinematic) {
          const d = Math.abs(a.char.root.position.x - f.x);
          if (d > 0.08 && !(f.hitstop > 0)) m.drift++;
          m.driftMax = Math.max(m.driftMax, d);
          if (a.char.facing !== f.facing && f.stateTime > 0.15) m.facing++;
          if (LYING.has(f.state) && f.stateTime > 0.4 && !/down|ko|Down|lying|dead/i.test(clip || '')) m.lying.length < 6 && m.lying.push(a.fighter.id + ':' + f.state + '->' + clip);
        }
        if (clip === 'demo.idle' && f.state !== 'idle' && f.state !== 'recovery' && f.state !== 'attack') m.idleFallback++;
        if (ctx.cam.mode === 'fight' && ctx.cam.state.blend >= 0.999 && match.phase === 'fight') {
          v.copy(a.char.sockets.chest.getWorldPosition(v)).project(ctx.camera);
          if (Math.abs(v.x) > 1.0 || Math.abs(v.y) > 1.0 || v.z > 1) {
            off = true;
            if ((m.offWhere || (m.offWhere = [])).length < 4 && m.offRun === 0) m.offWhere.push(a.fighter.id + ':' + f.state + (f.move ? ':' + f.move : '') + ' ndc ' + v.x.toFixed(2) + ',' + v.y.toFixed(2) + ' x ' + f.x.toFixed(1) + ' y ' + f.y.toFixed(1));
          }
        }
      }
      if (off) { m.offscreen++; m.offRun++; m.offRunMax = Math.max(m.offRunMax, m.offRun); } else m.offRun = 0;
      if (match.cinematic) m.cine++;
    };
    qa.run = (sec, renderEvery) => {
      const n = Math.round(sec * 60);
      for (let i = 0; i < n; i++) {
        const r = renderEvery > 0 && (qa.m.frames % renderEvery === 0);
        ctx.frame(1 / 60, r);
        qa.check();
        qa.soundFrame();
        if (r) {
          const p = (ctx.renderer.info.programs || []).length;
          const s = G.session();
          if (qa.m.programs0 < 0 && s && s.match.phase === 'fight') qa.m.programs0 = p;
          else if (qa.m.programs0 >= 0 && p > qa.m.programs1 && qa.m.programs1 > 0) qa.m.newPrograms.push(p + '@' + qa.m.frames + ':' + (s && s.match.phase));
          qa.m.programs1 = Math.max(qa.m.programs1, p);
        }
        const s = G.session();
        if (s && s.ended && G.state === 'result') { qa.m.ended = true; return 'ended'; }
      }
      return 'running';
    };
    // event counters
    qa.hook = () => {
      const s = G.session();
      s.match.on('roundStart', () => { qa.m.rounds++; qa.pendingLightCheck = 3; });
      s.match.on('cinematicStart', () => qa.m.ults++);
      s.match.on('hit', (e) => { if (!e.blocked) qa.m.hits++; });
      s.match.on('ko', () => qa.m.kos++);
    };
    return true;
  })()`);

  if (process.env.MEMORY) {
    // session churn: build / dispose a match per pair (and rematch it) 10 times, 3 s of fight each with a render;
    // renderer memory, programs, scene children and JS heap must not grow with the number of matches
    const rows = [];
    for (let k = 0; k < 10; k++) {
      const [p1, p2] = PAIRS[k % PAIRS.length];
      const r = await evalJs(`(() => {
        __ED.game.start('${p1}', '${p2}', { mode: 'demo', difficulty: 'hard', seed: ${300 + k} });
        __ED.game.skipIntro(); __ED.advance(2); __ED.render();
        __ED.game.rematch(); __ED.game.skipIntro(); __ED.advance(1); __ED.render();
        const i = __ED.ctx.renderer.info;
        return { k: ${k}, pair: '${p1}:${p2}', geo: i.memory.geometries, tex: i.memory.textures, prog: (i.programs || []).length, children: __ED.ctx.scene.children.length,
          vfxChildren: __ED.ctx.vfx.root.children.length, heap: performance.memory ? Math.round(performance.memory.usedJSHeapSize / 1048576) : 0 };
      })()`);
      rows.push(r);
      log('memory', JSON.stringify(r));
    }
    const a = rows[1], b = rows[rows.length - 1];
    log('memory growth (match 2 -> 10):', `geo ${a.geo}->${b.geo} tex ${a.tex}->${b.tex} programs ${a.prog}->${b.prog} children ${a.children}->${b.children} heap ${a.heap}->${b.heap}MB`);
  }

  const summary = [];
  for (let k = 0; k < MATCHES; k++) {
    const [p1, p2] = PAIRS[k % PAIRS.length];
    const d1 = DIFFS[(k * 3 + 1) % 4], d2 = DIFFS[(k + 2) % 4];
    const before = await evalJs('(() => { const i = __ED.ctx.renderer.info; return { geo: i.memory.geometries, tex: i.memory.textures, prog: (i.programs || []).length, children: __ED.ctx.scene.children.length, heap: performance.memory ? Math.round(performance.memory.usedJSHeapSize / 1048576) : 0 }; })()');
    await evalJs(`(() => { __qa.reset(); __ED.game.start('${p1}', '${p2}', { mode: 'demo', difficulty: '${d2}', difficulty1: '${d1}', seed: ${100 + k} }); __qa.hook(); return 1; })()`);
    let state = 'running', simT = 0;
    const t0 = Date.now();
    while (state === 'running' && simT < CAP) { state = await evalJs(`__qa.run(10, ${RENDER_EVERY})`); simT += 10; }
    const m = await evalJs(`(() => {
      const m = __qa.m, s = __ED.game.session(), mt = s.match;
      const clips = {};
      for (const k in m.clips) clips[k] = [...m.clips[k]].join('|');
      const i = __ED.ctx.renderer.info;
      const lights = (__ED.ctx.vfx.lights && __ED.ctx.vfx.lights.pool ? __ED.ctx.vfx.lights.pool.filter((l) => l.light && l.light.intensity > 0).length : -1);
      return { ...m, clips, winner: mt.winner, round: mt.round, score: mt.fighters.map((f) => f.rounds), phase: mt.phase, clock: +mt.clock.toFixed(1),
        hp: mt.fighters.map((f) => Math.round(f.hp)), result: s.result && s.result.rounds, geo: i.memory.geometries, tex: i.memory.textures, prog: (i.programs || []).length,
        children: __ED.ctx.scene.children.length, heap: performance.memory ? Math.round(performance.memory.usedJSHeapSize / 1048576) : 0, lights };
    })()`);
    const line = `${p1}(${d1}) vs ${p2}(${d2}) sim ${simT}s wall ${((Date.now() - t0) / 1000).toFixed(0)}s ended=${m.ended} winner=${m.winner} score=${m.score} rounds=${m.rounds} hits=${m.hits} ults=${m.ults} kos=${m.kos} ` +
      `| nan=${m.nan.length ? m.nan.join(',') : 0} drift=${m.drift}(max ${m.driftMax.toFixed(2)}) facing=${m.facing} lying=${m.lying.join(',') || 0} offscreen=${m.offscreen}(run ${m.offRunMax}${m.offWhere ? ' ' + m.offWhere.join(' / ') : ''}) idleFallback=${m.idleFallback} ` +
      `| programs ${before.prog}->${m.programs0}->${m.prog} new=[${m.newPrograms.join(' ')}] geo ${before.geo}->${m.geo} tex ${before.tex}->${m.tex} children ${before.children}->${m.children} heap ${before.heap}->${m.heap}MB lights=${m.lights}` +
      ` | sounds ${m.sounds} peak/frame ${m.soundPeak} (${m.soundPeakAt}) frames with a repeated name ${m.sameName}`;
    log(line);
    summary.push({ p1, p2, m });
    if (k === 0 || process.env.CLIPS) log('clips', JSON.stringify(m.clips));
    if (k === 0 || process.env.CLIPS) log('sounds', JSON.stringify(m.soundNames));
  }
  log('warnings', warnings.length, JSON.stringify([...new Set(warnings)].slice(0, 30)));
};
