// node shot.js <html> <outDir> <shots.json> [hash]
// shots: [{name, car: id|kind, eye:[x,y,z] model-local, at:[x,y,z] model-local, fov?, night?, wait?, world?:{eye,at}}]
const { chromium } = require('playwright');
const fs = require('fs');
(async () => {
  const [html, outDir, shotsFile, hash] = process.argv.slice(2);
  const shots = JSON.parse(fs.readFileSync(shotsFile, 'utf8'));
  fs.mkdirSync(outDir, { recursive: true });
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const p = await b.newPage({ viewport: { width: +(process.env.W || 1280), height: +(process.env.H || 720) } });
  p.setDefaultTimeout(300000);
  const errs = [];
  p.on('pageerror', e => { errs.push(e.message); console.log('[pageerror]', e.message); });
  p.on('console', m => { const t = m.text(); if (/carglass|CarGlass|shader|WebGL|THREE\.|GL_|error|ERROR/i.test(t)) console.log('[c]', t.slice(0, 400)); });
  await p.goto('file://' + html + (hash ? '#' + hash : ''));
  await p.waitForFunction(() => window.GW && GW.engine && GW.engine.running, null, { timeout: 300000 });
  for (let i = 0; i < 30; i++) { await p.waitForTimeout(2000); const n = await p.evaluate(() => Render3D.carSkinStats().cars); if (n > 10) break; }
  await p.waitForTimeout(3000);
  await p.evaluate(() => {
    CameraCtl.suspend();
    const st = document.createElement('style'); st.textContent = '#gw-gui,#gw-hud,#gw-controls,#gw-prompts,#gw-toasts,#gw-chips,#gw-badge{display:none!important}'; document.head.appendChild(st);
    const R = Render3D, orig = R.applyChanges;
    R.applyChanges = function (list) { if (window.__clock != null && list) for (const c of list) if (c && c.op === 'lighting') { const pr = c.props || c; if (pr.ClockTime !== undefined) pr.ClockTime = window.__clock; if (pr.TimeOfDay !== undefined) delete pr.TimeOfDay; } return orig.call(this, list); };
  });
  for (const s of shots) {
    const r = await p.evaluate(async (s) => {
      const R = Render3D, T = R.THREE;
      window.__clock = s.clock != null ? s.clock : 14; R.setLighting({ ClockTime: window.__clock });
      if (s.night != null) R.setNightOverride(s.night ? true : null);
      const cars = R.carSkinCars();
      const car = typeof s.car === 'number' ? cars.find(c => c.id === s.car) : cars.filter(c => c.kind === s.car).sort((a, b) => a.dist - b.dist)[0];
      if (!car) return { err: 'no car ' + s.car };
      const cam = R.camera;
      // first put the camera near the car so it becomes a hi-detail slot
      cam.position.set(car.pos[0] - car.look[0] * 12, car.pos[1] + 4, car.pos[2] - car.look[2] * 12);
      cam.lookAt(car.pos[0], car.pos[1], car.pos[2]); cam.updateMatrixWorld();
      await new Promise(r => setTimeout(r, 1200));
      // find the hi slot root nearest to the car
      let best = null, bd = 1e9; const wp = new T.Vector3();
      R.scene.traverse(o => { if (o.isGroup && o.matrixAutoUpdate === false && o.children.length === 1 && o.children[0].children.length > 8) { wp.setFromMatrixPosition(o.matrixWorld); const d = wp.distanceTo(new T.Vector3(...car.pos)); if (d < bd) { bd = d; best = o; } } });
      if (!best || bd > 12) return { err: 'no hi slot', bd };
      const M = best.matrixWorld;
      const eye = new T.Vector3(...s.eye).applyMatrix4(M), at = new T.Vector3(...s.at).applyMatrix4(M);
      cam.position.copy(eye); cam.up.set(0, 1, 0); cam.lookAt(at); cam.fov = s.fov || 70; cam.near = s.near || 0.1; cam.updateProjectionMatrix(); cam.updateMatrixWorld();
      window.__shotCam = { eye: eye.toArray(), at: at.toArray(), fov: cam.fov };
      return { car: car.id, kind: car.kind, slotDist: bd, eye: eye.toArray() };
    }, s);
    console.log(s.name, JSON.stringify(r));
    // keep the camera pinned for a few frames (render loop may move it otherwise)
    const t0 = Date.now();
    while (Date.now() - t0 < (s.wait || 2500)) {
      await p.evaluate(() => { const c = window.__shotCam; if (!c) return; const cam = Render3D.camera; cam.position.fromArray(c.eye); cam.lookAt(...c.at); cam.fov = c.fov; cam.updateProjectionMatrix(); });
      await p.waitForTimeout(250);
    }
    await p.screenshot({ path: outDir + '/' + s.name + '.png' });
    if (s.probe) console.log('probe', s.name, await p.evaluate(() => { const U = RblxGfx._.U; const f = (v) => v.value.toArray ? v.value.toArray().map((x) => +x.toFixed(4)) : +v.value.toFixed(4); return JSON.stringify({ zen: f(U.rbxSkyZen), hor: f(U.rbxSkyHor), sun: f(U.rbxSunCol), ambOut: f(U.rbxAmbOut), ambIn: f(U.rbxAmbIn), ground: f(U.rbxHemiGround), envSpec: f(U.rbxEnvSpec), env: !!Render3D.scene.environment, glass: !!window.GWCarGlass, prog: Render3D.renderer.info.programs.length }); }));
  }
  console.log('errors:', errs.length);
  await b.close();
})();
