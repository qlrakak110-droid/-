// node probe_char.js <html>: print the studio's JS character controller API (to teleport the avatar in tests)
const { chromium } = require('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/harness/node_modules/playwright');
(async () => {
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const p = await b.newPage({ viewport: { width: 640, height: 360 } });
  await p.goto('file://' + process.argv[2]);
  await p.waitForFunction(() => window.GW && GW.engine && GW.engine.running, null, { timeout: 300000 });
  await p.waitForTimeout(8000);
  const info = await p.evaluate(() => {
    const out = [];
    const C = window.Character;
    const dump = (name, o) => {
      if (!o) { out.push(name + ': null'); return; }
      const keys = new Set(Object.getOwnPropertyNames(o));
      let pr = Object.getPrototypeOf(o);
      while (pr && pr !== Object.prototype) { Object.getOwnPropertyNames(pr).forEach((k) => keys.add(k)); pr = Object.getPrototypeOf(pr); }
      for (const k of keys) {
        let v; try { v = o[k]; } catch (e) { v = 'ERR'; }
        if (typeof v === 'function') out.push(`${name}.${k}(${v.length}) ${String(v).slice(0, 160).replace(/\s+/g, ' ')}`);
        else out.push(`${name}.${k} = ${typeof v === 'object' ? (v && v.constructor ? v.constructor.name : 'obj') : String(v).slice(0, 80)}`);
      }
    };
    dump('Character', C);
    try { dump('GW.engine', GW.engine); } catch (e) {}
    return out.join('\n');
  });
  console.log(info);
  await b.close();
})().catch((e) => { console.log('FATAL', e); process.exit(1); });
