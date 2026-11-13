// Menu screens: title, select, vs, pause, movelist, result. Each screen is { el, enter(data, prev), exit?, back?,
// update?(dt), onAction?(action, info) }. Focus and navigation come from ui.item / ui.setItems (index.js).

import { h, esc } from './anim.js';
import { icon, weaponArt, eclipseMark } from './icons.js';
import { DIFFICULTIES, QUALITIES, ELEMENTS, ARENA, TITLE } from './roster.js';
import { seal, divider, mountains, splash } from './ink.js';
import { brushText } from './brush.js';
import { Ease, clamp, makeRng } from '../core/math.js';
import { put } from './hud.js';

const STAT_ROWS = [['power', '위력', 'POWER'], ['speed', '신속', 'SPEED'], ['reach', '간격', 'REACH'], ['difficulty', '숙련', 'MASTERY']];

export function createScreens(ui) {
  const { ctx, anim } = ui;
  // menu randomness has its own deterministic stream so it never shifts the match's ctx.rng sequence
  const rng = makeRng((Number(ctx.flags && ctx.flags.seed) || 20261112) ^ 0x5e1ec7);

  // ---------------------------------------------------------------------------------------------------------------
  // shared bits

  const fighterOf = (f) => (typeof f === 'string' ? ui.roster.find((r) => r.id === f) : f) || null;
  const elemTag = (el) => {
    const e = ELEMENTS[el] || { name: el, nameEn: '' };
    return `<span class="el-tag el-${esc(el)}">${icon(el)}<b>${esc(e.name)}</b><i class="hj">${esc(e.hanja || '')}</i><em>${esc(e.nameEn)}</em></span>`;
  };
  /** Korean reading with its Hanja as the accent: 「적양문 <赤陽門>」. */
  const kh = (ko, hanja) => `${esc(ko)}${hanja ? `<i class="hj">${esc(hanja)}</i>` : ''}`;
  const keycap = (k, cls = '') => (k ? `<span class="keycap ${cls}">${esc(k)}</span>` : '');
  const qualityNow = () => (ctx.quality && ctx.quality.tier) || 'high';
  const bilingual = (ko, en) => `<span class="ko">${esc(ko)}</span><span class="en">${esc(en)}</span>`;

  /** Panel corners (four short ink ticks). */
  const corners = () => '<i class="cn tl"></i><i class="cn tr"></i><i class="cn bl"></i><i class="cn br"></i>';

  /**
   * Segmented control: one focus item; left / right (or a tap on an option) changes the value.
   * @returns {HTMLElement & { set(v): void, value: string }}
   */
  function segmented({ ko, en, options, value, onChange, cls = '' }) {
    const opts = options.map((o) => h('button.seg-opt', { type: 'button', 'data-v': o.value, html: bilingual(o.name, o.nameEn) + (o.hanja ? `<i class="hj">${esc(o.hanja)}</i>` : '') }));
    const el = h('div.seg' + (cls ? '.' + cls : ''), null, h('div.seg-label', { html: bilingual(ko, en) }), h('div.seg-opts', null, ...opts));
    el.value = value;
    el.set = (v, emit = false) => {
      el.value = v;
      opts.forEach((o) => o.classList.toggle('on', o.dataset.v === v));
      if (emit && onChange) onChange(v);
    };
    el.set(value);
    ui.item(el, {
      lr: (d) => {
        const i = options.findIndex((o) => o.value === el.value);
        const n = clamp(i + d, 0, options.length - 1);
        if (n !== i) el.set(options[n].value, true);
      },
    });
    opts.forEach((o) => o.addEventListener('click', (e) => {
      e.stopPropagation();
      ui.focus(el, false);
      if (el.value !== o.dataset.v) { ui.sound('ui_move'); el.set(o.dataset.v, true); }
    }));
    return el;
  }

  /** Menu row button: Korean label, English sub, optional icon. */
  function menuBtn(ko, en, ico, act, cls = '') {
    const el = h('button.mbtn' + (cls ? '.' + cls : ''), { type: 'button' }, h('i.mbtn-mark'), ico ? h('span.mbtn-ico', { html: icon(ico) }) : null, h('span.mbtn-txt', { html: bilingual(ko, en) }));
    return ui.item(el, { act });
  }

  /** Entrance: fade + rise for a list of nodes, staggered (transform / opacity). */
  function rise(nodes, { delay = 0, step = 0.06, dist = 18, dur = 0.5 } = {}) {
    nodes.forEach((n, i) => {
      if (!n) return;
      n.style.opacity = '0';
      anim.add(dur, (k) => {
        n.style.opacity = k.toFixed(3);
        n.style.transform = k < 1 ? `translateY(${(dist * (1 - k)).toFixed(1)}px)` : '';
      }, { key: n, delay: delay + i * step, ease: 'outCubic' });
    });
  }

  // ---------------------------------------------------------------------------------------------------------------
  // TITLE

  const title = (() => {
    // the lockup: the ink eclipse behind the brush-written title and its seal, the Hanja between dry-brush rules
    const mark = h('div.tt-mark', { html: eclipseMark() });
    const glow = h('i.tt-glow');
    const word = h('h1.tt-word', { 'aria-label': `${TITLE.name} ${TITLE.hanja}`, html: brushText(TITLE.name, { weight: 1.16, gap: 4, seed: 1, fill: ['#fffaf0', '#d9cdb2'] }) });
    const stamp = h('i.tt-seal', { html: seal(TITLE.hanja, { seed: 3 }) });
    const sub = h('div.tt-sub', { html: `${divider({ seed: 6 })}<b>${esc(TITLE.hanja)}</b>${divider({ seed: 7, flip: true })}` });
    const en = h('div.tt-en', { text: TITLE.nameEn });
    const tag = h('div.tt-tag', { html: `<span>${esc(TITLE.tag)}</span><em>${esc(TITLE.tagEn)}</em>` });
    const lockup = h('div.tt-lockup', null, glow, mark, h('div.tt-type', null, word, stamp), sub, en, tag);
    const startTxt = h('span.tt-start-txt');
    const start = ui.item(h('button.tt-start', { type: 'button' }, startTxt), { act: () => ui.emit('start') });
    // title menu: entries stack under the start prompt
    const menu = h('div.tt-menu', null, start);
    // 강호행 (the action-RPG mode, src/rpg): one entry per hero -> event `expedition` (hero id)
    const expBtns = [];
    const exp = h('div.tt-exp', { style: 'position:relative;display:flex;flex-wrap:wrap;align-items:center;justify-content:center;gap:8px 10px;margin-top:4px;pointer-events:auto' },
      h('span.tt-exp-label', { style: 'display:flex;flex-direction:column;align-items:center;gap:3px;margin-right:6px;text-align:center',
        html: '<span class="ko" style="font:600 max(13px,calc(var(--k)*16))/1.2 var(--f-ko);letter-spacing:.2em;color:var(--paper,#ece4d2);text-shadow:0 1px 0 #000">강호행 <i class="hj" style="font-style:normal;opacity:.75">江湖行</i></span><span class="en" style="font:600 10px/1 var(--f-data);letter-spacing:.3em;color:var(--seal-hi,#d8b46a)">ACTION RPG</span>' }));
    function buildExpedition() {
      for (const b of expBtns) b.remove();
      expBtns.length = 0;
      for (const f of ui.roster || []) {
        const b = ui.item(h('button.tt-exp-btn', { type: 'button', 'aria-label': `강호행 ${f.name}`,
          style: 'min-width:86px;min-height:44px;padding:6px 12px;border:1px solid rgba(216,180,106,.45);background:rgba(6,6,9,.62);color:var(--paper,#ece4d2);cursor:pointer;font:600 max(12px,calc(var(--k)*14))/1.2 var(--f-ko);letter-spacing:.12em',
          html: `<span>${esc(f.name)}</span><em style="display:block;margin-top:3px;font:600 9px/1 var(--f-data);letter-spacing:.24em;font-style:normal;color:var(--seal-hi,#d8b46a)">${esc(f.nameEn || '')}</em>` }), { act: () => ui.emit('expedition', f.id) });
        expBtns.push(b);
        exp.appendChild(b);
      }
    }
    menu.appendChild(exp);
    const quality = segmented({ ko: '그래픽 품질', en: 'QUALITY', options: QUALITIES, value: qualityNow(), onChange: (v) => ui.emit('quality', v), cls: 'tt-quality' });
    const foot = h('div.tt-foot', null, h('div.tt-ver', { html: `<b>v0.1</b> · ${esc(ARENA.arena)} ${esc(ARENA.arenaHanja)}` }), quality);
    const body = h('div.tt-body', null, lockup, menu);
    const el = h('div', null, h('div.scr-shade.tt-shade'), h('div.tt-mount', { html: mountains({ seed: 8 }) }), body, foot);
    /** The lockup and the menu always fit between the top edge and the footer: shrink them as one when they do not. */
    function fit() {
      body.style.transform = '';
      const cs = getComputedStyle(el);
      const avail = el.clientHeight - parseFloat(cs.paddingTop) - parseFloat(cs.paddingBottom);
      const need = body.offsetHeight;
      if (avail > 0 && need > avail) body.style.transform = `scale(${(avail / need).toFixed(4)})`;
    }
    // a tap / click anywhere that is not a control starts
    el.addEventListener('click', () => { if (ui.screen === 'title') { ui.sound('ui_select'); ui.emit('start'); } });
    let t = 0;
    return {
      el,
      enter(d) {
        t = 0;
        quality.set(d.quality || qualityNow());
        startTxt.innerHTML = ui.device === 'touch' ? bilingual('화면을 눌러 비무대에 오른다', 'TAP TO BEGIN') : bilingual('아무 버튼이나 눌러 비무대에 오른다', 'PRESS ANY BUTTON');
        buildExpedition();
        fit();
        ui.setItems([start, ...expBtns, quality], start);
        mark.style.opacity = '0';
        anim.add(1.6, (k) => {
          mark.style.opacity = k.toFixed(3);
          mark.style.transform = `scale(${(0.86 + 0.14 * k).toFixed(4)})`;
        }, { key: mark, ease: 'outQuart' });
        // the title is written in: it lands large and settles, then the seal is stamped
        word.style.opacity = '0';
        anim.add(0.9, (k) => {
          word.style.opacity = Math.min(1, k * 1.6).toFixed(3);
          word.style.transform = k < 1 ? `scale(${(1.14 - 0.14 * k).toFixed(4)})` : '';
        }, { key: word, delay: 0.3, ease: 'outQuart' });
        stamp.style.opacity = '0';
        anim.add(0.34, (k) => {
          stamp.style.opacity = Math.min(1, k * 2.5).toFixed(3);
          stamp.style.transform = k < 1 ? `scale(${(1.9 - 0.9 * k).toFixed(4)}) rotate(${(-9 * (1 - k)).toFixed(2)}deg)` : '';
        }, { key: stamp, delay: 1.15, ease: 'outQuart' });
        rise([sub, en, tag], { delay: 0.75, step: 0.12, dist: 12, dur: 0.8 });
        rise([menu, foot], { delay: 1.1, step: 0.12, dist: 10, dur: 0.6 });
      },
      update(dt) {
        t += dt;
        // the corona breathes behind the black sun
        put(glow, 'opacity', (0.72 + 0.28 * Math.sin(t * 0.9)).toFixed(3));
        put(glow, 'transform', `scale(${(1 + 0.035 * Math.sin(t * 0.63)).toFixed(4)})`);
        if (t > 1.4) put(startTxt, 'opacity', (0.72 + 0.28 * Math.cos((t - 1.4) * 2.6)).toFixed(3));
      },
      layout() { if (ui.screen === 'title') fit(); },
      onAction(action) {
        // any face button starts, unless the player is adjusting quality
        if (ui.focused() === start && /^(light|heavy|skill\d|ult|dodge|guard)$/.test(action)) { ui.sound('ui_select'); ui.emit('start'); return true; }
        return false;
      },
    };
  })();

  // ---------------------------------------------------------------------------------------------------------------
  // SELECT

  const select = (() => {
    const steps = h('div.sel-steps');
    const backBtn = ui.item(h('button.icon-btn.sel-back', { type: 'button', 'aria-label': '뒤로 Back', html: icon('back') }), { act: () => sel.back(), sound: 'ui_back' });
    const head = h('div.sel-head', null, backBtn, h('div.sel-heading', { html: '<b>고수 선택<i class="hj">高手</i></b><em>CHOOSE YOUR MASTER</em>' }), steps);
    const cardsEl = h('div.sel-cards');
    const detail = h('div.sel-detail');
    const diff = segmented({ ko: '상대의 경지', en: 'CPU RANK', options: DIFFICULTIES, value: 'normal', cls: 'sel-diff', onChange: (v) => { st.diff = v; } });
    diff._act = () => begin();
    const beginBtn = ui.item(h('button.cta.sel-begin', { type: 'button', html: `<span class="ko">비무 시작</span><span class="en">BEGIN DUEL</span>${icon('dodge')}` }), { act: () => begin() });
    const foot = h('div.sel-foot', null, diff, beginBtn);
    const el = h('div', null, h('div.scr-shade.sel-shade'), head, h('div.sel-body', null, cardsEl, detail), foot);

    const st = { step: 'p1', p1: null, cpu: null, cpuRandom: false, diff: 'normal', cards: [], roster: [] };
    let detailFor = null;

    function card(f, idx) {
      // weapon line art on an ink wash, the sect emblem, the name written down a paper cartouche with the hero's seal
      const c = h(`button.card.el-${f.element}`, { type: 'button', 'aria-label': `${f.name} ${f.hanja || ''} ${f.nameEn || ''}` },
        h('i.card-glow'),
        h('div.card-art', { html: weaponArt(f.weaponArt || 'greatsword') }),
        h('div.card-sigil', { html: icon(f.emblem || f.element) }),
        h('div.card-tags', null, h('span.tag-p1', { text: '1P' }), h('span.tag-cpu', { text: 'CPU' })),
        h('div.card-cart', null, h('b.card-name', { 'data-name': f.name, html: brushText(f.name, { vertical: true, shadow: false, weight: 1.2, gap: 2 }) }), h('span.card-hanja', { text: f.hanja || '' }), h('i.card-seal', { html: seal(f.seal || (f.hanja || '').slice(0, 2), { seed: 5 }) })),
        h('div.card-id', null, h('span.card-title', { text: f.title }), h('span.card-ko', { text: [f.titleHanja, f.sect].filter(Boolean).join(' · ') })),
        h('i.card-frame'));
      c._idx = idx;
      c._onFocus = () => showDetail(f);
      return ui.item(c, { act: () => pick(idx) });
    }
    function randomCard() {
      const c = h('button.card.card-random', { type: 'button', 'aria-label': '무작위 Random' }, h('div.card-art', { html: icon('random') }), h('div.card-id', null, h('b.card-rname', { text: '천명' }), h('span.card-ko', { text: 'RANDOM' })), h('i.card-frame'));
      c._idx = -1;
      c._onFocus = () => showDetail(null);
      return ui.item(c, { act: () => pick(-1) });
    }

    function showDetail(f) {
      if (f === detailFor && detail.childElementCount) return;
      detailFor = f;
      if (!f) {
        detail.className = 'sel-detail is-random';
        detail.innerHTML = `${corners()}<div class="dt-random">${icon('random')}<b>천명에 맡긴다<i class="hj">天命</i></b><em>RANDOM — 상대는 하늘이 정한다 · leave it to fate</em></div>`;
        return;
      }
      const stats = STAT_ROWS.map(([k, ko, en]) => {
        const v = (f.stats && f.stats[k]) || 0;
        let pips = '';
        for (let i = 0; i < 5; i++) pips += `<i class="${i < v ? 'on' : ''}"></i>`;
        return `<div class="st-row"><span class="st-l">${esc(ko)}<em>${en}</em></span><span class="st-pips">${pips}</span></div>`;
      }).join('');
      const sk = (f.moves || []).filter((m) => /^skill|^ult/.test(m.slot)).map((m) => `
        <div class="dt-skill${m.slot === 'ult' ? ' is-ult' : ''}"><span class="dt-ico">${icon(m.icon || (m.slot === 'ult' ? 'ult' : 'light'))}</span>
          <span class="dt-sk-txt"><b>${kh(m.name, m.hanja)}</b><em>${esc(m.nameEn || '')}</em></span>
          <span class="dt-sk-meta">${m.slot === 'ult' ? '<span class="ult-chip">오의<i class="hj">奧義</i></span>' : `${m.cost ? `<span>내공 ${m.cost}</span>` : ''}${m.cd ? `<span>${m.cd}s</span>` : ''}`}</span>
          <span class="dt-sk-desc">${esc(m.desc || '')}</span></div>`).join('');
      detail.className = `sel-detail el-${f.element}`;
      detail.innerHTML = `${corners()}
        <div class="dt-head"><div class="dt-name"><b>${brushText(f.name, { weight: 1.22, gap: 3 })}</b><span>${esc(f.hanja || '')}</span><em>${esc(f.nameEn || '')}</em></div>
          <div class="dt-title">${kh(f.title, f.titleHanja)}<em>${esc(f.titleEn || '')}</em></div>
          <dl class="dt-lines">
            <div><dt>문파</dt><dd><span class="dt-emb">${icon(f.emblem || f.element)}</span>${kh(f.sect || '', f.sectHanja)}<em>${esc(f.sectEn || '')}</em></dd></div>
            <div><dt>병기</dt><dd>${kh(f.weapon, f.weaponHanja)}<em>${esc(f.weaponEn || '')}</em></dd></div>
            <div><dt>내공</dt><dd>${kh(f.art || '', f.artHanja)}<em>${esc(f.artEn || '')}</em></dd></div>
          </dl></div>
        <div class="dt-blurb">${esc(f.blurb || '')}</div>
        <div class="dt-stats">${stats}</div>
        <div class="dt-skills">${sk}</div>`;
    }

    function renderSteps() {
      const s = [['p1', '나의 고수', 'YOU'], ['cpu', '상대', 'OPPONENT'], ['diff', '경지', 'RANK']];
      const at = s.findIndex((x) => x[0] === st.step);
      steps.innerHTML = s.map((x, i) => `<span class="step${i === at ? ' on' : ''}${i < at ? ' done' : ''}"><i>${i + 1}</i><b>${x[1]}</b><em>${x[2]}</em></span>`).join('<span class="step-sep"></span>');
      for (const c of st.cards) {
        c.classList.toggle('is-p1', st.p1 !== null && c._idx === st.p1);
        c.classList.toggle('is-cpu', st.cpu !== null && ((st.cpuRandom && c._idx === -1) || (!st.cpuRandom && c._idx === st.cpu)));
      }
      beginBtn.classList.toggle('is-disabled', st.step !== 'diff');
      el.classList.toggle('picking-cpu', st.step === 'cpu');
    }

    function pick(idx) {
      const n = st.roster.length;
      const real = idx < 0 ? Math.floor(rng() * n) % n : idx;
      if (st.step === 'p1') {
        st.p1 = real;
        st.step = 'cpu';
        renderSteps();
        ui.focus(st.cards[(real + 1) % n], false);
        flashCard(st.cards[idx < 0 ? n : idx]);
      } else if (st.step === 'cpu') {
        st.cpu = real;
        st.cpuRandom = idx < 0;
        st.step = 'diff';
        renderSteps();
        flashCard(st.cards[idx < 0 ? n : idx]);
        ui.focus(diff, false);
      } else begin();
    }
    function flashCard(c) {
      if (!c) return;
      const g = c.querySelector('.card-glow');
      if (!g) return;
      anim.add(0.6, (k) => { g.style.opacity = (1 - k).toFixed(3); g.style.transform = `scale(${(1 + 0.2 * k).toFixed(3)})`; }, { key: g, ease: 'outCubic' });
    }
    function begin() {
      if (st.step !== 'diff' || st.p1 === null || st.cpu === null) return;
      ui.emit('pick', { p1: st.roster[st.p1].id, cpu: st.roster[st.cpu].id, difficulty: diff.value, random: st.cpuRandom });
    }

    const sel = {
      el,
      enter(d) {
        st.roster = d.roster || ui.roster;
        ui.roster = st.roster;
        cardsEl.innerHTML = '';
        st.cards = st.roster.map(card);
        st.cards.push(randomCard());
        cardsEl.append(...st.cards);
        const idxOf = (id) => st.roster.findIndex((r) => r.id === id);
        st.p1 = d.p1 ? idxOf(d.p1) : null;
        st.cpu = d.cpu ? idxOf(d.cpu) : null;
        if (st.p1 < 0) st.p1 = null;
        if (st.cpu < 0) st.cpu = null;
        st.cpuRandom = false;
        st.diff = d.difficulty || st.diff || 'normal';
        diff.set(st.diff);
        st.step = d.step || (st.p1 === null ? 'p1' : st.cpu === null ? 'cpu' : 'diff');
        detailFor = undefined;
        renderSteps();
        ui.setItems([backBtn, ...st.cards, diff, beginBtn], st.step === 'diff' ? diff : st.cards[st.step === 'cpu' ? (st.p1 + 1) % st.roster.length : st.p1 || 0]);
        if (!ui.focused() || !ui.focused()._onFocus) showDetail(st.roster[st.p1 || 0]);
        rise([head], { dur: 0.45, dist: -10 });
        rise(st.cards, { delay: 0.08, step: 0.07, dist: 26, dur: 0.55 });
        rise([detail, foot], { delay: 0.25, step: 0.08, dist: 14, dur: 0.5 });
      },
      back() {
        if (st.step === 'diff') { st.step = 'cpu'; st.cpu = null; st.cpuRandom = false; renderSteps(); ui.focus(st.cards[(st.p1 + 1) % st.roster.length], false); }
        else if (st.step === 'cpu') { const p = st.p1; st.step = 'p1'; st.p1 = null; renderSteps(); ui.focus(st.cards[p], false); }
        else ui.emit('back', 'select');
      },
    };
    return sel;
  })();

  // ---------------------------------------------------------------------------------------------------------------
  // VERSUS

  const vs = (() => {
    const half = (s) => {
      const art = h('div.vs-art');
      const id = h('div.vs-id');
      const el = h(`div.vs-half.${s}`, null, h('i.vs-tint'), art, id);
      return { el, art, id };
    };
    const A = half('p1'), B = half('p2');
    const seam = h('i.vs-seam');
    const flash = h('i.vs-flash');
    const vsMark = h('div.vs-mark', { html: eclipseMark('small') });
    const vsTxt = h('div.vs-txt', { html: `${brushText('대', { weight: 1.25, fill: ['#fffaf0', '#e2d6bb'] })}<i class="vs-seal">${seal('對', { seed: 9 })}</i>` });
    const mid = h('div.vs-mid', null, vsMark, vsTxt);
    const foot = h('div.vs-foot');
    const el = h('div', null, A.el, B.el, seam, flash, mid, foot);
    let t = 0, dur = 3, done = false, portrait = false, seamDeg = 14;
    const fill = (side, f, tag) => {
      side.el.className = `vs-half ${side === A ? 'p1' : 'p2'} el-${f.element}`;
      side.art.innerHTML = weaponArt(f.weaponArt || 'greatsword');
      side.id.innerHTML = `<span class="vs-tag">${esc(tag)}</span><b class="vs-name" aria-label="${esc(f.name)}">${brushText(f.name, { weight: 1.12, gap: 3, fill: ['#fffaf0', '#dccfb4'] })}</b>
        <span class="vs-ko"><i class="vs-hseal">${seal(f.seal || (f.hanja || '').slice(0, 2), { seed: 5 })}</i>${esc(f.hanja || '')}<em>${esc(f.nameEn || '')}</em></span>
        <span class="vs-title">${kh(f.title, f.titleHanja)}<em>${esc(f.titleEn || '')}</em></span>
        <span class="vs-sect"><span class="vs-emb">${icon(f.emblem || f.element)}</span>${kh(f.sect || '', f.sectHanja)} · ${kh(f.art || '', f.artHanja)}</span>`;
    };
    return {
      el,
      enter(d) {
        const p1 = fighterOf(d.p1) || ui.roster[0], p2 = fighterOf(d.p2) || ui.roster[1];
        fill(A, p1, '1P');
        fill(B, p2, 'CPU');
        const df = DIFFICULTIES.find((x) => x.value === d.difficulty);
        const arena = d.arena ? { arena: d.arena, arenaHanja: d.arenaHanja || '', arenaEn: d.arenaEn || '' } : ARENA;
        foot.innerHTML = `<span class="vs-arena">비무대 <b>${kh(arena.arena, arena.arenaHanja)}</b><em>${esc(arena.arenaEn)}</em></span>${df ? `<span class="vs-diff">상대의 경지 <b>${kh(df.name, df.hanja)}</b><em>${df.nameEn}</em></span>` : ''}`;
        t = 0; dur = d.duration || 3.2; done = false;
        this.update(0);
      },
      update(dt) {
        t += dt;
        const inA = Ease.outQuart(clamp(t / 0.45));
        const late = Ease.outCubic(clamp((t - 0.35) / 0.5));
        const ax = portrait ? 'translateY' : 'translateX';
        put(A.el, 'transform', `${ax}(${(-100 * (1 - inA)).toFixed(2)}%)`);
        put(B.el, 'transform', `${ax}(${(100 * (1 - inA)).toFixed(2)}%)`);
        // slow push on the art while the splash holds
        const rot = portrait ? 62 : 18;
        put(A.art, 'transform', `translateX(${(-30 + 30 * late + t * 4).toFixed(1)}px) rotate(${-rot}deg)`);
        put(B.art, 'transform', `translateX(${(30 - 30 * late - t * 4).toFixed(1)}px) rotate(${rot}deg)`);
        put(A.id, 'opacity', late.toFixed(3)); put(B.id, 'opacity', late.toFixed(3));
        put(A.id, 'transform', `translateX(${(-40 * (1 - late)).toFixed(1)}px)`);
        put(B.id, 'transform', `translateX(${(40 * (1 - late)).toFixed(1)}px)`);
        const sm = clamp((t - 0.38) / 0.25);
        put(seam, 'transform', `rotate(${seamDeg.toFixed(2)}deg) scaleY(${Ease.outExpo(sm).toFixed(3)})`);
        put(seam, 'opacity', (sm > 0 ? 1 : 0).toFixed(2));
        const fl = t > 0.45 ? 1 - clamp((t - 0.45) / 0.35) : 0;
        put(flash, 'opacity', (fl * 0.7).toFixed(3));
        const vm = clamp((t - 0.45) / 0.22);
        put(mid, 'opacity', Math.min(1, vm * 1.5).toFixed(3));
        put(vsTxt, 'transform', `scale(${(2.4 - 1.4 * Ease.outQuart(vm)).toFixed(3)})`);
        put(vsMark, 'transform', `scale(${(0.6 + 0.4 * Ease.outCubic(vm)).toFixed(3)}) rotate(${(t * 3).toFixed(1)}deg)`);
        put(foot, 'opacity', clamp((t - 0.8) / 0.4).toFixed(3));
        if (!done && t >= dur) { done = true; ui.emit('vsDone'); }
      },
      onAction(action) {
        if ((action === 'confirm' || action === 'pause') && t > 0.8 && !done) { done = true; ui.emit('vsDone'); }
        return true;
      },
      layout(L) {
        portrait = L.portrait;
        // the seam follows the clip-path diagonal: 14% of the width across the height (or the reverse in portrait)
        seamDeg = portrait ? 90 - (Math.atan2(0.1 * L.H, L.W) * 180) / Math.PI : (Math.atan2(0.14 * L.W, L.H) * 180) / Math.PI;
      },
    };
  })();

  // ---------------------------------------------------------------------------------------------------------------
  // PAUSE

  const pause = (() => {
    let confirmTitle = false;
    const resume = menuBtn('계속 겨루기', 'RESUME', 'dodge', () => ui.emit('resume'));
    const moves = menuBtn('초식표', 'MOVE LIST', 'list', () => openMoves());
    const quality = segmented({ ko: '그래픽 품질', en: 'QUALITY', options: QUALITIES, value: qualityNow(), onChange: (v) => ui.emit('quality', v), cls: 'pz-quality' });
    const toTitle = menuBtn('산문으로', 'QUIT TO TITLE', 'home', () => {
      if (!confirmTitle) {
        confirmTitle = true;
        toTitle.classList.add('is-confirm');
        toTitle.querySelector('.mbtn-txt').innerHTML = bilingual('한 번 더 눌러 확인', 'PRESS AGAIN TO QUIT');
        return;
      }
      ui.emit('toTitle');
    }, 'is-danger');
    const panel = h('div.panel.pz-panel', { html: corners() }, h('div.ph', { html: `<b>숨 고르기</b><i class="ph-seal">${seal('調息', { seed: 13 })}</i><em>PAUSED</em>` }), h('div.ph-rule', { html: divider({ seed: 14 }) }), h('div.pz-list', null, resume, moves, quality, toTitle));
    const emblem = h('div.pz-emblem', { html: eclipseMark() });
    const el = h('div', null, h('div.scr-shade.pz-shade'), emblem, panel);
    let t = 0;
    let data = {};
    function openMoves() { ui.show('movelist', { fighters: data.fighters, index: 0, fromPause: true, pause: data }); }
    return {
      el,
      enter(d, prev) {
        data = d.fighters ? d : { ...d, fighters: [fighterOf(d.p1) || ui.roster[0], fighterOf(d.p2) || ui.roster[1]].filter(Boolean) };
        if (d.pause) data = d.pause;
        confirmTitle = false;
        toTitle.classList.remove('is-confirm');
        toTitle.querySelector('.mbtn-txt').innerHTML = bilingual('산문으로', 'QUIT TO TITLE');
        quality.set(d.quality || qualityNow());
        ui.setItems([resume, moves, quality, toTitle], prev === 'movelist' ? moves : resume);
        if (prev !== 'movelist') {
          panel.style.opacity = '0';
          anim.add(0.28, (k) => { panel.style.opacity = k.toFixed(3); panel.style.transform = `scale(${(0.96 + 0.04 * k).toFixed(4)})`; }, { key: panel, ease: 'outCubic' });
          t = 0;
        }
      },
      update(dt) {
        // the black sun behind the panel turns slowly while the fight is frozen
        t += dt;
        put(emblem, 'transform', `rotate(${(t * 2).toFixed(2)}deg) scale(${(0.94 + 0.06 * Ease.outCubic(clamp(t / 0.6))).toFixed(4)})`);
        put(emblem, 'opacity', (0.2 * clamp(t / 0.4)).toFixed(3));
      },
      back() { ui.emit('resume'); },
      onAction(action) {
        if (action === 'pause') { ui.sound('ui_back'); ui.emit('resume'); return true; }
        if (confirmTitle && action !== 'confirm' && ui.focused() !== toTitle) { confirmTitle = false; toTitle.classList.remove('is-confirm'); toTitle.querySelector('.mbtn-txt').innerHTML = bilingual('산문으로', 'QUIT TO TITLE'); }
        return false;
      },
    };
  })();

  // ---------------------------------------------------------------------------------------------------------------
  // MOVE LIST

  const movelist = (() => {
    const tabs = h('div.ml-tabs');
    const body = h('div.ml-body');
    const legend = h('div.ml-legend');
    const backBtn = ui.item(h('button.icon-btn.ml-back', { type: 'button', 'aria-label': '뒤로 Back', html: icon('back') }), { act: () => ml.back(), sound: 'ui_back' });
    const panel = h('div.panel.ml-panel', { html: corners() }, h('div.ml-top', null, backBtn, h('div.ph', { html: '<b>초식표<i class="hj">招式表</i></b><em>MOVE LIST</em>' }), tabs), body, legend);
    const el = h('div', null, h('div.scr-shade.ml-shade'), panel);
    let data = {}, list = [], idx = 0, tabEls = [];

    const kc = (k) => keycap(ctx.input ? ctx.input.keyLabel(k, 0, 'keyboard') : k.toUpperCase());
    const tg = (ico, cls = '') => `<span class="tglyph ${cls}">${icon(ico)}</span>`;
    const arrow = (dir) => `<span class="dirchip">${dir === 'f' ? '→' : '↓'}<em>${dir === 'f' ? '앞' : '아래'}</em></span>`;
    const plus = '<i class="plus">+</i>', then = '<i class="then">›</i>';
    function inputs(m) {
      const s = m.slot;
      const L = kc('light'), H = kc('heavy');
      const tL = tg('light'), tH = tg('heavy');
      switch (s) {
        case 'light1': return [L, tL];
        case 'light2': return [L + then + L, tL + then + tL];
        case 'light3': return [L + then + L + then + L, tL + then + tL + then + tL];
        case 'heavy': return [H, tH];
        case 'fheavy': return [arrow('f') + plus + H, `<span class="tstick">${icon('stick')}</span>` + plus + tH];
        case 'dheavy': return [arrow('d') + plus + H, `<span class="tstick down">${icon('stick')}</span>` + plus + tH];
        case 'skill1': case 'skill2': case 'skill3': return [kc(s), tg(m.icon || 'light', 'tg-sk')];
        case 'ult': return [kc('ult'), tg('ult', 'tg-ul')];
        default: return ['', ''];
      }
    }
    function render() {
      const f = list[idx];
      tabEls.forEach((t, i) => t.classList.toggle('on', i === idx));
      if (!f) { body.innerHTML = ''; return; }
      panel.className = `panel ml-panel el-${f.element}`;
      const groups = [['기본 초식', '', 'BASIC FORMS', (m) => /^light|heavy/.test(m.slot)], ['절기', '絶技', 'SKILLS', (m) => /^skill/.test(m.slot)], ['오의', '奧義', 'ULTIMATE', (m) => m.slot === 'ult']];
      body.innerHTML = `<div class="ml-who"><b>${brushText(f.name, { weight: 1.24, gap: 3 })}</b><span>${esc(f.hanja || '')} · ${kh(f.title, f.titleHanja)} · ${kh(f.sect || '', f.sectHanja)}</span>${elemTag(f.element)}</div>` + groups.map(([ko, hj, en, fn]) => {
        const rows = (f.moves || []).filter(fn).map((m) => {
          const [k, t] = inputs(m);
          const meta = m.slot === 'ult' ? '<span class="ult-chip">오의 100</span>' : m.cost ? `<span class="meta">내공 ${m.cost}${m.cd ? ` · ${m.cd}s` : ''}</span>` : '';
          return `<div class="ml-row${m.slot === 'ult' ? ' is-ult' : ''}"><span class="ml-name"><b>${kh(m.name, m.hanja)}</b><em>${esc(m.nameEn || '')}</em>${meta}</span><span class="ml-desc">${esc(m.desc || '')}</span><span class="ml-in kb">${k}</span><span class="ml-in tc">${t}</span></div>`;
        }).join('');
        return `<div class="ml-group"><div class="ml-gh"><b>${kh(ko, hj)}</b><em>${en}</em><span class="ml-colh"><span>키보드 KEYBOARD</span><span>터치 TOUCH</span></span></div>${rows}</div>`;
      }).join('') + `<div class="ml-group ml-common"><div class="ml-gh"><b>${kh('신법', '身法')}</b><em>COMMON</em></div>
        <div class="ml-row"><span class="ml-name"><b>${kh('호신강기', '護身罡氣')}</b><em>Guard</em></span><span class="ml-desc">누르는 동안 기운으로 막는다 · hold</span><span class="ml-in kb">${kc('guard')}</span><span class="ml-in tc">${tg('guard')}</span></div>
        <div class="ml-row"><span class="ml-name"><b>${kh('경공', '輕功')}</b><em>Dodge</em></span><span class="ml-desc">짧게 몸을 날려 피한다 · i-frames</span><span class="ml-in kb">${kc('dodge')}</span><span class="ml-in tc">${tg('dodge')}</span></div></div>`;
      body.scrollTop = 0;
    }
    const ml = {
      el,
      enter(d) {
        data = d;
        list = (d.fighters && d.fighters.length ? d.fighters : ui.roster).map(fighterOf).filter(Boolean);
        // tabs: the fighters in this match first, then the rest of the roster
        if (d.fromPause) for (const r of ui.roster) if (!list.includes(r)) list.push(r);
        idx = clamp(d.index || 0, 0, list.length - 1);
        tabs.innerHTML = '';
        tabEls = list.map((f, i) => ui.item(h(`button.ml-tab.el-${f.element}`, { type: 'button', html: `${icon(f.emblem || f.element)}<b>${esc(f.name)}</b><span>${esc(f.hanja || '')}</span>` }), { act: () => { idx = i; render(); } }));
        tabEls.forEach((t, i) => { t._lr = (dd) => { idx = (idx + dd + list.length) % list.length; render(); ui.focus(tabEls[idx], false); }; tabs.appendChild(t); t._i = i; });
        legend.innerHTML = '<span><span class="dirchip">→<em>앞</em></span> 상대 방향 · toward the opponent</span><span><i class="then">›</i> 이어서 · then</span><span><i class="plus">+</i> 동시에 · together</span>';
        render();
        ui.setItems([backBtn, ...tabEls], tabEls[idx]);
        rise([panel], { dist: 12, dur: 0.35 });
      },
      back() {
        if (data.fromPause) ui.show('pause', { pause: data.pause });
        else ui.emit('back', 'movelist');
      },
      onAction(action) {
        if (action === 'up' || action === 'down') { body.scrollTop += action === 'down' ? 80 : -80; return true; }
        if (action === 'pause') { ml.back(); return true; }
        return false;
      },
    };
    return ml;
  })();

  // ---------------------------------------------------------------------------------------------------------------
  // RESULT

  const result = (() => {
    const art = h('div.rs-art');
    const kicker = h('div.rs-kicker');
    const name = h('div.rs-name');
    const sub = h('div.rs-sub');
    const score = h('div.rs-score');
    const rounds = h('div.rs-rounds');
    const stats = h('div.rs-stats');
    const rematch = menuBtn('다시 겨루기', 'REMATCH', 'rematch', () => ui.emit('rematch'));
    const reselect = menuBtn('고수 선택', 'CHOOSE MASTER', 'people', () => ui.emit('select'));
    const toTitle = menuBtn('산문으로', 'TITLE', 'home', () => ui.emit('toTitle'));
    const menu = h('div.rs-menu', null, rematch, reselect, toTitle);
    const halo = h('div.rs-halo', { html: eclipseMark() });
    const blot = h('i.rs-blot', { html: splash({ seed: 23 }) });
    const main = h('div.rs-main', null, halo, blot, kicker, name, sub, score, rounds, stats);
    const el = h('div', null, h('i.rs-tint'), art, h('div.scr-shade.rs-shade'), h('div.rs-wrap', null, main, menu));
    const howName = { ko: ['결', '決'], time: ['향진', '香盡'], perfect: ['무결', '無缺'], draw: ['무승부', ''] };
    // the verdict, written large with its seal: 승 勝 / 패 敗 from the player's side
    const verdict = (w) => (w === 0 ? ['승', '勝', 'VICTORY'] : w === 1 ? ['패', '敗', 'DEFEAT'] : ['무승부', '和', 'DRAW']);
    return {
      el,
      enter(d) {
        const p1 = fighterOf(d.p1) || ui.roster[0], p2 = fighterOf(d.p2) || ui.roster[1];
        const w = d.winner === 0 ? p1 : d.winner === 1 ? p2 : null;
        el.className = `scr scr-result ${w ? 'el-' + w.element : 'is-draw'} ${d.winner === 0 ? 'is-win' : d.winner === 1 ? 'is-lose' : ''}`;
        art.innerHTML = w ? weaponArt(w.weaponArt) : eclipseMark();
        const [vk, vh, ve] = verdict(d.winner);
        kicker.innerHTML = `<b class="rs-verdict" aria-label="${vk}">${brushText(vk, { weight: 1.2, gap: 2, fill: d.winner === 1 ? ['#ffe9e2', '#e58a7a'] : ['#fffaf0', '#e6d6ae'] })}</b><i class="rs-seal">${seal(vh, { seed: 17 })}</i><span class="en">${ve}</span>`;
        name.innerHTML = w ? `<b aria-label="${esc(w.name)}">${brushText(w.name, { weight: 1.14, gap: 3, fill: ['#fffaf0', '#dccfb4'] })}</b><span>${esc(w.hanja || '')}<em>${esc(w.nameEn || '')}</em></span>` : `<b>${brushText('비김', { weight: 1.14, gap: 3 })}</b><span>승부를 가리지 못했다<em>DRAW</em></span>`;
        sub.innerHTML = w ? `${kh(w.title, w.titleHanja)} <em>${esc(w.titleEn || '')}</em> · ${kh(w.sect || '', w.sectHanja)} — ${d.winner === 0 ? '승' : 'CPU 승'}` : '';
        const sc = d.score || [0, 0];
        score.innerHTML = `<span class="sc-side"><em>1P</em><b>${esc(p1.name)}</b></span><span class="sc-num">${sc[0]}</span><i>:</i><span class="sc-num">${sc[1]}</span><span class="sc-side r"><em>CPU</em><b>${esc(p2.name)}</b></span>`;
        rounds.innerHTML = (d.rounds || []).map((r, i) => {
          const hw = howName[r.how] || ['', ''];
          const who = r.winner === 0 ? p1 : r.winner === 1 ? p2 : null;
          return `<span class="rd ${who ? 'el-' + who.element : ''} ${r.winner === 0 ? 'w1' : r.winner === 1 ? 'w2' : 'wd'}"><em>제${i + 1}합</em><b>${kh(hw[0], hw[1])}</b><span>${who ? esc(who.name) : '—'}</span></span>`;
        }).join('');
        const s1 = (d.stats && d.stats.p1) || null;
        stats.innerHTML = s1 ? [['최대 연환', 'MAX COMBO', s1.maxCombo], ['입힌 피해', 'DAMAGE', s1.damage], ['오의', 'ULTIMATES', s1.ults], ['남은 기혈', 'HP LEFT', s1.hpLeft !== undefined ? s1.hpLeft + '%' : undefined]]
          .filter((x) => x[2] !== undefined).map((x) => `<span class="stat"><em>${x[0]} · ${x[1]}</em><b>${typeof x[2] === 'number' ? x[2].toLocaleString('en-US') : esc(x[2])}</b></span>`).join('') : '';
        stats.style.display = s1 ? '' : 'none';
        ui.setItems([rematch, reselect, toTitle], rematch);
        art.style.opacity = '0';
        anim.add(1.4, (k) => { art.style.opacity = k.toFixed(3); art.style.transform = `translate(-50%,-50%) rotate(${(-24 + 6 * k).toFixed(2)}deg) scale(${(1.12 - 0.12 * k).toFixed(4)})`; }, { key: art, ease: 'outCubic' });
        halo.style.opacity = '0';
        anim.add(1.6, (k) => { halo.style.opacity = (0.5 * Math.min(1, k * 1.5)).toFixed(3); halo.style.transform = `rotate(${(-30 + 30 * k).toFixed(2)}deg) scale(${(0.7 + 0.3 * k).toFixed(4)})`; }, { key: halo, delay: 0.1, ease: 'outCubic' });
        // brush-in: the ink blot lands, the verdict is written over it, then the seal is stamped
        blot.style.opacity = '0';
        anim.add(0.5, (k) => { blot.style.opacity = (0.9 * Math.min(1, k * 2)).toFixed(3); blot.style.transform = `scale(${(0.5 + 0.5 * k).toFixed(4)})`; }, { key: blot, ease: 'outQuart' });
        const mark = kicker.firstChild, stamp = mark.nextSibling, en = kicker.lastChild;
        mark.style.opacity = '0';
        anim.add(0.36, (k) => { mark.style.opacity = Math.min(1, k * 2).toFixed(3); mark.style.transform = k < 1 ? `scale(${(2.2 - 1.2 * k).toFixed(4)})` : ''; }, { key: mark, delay: 0.08, ease: 'outQuart' });
        stamp.style.opacity = '0';
        anim.add(0.3, (k) => { stamp.style.opacity = Math.min(1, k * 2.5).toFixed(3); stamp.style.transform = k < 1 ? `scale(${(1.9 - 0.9 * k).toFixed(4)}) rotate(${(-10 * (1 - k)).toFixed(2)}deg)` : ''; }, { key: stamp, delay: 0.5, ease: 'outQuart' });
        rise([en], { delay: 0.6, dist: 8, dur: 0.4 });
        name.style.opacity = '0';
        anim.add(0.7, (k) => { name.style.opacity = Math.min(1, k * 1.4).toFixed(3); name.style.transform = k < 1 ? `translateX(${(-26 * (1 - k)).toFixed(1)}px)` : ''; }, { key: name, delay: 0.3, ease: 'outQuart' });
        rise([sub, score, rounds, stats], { delay: 0.45, step: 0.08, dist: 12, dur: 0.5 });
        rise([rematch, reselect, toTitle], { delay: 0.7, step: 0.07, dist: 12, dur: 0.45 });
      },
    };
  })();

  return { title, select, vs, pause, movelist, result };
}
