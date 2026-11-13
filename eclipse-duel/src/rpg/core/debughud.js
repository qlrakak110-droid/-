// Minimal built-in HUD of the RPG mode: used until src/rpg/ui registers the real one (README §11). Plain DOM over the
// stage: hero bars, chalice / shards, skill cooldowns, lock reticle + target bar, boss bar, prompt, banners, damage
// numbers, a pause panel. Everything is written only when it changes (no per-frame layout work beyond transforms).

const CSS = `
.rpgdbg{position:absolute;inset:0;pointer-events:none;font:600 12px/1.25 system-ui,"Noto Sans KR",sans-serif;color:#e8e2d2;z-index:4;text-shadow:0 1px 2px #000}
.rpgdbg .bars{position:absolute;left:3%;top:4%;width:min(34%,300px)}
.rpgdbg .bar{height:9px;margin:3px 0;background:rgba(8,9,13,.72);border:1px solid rgba(216,180,106,.45);position:relative;overflow:hidden}
.rpgdbg .bar i{position:absolute;left:0;top:0;bottom:0;width:100%;transform-origin:0 50%}
.rpgdbg .hp i{background:linear-gradient(#c8423a,#8a1f1c)}.rpgdbg .fp i{background:linear-gradient(#5aa7e6,#2a5c9c)}.rpgdbg .st i{background:linear-gradient(#7fc77a,#3f8544)}
.rpgdbg .st.lock i{background:#7a5a3a}
.rpgdbg .bar.st,.rpgdbg .bar.fp{height:6px;width:82%}
.rpgdbg .name{letter-spacing:.14em;font-size:11px;color:#d8b46a}
.rpgdbg .meta{margin-top:5px;font-size:11px;color:#cfc7b4}
.rpgdbg .skills{position:absolute;left:3%;bottom:5%;display:flex;gap:6px}
.rpgdbg .sk{min-width:54px;padding:4px 6px;background:rgba(8,9,13,.7);border:1px solid rgba(216,180,106,.4);font-size:10px;text-align:center;opacity:.55}
.rpgdbg .sk.ready{opacity:1;border-color:#d8b46a}
.rpgdbg .sk b{display:block;font-size:11px;color:#f4dca0}
.rpgdbg .ret{position:absolute;left:0;top:0;width:26px;height:26px;margin:-13px 0 0 -13px;border:2px solid rgba(255,240,200,.9);border-radius:50%;box-shadow:0 0 6px #000;display:none}
.rpgdbg .ret:after{content:"";position:absolute;left:50%;top:50%;width:4px;height:4px;margin:-2px;background:#fff;border-radius:50%}
.rpgdbg .tbar{position:absolute;left:0;top:0;width:84px;height:6px;margin:-34px 0 0 -42px;background:rgba(0,0,0,.7);border:1px solid rgba(255,255,255,.35);display:none}
.rpgdbg .tbar i{display:block;height:100%;background:#d6483e;transform-origin:0 50%}
.rpgdbg .boss{position:absolute;left:18%;right:18%;bottom:7%;display:none;text-align:center}
.rpgdbg .boss .bar{height:10px}.rpgdbg .boss .bar i{background:linear-gradient(#e0b45a,#8a5a1c)}
.rpgdbg .boss .bn{font:600 14px/1.4 Georgia,"Noto Serif KR",serif;letter-spacing:.2em;color:#f4dca0}
.rpgdbg .prompt{position:absolute;left:50%;bottom:22%;transform:translateX(-50%);padding:6px 14px;background:rgba(8,9,13,.78);border:1px solid rgba(216,180,106,.5);display:none;white-space:nowrap}
.rpgdbg .banner{position:absolute;left:0;right:0;top:30%;text-align:center;font:600 30px/1.3 Georgia,"Noto Serif KR",serif;letter-spacing:.3em;color:#f4dca0;opacity:0;transition:opacity .5s}
.rpgdbg .banner small{display:block;font:500 13px/1.6 system-ui;letter-spacing:.4em;color:#cfc7b4}
.rpgdbg .banner.death{color:#c0453a}
.rpgdbg .num{position:absolute;left:0;top:0;font:700 15px/1 system-ui;color:#fff;will-change:transform,opacity}
.rpgdbg .num.crit{color:#ffd76a;font-size:19px}.rpgdbg .num.hero{color:#ff6a5a}
.rpgdbg .panel{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);min-width:260px;padding:18px 22px;background:rgba(6,7,10,.92);border:1px solid rgba(216,180,106,.6);display:none;pointer-events:auto;text-align:center}
.rpgdbg .panel h3{margin:0 0 10px;font:600 16px/1.3 Georgia,"Noto Serif KR",serif;letter-spacing:.2em;color:#f4dca0}
.rpgdbg .panel button{display:block;width:100%;margin:6px 0;padding:9px 10px;background:#15161c;color:#e8e2d2;border:1px solid rgba(216,180,106,.45);font:600 12px/1.2 system-ui;letter-spacing:.08em;cursor:pointer}
.rpgdbg .panel button:hover{border-color:#f4dca0}
.rpgdbg .panel button[disabled]{opacity:.4;cursor:default}
`;

/**
 * @param {object} ctx
 * @param {object} api the mode object (ctx.rpg)
 */
export function createDebugHud(ctx, api) {
  const host = document.getElementById('ui') || document.getElementById('stage') || document.getElementById('app') || document.body;
  let style = document.getElementById('rpgdbg-css');
  if (!style) { style = document.createElement('style'); style.id = 'rpgdbg-css'; style.textContent = CSS; document.head.appendChild(style); }
  const root = document.createElement('div');
  root.className = 'rpgdbg';
  root.innerHTML = '<div class="bars"><div class="name"></div><div class="bar hp"><i></i></div><div class="bar fp"><i></i></div><div class="bar st"><i></i></div><div class="meta"></div></div>' +
    '<div class="skills"></div><div class="ret"></div><div class="tbar"><i></i></div><div class="boss"><div class="bn"></div><div class="bar"><i></i></div></div>' +
    '<div class="prompt"></div><div class="banner"></div><div class="panel"></div>';
  const q = (s) => root.querySelector(s);
  const el = { name: q('.name'), hp: q('.hp i'), fp: q('.fp i'), st: q('.st i'), stBar: q('.st'), meta: q('.meta'), skills: q('.skills'), ret: q('.ret'), tbar: q('.tbar'), tfill: q('.tbar i'),
    boss: q('.boss'), bossName: q('.bn'), bossFill: q('.boss .bar i'), prompt: q('.prompt'), banner: q('.banner'), panel: q('.panel') };
  const last = {};
  const put = (key, node, prop, value) => { if (last[key] === value) return; last[key] = value; node.style[prop] = value; };
  const text = (key, node, value) => { if (last[key] === value) return; last[key] = value; node.textContent = value; };
  const offs = [];
  const nums = [];
  for (let i = 0; i < 14; i++) { const n = document.createElement('div'); n.className = 'num'; n.style.opacity = '0'; root.appendChild(n); nums.push({ el: n, t: 9, x: 0, y: 0 }); }
  let numI = 0, bannerT = 0, panelKind = '';
  const P = { x: 0, y: 0, visible: false };

  function banner(title, sub, cls, dur = 2.6) {
    el.banner.className = 'banner' + (cls ? ' ' + cls : '');
    el.banner.innerHTML = '';
    el.banner.appendChild(document.createTextNode(title));
    if (sub) { const s = document.createElement('small'); s.textContent = sub; el.banner.appendChild(s); }
    el.banner.style.opacity = '1';
    bannerT = dur;
  }
  function panel(kind, snap) {
    if (panelKind === kind && kind !== 'rest') return;
    panelKind = kind;
    const p = el.panel;
    if (!kind) { p.style.display = 'none'; return; }
    p.style.display = 'block';
    p.innerHTML = '';
    const h = document.createElement('h3');
    const add = (label, fn, disabled) => { const b = document.createElement('button'); b.type = 'button'; b.textContent = label; b.disabled = !!disabled; b.addEventListener('click', (ev) => { ev.stopPropagation(); fn(); }); p.appendChild(b); };
    if (kind === 'pause') {
      h.textContent = '일시 정지 · PAUSED'; p.appendChild(h);
      add('계속하기 · Resume', () => api.resume());
      add('타이틀로 · Return to title', () => api.toTitle());
    } else if (kind === 'rest') {
      const lv = snap.levelUp;
      h.textContent = `별빛 제단 · Lv ${lv ? lv.level : 1}`; p.appendChild(h);
      const info = document.createElement('div');
      info.style.cssText = 'font-size:11px;margin-bottom:8px;color:#cfc7b4';
      info.textContent = lv ? `일식 조각 ${snap.hero.shards} / 필요 ${lv.cost}` : '';
      p.appendChild(info);
      const names = { vigor: '생명력 Vigor', endurance: '지구력 Endurance', might: '완력 Might', arcana: '비전 Arcana' };
      if (lv) for (const k of Object.keys(names)) add(`${names[k]}  ${lv.stats[k]} → ${lv.stats[k] + 1}`, () => { api.levelUp(k); panelKind = ''; }, !lv.canAfford);
      add('일어서기 · Leave', () => api.leaveAltar());
    } else if (kind === 'victory') {
      h.textContent = '거상이 무너졌다 · COLOSSUS FELLED'; p.appendChild(h);
      add('다음 일식으로 · Next cycle', () => api.nextCycle());
      add('타이틀로 · Return to title', () => api.toTitle());
    }
  }

  return {
    start() {
      host.appendChild(root);
      offs.push(api.on('hit', (e) => number(e)), api.on('tick', (e) => number(e)), api.on('guard', (e) => number(e)));
      offs.push(api.on('encounterStart', (e) => banner(e.def.title ? e.def.title.ko : e.id, e.def.title ? e.def.title.en : '')));
      offs.push(api.on('heroDeath', () => banner('빛이 꺼졌다', 'THE LIGHT GOES OUT', 'death', 3.2)));
      offs.push(api.on('bossDefeated', () => banner('일식이 물러간다', 'THE ECLIPSE RECEDES', '', 4)));
      offs.push(api.on('cycle', (e) => banner(`일식 ${e.cycle + 1}`, 'A NEW ECLIPSE')));
      offs.push(api.on('announce', (e) => banner(e.text, e.sub || '', '', 1.6)));
      offs.push(api.on('shards', (e) => { if (e.reason === 'reclaim') banner('조각을 되찾았다', 'SHARDS RECLAIMED', '', 1.8); }));
      offs.push(api.on('perfectGuard', () => banner('완벽한 방어', 'PERFECT GUARD', '', 0.7)));
    },
    stop() { for (const off of offs) off(); offs.length = 0; root.remove(); },
    update(s, dt) {
      const h = s.hero;
      text('name', el.name, `${h.nameEn}  LV ${h.level}`);
      put('hp', el.hp, 'transform', `scaleX(${(h.hp / h.hpMax).toFixed(3)})`);
      put('fp', el.fp, 'transform', `scaleX(${(h.fpMax ? h.fp / h.fpMax : 0).toFixed(3)})`);
      put('st', el.st, 'transform', `scaleX(${(h.staminaMax ? h.stamina / h.staminaMax : 0).toFixed(3)})`);
      const lock = h.staminaLocked ? 'bar st lock' : 'bar st';
      if (last.stc !== lock) { last.stc = lock; el.stBar.className = lock; }
      text('meta', el.meta, `여명의 잔 ${h.chalice}/${h.chaliceMax}   일식 조각 ${h.shards}   궁극기 ${Math.round(h.ult)}%${s.cycle ? '   일식 ' + (s.cycle + 1) : ''}`);
      // skills
      let sk = '';
      for (let i = 0; i < h.skills.length; i++) { const k = h.skills[i]; sk += `${k.name}|${k.ready ? 1 : 0}|${Math.ceil(k.cd * 10)};`; }
      sk += h.ultReady ? 'U1' : 'U0';
      if (last.sk !== sk) {
        last.sk = sk;
        el.skills.innerHTML = '';
        for (const k of h.skills) { const d = document.createElement('div'); d.className = 'sk' + (k.ready ? ' ready' : ''); d.innerHTML = `<b></b>${k.cost} FP${k.cd > 0 ? ' · ' + Math.ceil(k.cd * 10) / 10 : ''}`; d.firstChild.textContent = k.name; el.skills.appendChild(d); }
        const u = document.createElement('div'); u.className = 'sk' + (h.ultReady ? ' ready' : ''); u.innerHTML = '<b></b>ULT'; u.firstChild.textContent = h.ultSkill ? h.ultSkill.name : '궁극기'; el.skills.appendChild(u);
      }
      // target
      const t = s.target;
      const showT = !!t && t.visible && s.mode !== 'cine';
      put('retd', el.ret, 'display', showT ? 'block' : 'none');
      put('tbd', el.tbar, 'display', showT && !t.boss ? 'block' : 'none');
      if (showT) {
        el.ret.style.transform = `translate(${t.sx.toFixed(1)}px,${t.sy.toFixed(1)}px)`;
        el.tbar.style.transform = `translate(${t.sx.toFixed(1)}px,${t.sy.toFixed(1)}px)`;
        put('tf', el.tfill, 'transform', `scaleX(${(t.hp / t.hpMax).toFixed(3)})`);
      }
      const b = s.boss;
      put('bd', el.boss, 'display', b ? 'block' : 'none');
      if (b) { text('bn', el.bossName, `${b.name} · ${b.nameEn}`); put('bf', el.bossFill, 'transform', `scaleX(${(b.hp / b.hpMax).toFixed(3)})`); }
      const pr = s.prompt && s.mode === 'play' ? `[${s.prompt.key}] ${s.prompt.ko} · ${s.prompt.en}` : '';
      put('pd', el.prompt, 'display', pr ? 'block' : 'none');
      if (pr) text('pt', el.prompt, pr);
      if (bannerT > 0) { bannerT -= dt; if (bannerT <= 0) el.banner.style.opacity = '0'; }
      panel(s.mode === 'pause' ? 'pause' : s.mode === 'rest' ? 'rest' : s.mode === 'victory' ? 'victory' : '', s);
      for (const n of nums) {
        if (n.t > 0.9) continue;
        n.t += dt;
        const k = n.t / 0.9;
        n.el.style.transform = `translate(${n.x.toFixed(1)}px,${(n.y - 46 * k).toFixed(1)}px)`;
        n.el.style.opacity = k >= 1 ? '0' : (1 - k * k).toFixed(2);
      }
    },
    dispose() { root.remove(); },
  };

  function number(e) {
    if (!e.damage || !e.pos) return;
    api.project(e.pos, P);
    if (!P.visible) return;
    const n = nums[numI++ % nums.length];
    n.t = 0; n.x = P.x - 10; n.y = P.y - 24;
    n.el.className = 'num' + (e.crit ? ' crit' : '') + (e.victim === api.hero ? ' hero' : '');
    n.el.textContent = String(e.damage);
  }
}
