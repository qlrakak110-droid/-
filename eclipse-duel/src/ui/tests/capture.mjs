// Capture every UI screen / HUD state at several viewports in one page load (shot.mjs --scenario).
//
//   node tools/shot.mjs ui --scenario src/ui/tests/capture.mjs --out shots/ui/desk                 (desktop sizes)
//   node tools/shot.mjs ui --scenario src/ui/tests/capture.mjs --touch --out shots/ui/phone        (touch sizes)
//
// Env: ED_SIZES="1280x720,1920x1080" and ED_ONLY="hud,title" narrow the run.

const DESK = ['1280x720', '1920x1080', '1024x768'];
const TOUCH = ['844x390', '390x844', '360x740'];

// [label, scenario call, seconds to advance before the capture]
const STATES = [
  ['title', "__ED.lab.play('title')", 2.2],
  ['select', "__ED.lab.play('select')", 1.2],
  ['selectCpu', "__ED.lab.play('selectCpu')", 1.2],
  ['selectDiff', "__ED.lab.play('selectDiff')", 1.2],
  ['vs', "__ED.lab.play('vs')", 1.4],
  ['hud', "__ED.lab.play('hud')", 0.6],
  ['hudLow', "__ED.lab.play('hudLow')", 0.9],
  ['hints', "__ED.lab.play('hints')", 0.6],
  ['round', "__ED.lab.play('announce', 'round')", 0.7],
  ['fight', "__ED.lab.play('announce', 'fight')", 0.3],
  ['ko', "__ED.lab.play('announce', 'ko')", 0.5],
  ['perfect', "__ED.lab.play('announce', 'perfect')", 0.8],
  ['timeup', "__ED.lab.play('announce', 'timeup')", 0.7],
  ['ult', "__ED.lab.play('announce', 'ult')", 0.6],
  ['pause', "__ED.lab.play('pause')", 0.6],
  ['movelist', "__ED.lab.play('movelist')", 0.6],
  ['result', "__ED.lab.play('result')", 1.6],
  ['resultLose', "__ED.lab.play('resultLose')", 1.6],
];

export default async ({ page, evalJs, advance, shot, log }) => {
  const touch = await evalJs('__ED.lab.ui.touch.visible');
  const sizes = (process.env.ED_SIZES ? process.env.ED_SIZES.split(',') : touch ? TOUCH : DESK);
  const only = process.env.ED_ONLY ? process.env.ED_ONLY.split(',') : null;
  for (const size of sizes) {
    const [w, hh] = size.split('x').map(Number);
    await page.setViewportSize({ width: w, height: hh });
    await page.evaluate(() => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))));
    await evalJs('__ED.lab.ui.layout()');
    for (const [label, call, t] of STATES) {
      if (only && !only.includes(label)) continue;
      await evalJs(call);
      await advance(t);
      await shot(`${size}_${label}`);
    }
    log('captured', size);
  }
};
