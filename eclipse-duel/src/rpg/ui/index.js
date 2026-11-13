// HUD of 강호행 (README of src/rpg, §11): the core's HUD (bars, boss plate, banners, altar / pause panels) plus the
// touch controls a phone needs — a floating move stick on the left, camera drag on the right, and an arc of ink-seal
// buttons under the right thumb. The seals carry one character each: 攻 light, 重 heavy, 避 roll (hold: sprint),
// 防 guard, 鎖 lock-on, 丹 the pill gourd, 一 二 三 the arts, 奧 the ultimate, 門 interact, ‖ pause.

import { createDebugHud } from '../core/debughud.js';

const CSS = `
.rpgt{position:absolute;inset:0;z-index:3;pointer-events:auto;touch-action:none;user-select:none;-webkit-user-select:none;-webkit-touch-callout:none;font-family:"Noto Serif KR","Nanum Myeongjo",Georgia,serif}
.rpgt .b{position:absolute;display:flex;align-items:center;justify-content:center;border-radius:50%;color:#f1e6c8;
  background:radial-gradient(circle at 36% 30%,rgba(70,62,52,.74),rgba(12,11,12,.82) 68%);border:1.5px solid rgba(214,178,104,.62);
  box-shadow:0 0 0 3px rgba(0,0,0,.34),inset 0 0 12px rgba(0,0,0,.7);text-shadow:0 1px 3px #000;line-height:1;transition:transform .06s,filter .12s,opacity .2s}
.rpgt .b.on{transform:scale(.9);filter:brightness(1.7);border-color:#ffe6a6}
.rpgt .b.off{opacity:.34}
.rpgt .b.hot{border-color:#ffd77a;box-shadow:0 0 0 3px rgba(0,0,0,.34),0 0 16px rgba(255,190,80,.8),inset 0 0 12px rgba(120,60,0,.6)}
.rpgt .b small{position:absolute;bottom:-1.25em;left:-30%;right:-30%;text-align:center;font:600 9px/1 system-ui,sans-serif;letter-spacing:.06em;color:#d9cfb6;opacity:.86;white-space:nowrap}
.rpgt .b em{position:absolute;right:-6%;top:-6%;min-width:1.5em;padding:.18em .2em;border-radius:1em;background:#7c1f17;border:1px solid #e0b46a;font:700 10px/1 system-ui;font-style:normal;text-align:center}
.rpgt .cd{position:absolute;inset:0;border-radius:50%;background:conic-gradient(rgba(0,0,0,.72) var(--cd,0deg),transparent 0);pointer-events:none}
.rpgt .stick{position:absolute;border-radius:50%;border:1.5px solid rgba(214,178,104,.42);background:radial-gradient(circle,rgba(20,18,18,.2),rgba(8,8,10,.5));pointer-events:none;opacity:.5;transition:opacity .15s}
.rpgt .stick i{position:absolute;left:50%;top:50%;width:44%;height:44%;margin:-22% 0 0 -22%;border-radius:50%;background:radial-gradient(circle at 36% 30%,rgba(120,104,80,.9),rgba(24,20,18,.92));border:1.5px solid rgba(232,196,120,.8)}
.rpgt.hide .b:not(.pause),.rpgt.hide .stick{opacity:0;pointer-events:none}
.rpgt .b.int.off{opacity:0;pointer-events:none}
.rpgdbg.touch .skills{display:none}
.rpgdbg.touch .boss{left:41%;right:15%;bottom:auto;top:3%}
`;

// [action, glyph, label, right vmin, bottom vmin, size vmin]
const BUTTONS = [
  ['light', '攻', '약공', 5, 9, 21],
  ['dodge', '避', '구르기', 28, 4, 15.5],
  ['heavy', '重', '강공', 27, 22, 15.5],
  ['guard', '防', '방어', 7, 33, 14.5],
  ['lock', '鎖', '조준', 24, 40, 11.5],
  ['chalice', '丹', '회천단', 46, 4, 11.5],
  ['skill1', '一', '', 4, 51, 11.5],
  ['skill2', '二', '', 17.5, 55, 11.5],
  ['skill3', '三', '', 31, 55, 11.5],
  ['ult', '奧', '오의', 43, 44, 13],
];

export default function install(rpg) {
  rpg.ui((ctx, api) => {
    const hud = createDebugHud(ctx, api);
    const touch = (typeof matchMedia !== 'undefined' && matchMedia('(pointer: coarse)').matches) || (typeof navigator !== 'undefined' && navigator.maxTouchPoints > 0) || /[#&]touch\b/.test(location.hash);
    if (!touch) return hud;

    const host = document.getElementById('ui') || document.getElementById('stage') || document.getElementById('app') || document.body;
    if (!document.getElementById('rpgt-css')) { const st = document.createElement('style'); st.id = 'rpgt-css'; st.textContent = CSS; document.head.appendChild(st); }
    const root = document.createElement('div');
    root.className = 'rpgt';
    const input = ctx.input;
    const btn = {};
    const mk = (action, glyph, label, r, b, s, cls = '') => {
      const e = document.createElement('div');
      e.className = 'b ' + cls;
      e.style.cssText = `right:${r}vmin;bottom:${b}vmin;width:${s}vmin;height:${s}vmin;font-size:${s * 0.46}vmin`;
      e.innerHTML = `<span>${glyph}</span>${label ? `<small>${label}</small>` : ''}<div class="cd"></div>`;
      e.dataset.a = action;
      root.appendChild(e);
      btn[action] = { el: e, id: -1, cd: e.querySelector('.cd'), last: {} };
      return e;
    };
    for (const [a, g, l, r, b, s] of BUTTONS) mk(a, g, l, r, b, s);
    const pill = document.createElement('em'); btn.chalice.el.appendChild(pill);
    const pause = mk('pause', '‖', '', 3, 0, 9, 'pause');
    pause.style.bottom = 'auto'; pause.style.top = '3vmin';
    const act = mk('interact', '門', '', 0, 30, 13, 'int off');
    act.style.right = 'auto'; act.style.left = 'calc(50% - 6.5vmin)';
    const stick = document.createElement('div');
    stick.className = 'stick';
    stick.innerHTML = '<i></i>';
    root.appendChild(stick);
    const knob = stick.firstChild;

    const vmin = () => Math.min(root.clientWidth || innerWidth, root.clientHeight || innerHeight) / 100;
    const mv = { id: -1, x: 0, y: 0, r: 60 }, look = { id: -1, x: 0, y: 0 };
    const placeStick = (x, y, show) => {
      const R = mv.r;
      stick.style.width = stick.style.height = R * 2 + 'px';
      stick.style.left = x - R + 'px'; stick.style.top = y - R + 'px';
      stick.style.opacity = show ? '1' : '.5';
    };
    const homeStick = () => { const u = vmin(); mv.r = 11 * u; placeStick(20 * u, (root.clientHeight || innerHeight) - 22 * u, false); knob.style.transform = ''; };
    const press = (b, down) => {
      b.el.classList.toggle('on', down);
      input.setVirtual(b.el.dataset.a, down);
    };
    const local = (e) => { const r = root.getBoundingClientRect(); return { x: e.clientX - r.left, y: e.clientY - r.top, w: r.width, h: r.height }; };
    const onDown = (e) => {
      if (e.pointerType === 'mouse' && !/[#&]touch\b/.test(location.hash)) return;
      const t = e.target.closest ? e.target.closest('.b') : null;
      e.preventDefault();
      if (t && btn[t.dataset.a]) { const b = btn[t.dataset.a]; if (b.id < 0) { b.id = e.pointerId; press(b, true); } return; }
      const p = local(e);
      if (p.x < p.w * 0.42 && mv.id < 0) {
        mv.id = e.pointerId; mv.x = p.x; mv.y = p.y;
        placeStick(p.x, p.y, true);
      } else if (look.id < 0) { look.id = e.pointerId; look.x = e.clientX; look.y = e.clientY; }
    };
    const onMove = (e) => {
      if (e.pointerId === mv.id) {
        const p = local(e);
        let dx = (p.x - mv.x) / mv.r, dy = (p.y - mv.y) / mv.r;
        const l = Math.hypot(dx, dy);
        if (l > 1) { dx /= l; dy /= l; }
        knob.style.transform = `translate(${dx * mv.r * 0.62}px,${dy * mv.r * 0.62}px)`;
        const dead = 0.14, m = Math.min(1, l);
        const k = m < dead ? 0 : (m - dead) / (1 - dead) / (m || 1);
        input.setVirtualMove(dx * k, -dy * k);
      } else if (e.pointerId === look.id) {
        const dx = e.clientX - look.x, dy = e.clientY - look.y;
        look.x = e.clientX; look.y = e.clientY;
        input.addLook(dx * 0.0062, -dy * 0.0046);
      }
    };
    const onUp = (e) => {
      if (e.pointerId === mv.id) { mv.id = -1; input.setVirtualMove(0, 0); homeStick(); }
      else if (e.pointerId === look.id) look.id = -1;
      else for (const k in btn) if (btn[k].id === e.pointerId) { btn[k].id = -1; press(btn[k], false); }
    };
    const releaseAll = () => {
      mv.id = look.id = -1;
      input.setVirtualMove(0, 0);
      for (const k in btn) { if (btn[k].id >= 0) { btn[k].id = -1; press(btn[k], false); } }
      homeStick();
    };
    const set = (b, key, cls, on) => { if (b.last[key] === on) return; b.last[key] = on; b.el.classList.toggle(cls, on); };
    let hidden = null;

    return {
      start(s) {
        hud.start(s);
        host.appendChild(root);
        const dbg = host.querySelector('.rpgdbg');
        if (dbg) dbg.classList.add('touch');
        root.addEventListener('pointerdown', onDown);
        window.addEventListener('pointermove', onMove);
        window.addEventListener('pointerup', onUp);
        window.addEventListener('pointercancel', onUp);
        window.addEventListener('resize', homeStick);
        homeStick();
      },
      stop() {
        releaseAll();
        root.removeEventListener('pointerdown', onDown);
        window.removeEventListener('pointermove', onMove);
        window.removeEventListener('pointerup', onUp);
        window.removeEventListener('pointercancel', onUp);
        window.removeEventListener('resize', homeStick);
        root.remove();
        hud.stop();
      },
      update(s, dt) {
        hud.update(s, dt);
        const play = s.mode === 'play';
        if (hidden !== !play) { hidden = !play; root.classList.toggle('hide', hidden); if (hidden) releaseAll(); }
        if (!play) return;
        const h = s.hero;
        for (let i = 0; i < 3; i++) {
          const sk = h.skills[i], b = btn['skill' + (i + 1)];
          if (!sk || !b) continue;
          set(b, 'off', 'off', !sk.ready);
          const deg = Math.round((sk.cd || 0) * 36) * 10;
          if (b.last.deg !== deg) { b.last.deg = deg; b.cd.style.setProperty('--cd', deg + 'deg'); }
        }
        set(btn.ult, 'off', 'off', !h.ultReady); set(btn.ult, 'hot', 'hot', !!h.ultReady);
        set(btn.chalice, 'off', 'off', h.chalice <= 0);
        if (btn.chalice.last.n !== h.chalice) { btn.chalice.last.n = h.chalice; pill.textContent = h.chalice; }
        set(btn.lock, 'hot', 'hot', !!h.lockId);
        set(btn.interact, 'off', 'off', !s.prompt); set(btn.interact, 'hot', 'hot', !!s.prompt);
        set(btn.dodge, 'off', 'off', !!h.staminaLocked); set(btn.light, 'off', 'off', !!h.staminaLocked);
      },
      dispose() { root.remove(); if (hud.dispose) hud.dispose(); },
    };
  });
}
