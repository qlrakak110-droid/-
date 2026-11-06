// ============================================================================
//  game: state, dialogue, story, menus, main loop
// ============================================================================
const SAVE_KEY = 'void-being-save-v1';
function newState() {
  return { v: 1, party: [], box: [], items: { crystal: 0, potion: 0, elixir: 0, origin: 0 }, flags: {}, dex: { seen: {}, caught: {} }, pos: { x: SITES.spawn.x, z: SITES.spawn.z }, yaw: 0 };
}
let S = newState();
function loadSave() { try { const s = JSON.parse(localStorage.getItem(SAVE_KEY) || 'null'); if (s && s.v === 1 && s.party) return s; } catch (e) {} return null; }
function save() {
  try {
    const p = World.player.root.position; S.pos = { x: p.x, z: p.z }; S.yaw = World.camYaw;
    localStorage.setItem(SAVE_KEY, JSON.stringify(S));
    const ind = document.getElementById('saveInd');
    if (ind && G.mode === 'world') { ind.classList.add('on'); clearTimeout(save.t); save.t = setTimeout(() => ind.classList.remove('on'), 1600); }
  } catch (e) {}
}
const G = { mode: 'loading', busy: false, dialog: 0, lock: 0, encDist: 0, encNext: 9, near: null, t: 0 };
function canMove() { return G.mode === 'world' && !G.busy && !G.dialog && $('#modal').hidden && G.lock <= 0; }

// ---------------------------------------------------------------- dialogue
$('#dialog').addEventListener('click', (e) => { if (e.target.closest('#dChoices')) return; fireAction(); });
async function typeLine(text) {
  const el = $('#dTxt'); el.textContent = '';
  let skipped = false; const p = nextAction().then(() => { skipped = true; });
  for (let i = 1; i <= text.length && !skipped; i++) {
    el.textContent = text.slice(0, i);
    if (i % 3 === 0 && text[i - 1] !== ' ') Snd.fx('talk');
    await sleep(text[i - 1] === '.' || text[i - 1] === '…' ? 70 : 24);
  }
  el.textContent = text;
  if (skipped) await nextAction(); else await p;
}
// who is speaking: name plate + portrait (people get a rendered head shot, spirits their icon)
function speakerPortrait(who) {
  if (!who) return null;
  const n = NPC_DEFS.find((d) => d.name === who);
  if (n) return { src: Icons.portrait(n.id, n.look) };
  if (who === '???') return { src: Icons.get('nihilos'), cls: 'sil' };
  const sp = Object.keys(SPECIES).find((k) => SPECIES[k].n === who);
  return sp ? { src: Icons.get(sp) } : null;
}
function setSpeaker(who, cls) {
  $('#dWho').textContent = who; $('#dWho').className = cls;
  const p = speakerPortrait(who), img = $('#dPort');
  if (p && p.src) { if (img.getAttribute('src') !== p.src) img.src = p.src; img.className = p.cls || cls || ''; img.hidden = false; }
  else img.hidden = true;
}
async function say(lines, who = '', cls = '') {
  G.dialog++;
  $('#dialog').hidden = false; $('#dChoices').innerHTML = ''; $('#dNext').hidden = false;
  for (const ln of [].concat(lines)) {
    const o = typeof ln === 'string' ? { t: ln } : ln;
    setSpeaker(o.who ?? who, o.cls ?? cls);
    await typeLine(o.t);
  }
  $('#dialog').hidden = true; G.dialog--; G.lock = 0.25; Input.actionQueued = false;
}
async function ask(text, options, who = '', cls = '') {
  G.dialog++;
  $('#dialog').hidden = false; setSpeaker(who, cls); $('#dNext').hidden = true; $('#dChoices').innerHTML = '';
  const el = $('#dTxt'); el.textContent = '';
  for (let i = 1; i <= text.length; i++) { el.textContent = text.slice(0, i); if (i % 3 === 0) Snd.fx('talk'); await sleep(18); }
  const v = await new Promise((res) => {
    const btns = options.map((o, i) => {
      const b = document.createElement('button'); b.textContent = o;
      b.addEventListener('click', () => { Snd.fx('select'); hotkeyHandler = null; res(i); });
      $('#dChoices').appendChild(b); return b;
    });
    if (!isTouch) btns[0].focus({ preventScroll: true });
    hotkeyHandler = (code) => {
      const n = parseInt(code.replace('Digit', ''), 10); if (btns[n - 1]) btns[n - 1].click();
      if (code.startsWith('Arrow')) { let i = btns.indexOf(document.activeElement); i = (i + (code === 'ArrowRight' || code === 'ArrowDown' ? 1 : -1) + btns.length) % btns.length; btns[i].focus(); }
      if ((code === 'KeyE' || code === 'KeyZ') && btns.includes(document.activeElement)) document.activeElement.click();
    };
  });
  $('#dChoices').innerHTML = ''; $('#dialog').hidden = true; G.dialog--; G.lock = 0.25; Input.actionQueued = false;
  return v;
}
function toast(t) { const d = document.createElement('div'); d.className = 'toast'; d.textContent = t; $('#toasts').appendChild(d); setTimeout(() => d.remove(), 3300); }
async function banner(b1, b2, cls = 'plain', hold = 2.2) {
  const el = $('#banner'); el.className = cls; el.querySelector('.b1').textContent = b1; el.querySelector('.b2').textContent = b2;
  el.style.opacity = '1'; await wait(hold); el.style.opacity = '0'; await wait(0.6);
}
function fadeTo(v, dur = 0.6) { const f = $('#fade'); f.style.transitionDuration = dur + 's'; f.style.opacity = String(v); return sleep(dur * 1000 + 30); }

// ---------------------------------------------------------------- HUD
function questInfo() {
  if (!S.party.length) return ['장로 무연과 이야기하기', '마을 광장, 분수 앞의 노인'];
  if (S.flags.ending) return [`자유 탐험 · 도감 ${Object.keys(S.dex.caught).length}/${DEX_ORDER.length}`, '하늘은 닫혔다. 아직 만나지 못한 정령이 있다.'];
  const k = fragCount();
  if (k < 3) return [`균열의 수호자를 넘어 존재의 파편 모으기 (${k}/3)`, '남은 균열: ' + SITES.rifts.filter((r) => !S.flags['closed_' + r.id]).map((r) => r.name).join(' · ')];
  if (!S.flags.nihilosDone) return [S.flags.awakened ? '근원의 제단에서 니힐로스와 맞서기' : '섬 중앙, 근원의 제단으로 가기', '금빛 표식이 떠 있는 언덕 위'];
  if (!S.flags.ensiaDone) return ['근원의 제단에서 엔시아와 맞서기', '빛이 내려온 곳'];
  return [`자유 탐험 · 도감 ${Object.keys(S.dex.caught).length}/${DEX_ORDER.length}`, '하늘은 닫혔다. 아직 만나지 못한 정령이 있다.'];
}
function updateHud() {
  const [a, b] = questInfo(); $('#questText').textContent = a; $('#questSub').textContent = b;
  const legs = Object.keys(World.legends || {}).map((sp) => World.legendSites[sp].name);
  $('#questLeg').textContent = legs.length ? '✦ 전설의 기척: ' + legs.join(' · ') : '';
  const lc = $('#leadCard'), m = S.party[0];
  if (!m) { lc.hidden = true; return; }
  lc.hidden = false;
  const f = m.hp / maxHp(m);
  lc.innerHTML = `<img src="${Icons.get(m.sp)}" alt=""><div class="lc-body"><div class="lc-name">${monName(m)} <span>Lv.${m.lv} · ${m.hp}/${maxHp(m)}</span></div><div class="bar"><i style="width:${f * 100}%;background:${hpColor(f)}"></i></div></div>`;
}
function showHud(on = true) { $('#hud').hidden = !on; $('#touch').hidden = !on || !isTouch; if (on) updateHud(); }

// ---------------------------------------------------------------- story actors
const NPC_DEFS = [
  { id: 'elder', name: '장로 무연', x: 0, z: 55, face: Math.PI, look: { top: 0x6a5a8a, robe: true, hair: 0xe6e2ee, beard: 0xf2eef8, accent: 0xffd98a, pack: false, staff: 0xffd98a }, talk: talkElder },
  { id: 'healer', name: '샘지기 하나', x: -8.2, z: 47, face: Math.PI / 2, look: { top: 0xfafaff, bottom: 0x5a6a9a, accent: 0x5fd8ff, hair: 0x7a4a2a, long: true, pack: false }, pet: 'bandiru', talk: talkHealer },
  { id: 'kid', name: '꼬마 도윤', x: 6.5, z: 44, face: -Math.PI / 2, look: { top: 0xff9a3a, bottom: 0x3a5a8a, accent: 0xff6a6a, hair: 0x3a2a1a, hat: 'band', pack: true, kid: true, shirt: 0xfff4e0 }, pet: 'somgu', talk: talkKid },
  { id: 'traveler', name: '여행자 루아', x: 7.5, z: -27, face: -Math.PI / 2, look: { top: 0x4a8a6a, bottom: 0x2a2a3a, accent: 0xe8c063, hair: 0xc0603a, hat: 'wide', pack: true }, talk: talkTraveler },
  { id: 'g_east', name: '불씨 수호자 하람', rift: 'east', x: 53.5, z: 6.5, face: -Math.PI / 2, look: { top: 0xb8483a, robe: true, accent: 0xffb84a, hat: 'hood', staff: 0xff8a4c, pack: false, hair: 0x2a1a14 }, pet: 'bawimong', talk: talkGuardian,
    team: [['bawimong', 9], ['geurim', 9], ['hwarr', 11]],
    pre: ['멈춰라. 이 균열은 밤마다 넓어지고 있다.', '네가 이걸 닫을 자격이 있는지, 내 정령들이 시험하겠다!'],
    lose: '…좋다. 그 불꽃이라면 공허도 태울 수 있겠군.', after: '하늘의 금이 조금 옅어졌어. 다음 균열로 가라.' },
  { id: 'g_west', name: '파도 수호자 이든', rift: 'west', x: -53.5, z: 2.5, face: Math.PI / 2, look: { top: 0x2f5f9a, robe: true, accent: 0x5fd8ff, hat: 'hood', staff: 0x5fd8ff, pack: false, hair: 0xd8c08a }, pet: 'jjirit', talk: talkGuardian,
    team: [['jjirit', 11], ['mullong', 11], ['bandiru', 12]],
    pre: ['번개 습지에 온 걸 환영해! 균열에서 새어 나온 공허 때문에 바다가 울고 있어.', '내가 질 때만 지나가도 좋아. 준비됐지?'],
    lose: '하하, 졌다! 바다도 너를 응원하나 봐.', after: '바다가 다시 조용해졌어. 고마워!' },
  { id: 'g_north', name: '그림자 수호자 세레나', rift: 'north', x: 3.5, z: -57.5, face: 0, look: { top: 0x2e2248, robe: true, accent: 0xb48cff, hat: 'hood', staff: 0xb48cff, pack: false, hair: 0xe8e4f4, long: true }, pet: 'teum', talk: talkGuardian,
    team: [['geurim', 14], ['teum', 15], ['bawimong', 15]],
    pre: ['그림자는 공허와 가장 가까운 것. 그래서 나는 공허가 얼마나 굶주렸는지 알아.', '네가 그걸 마주할 수 있을지… 보여 줘.'],
    lose: '…그렇구나. 너는 사라지는 것을 두려워하지 않는구나.', after: '제단으로 가. 공허가 너를 기다리고 있어.' },
];

async function talkElder() {
  const W = '장로 무연';
  if (!S.party.length) {
    await say(['왔구나. 하늘의 금을 보았느냐?', '저것은 공허의 균열이다. 태초에 이 섬을 빚은 두 힘, 존재와 공허의 균형이 무너지고 있다는 뜻이지.', '섬 곳곳에 작은 균열이 열렸고, 세 수호자가 그 앞을 지키며 버티고 있다.', '혼자서는 무리다. 이 섬의 정령과 함께 가거라. 저 세 아이 중 하나를 골라 보렴.'], W);
    const sp = await starterSelect();
    S.flags.starter = sp;
    const m = makeMon(sp, 5); S.party.push(m); S.dex.seen[sp] = S.dex.caught[sp] = true;
    for (const s of STARTERS) S.dex.seen[s] = true;
    const pd = World.pedestals.find((p) => p.sp === sp);
    await starterJoin(pd);
    S.items.crystal += 5; S.items.potion += 3;
    await say([`${josa(SPECIES[sp].n, '이가')}… 좋은 눈이구나. 그 아이도 너를 고른 것 같다.`], W);
    toast('봉인결정 ×5 · 회복약 ×3을 받았다');
    await say(['풀숲에 들어가면 정령이 나타난다. 체력을 깎은 뒤 봉인결정을 던지면 동료로 삼을 수 있지.', '동쪽 불씨 언덕의 수호자 하람부터 찾아가 보거라. 세 수호자를 넘어서면 존재의 파편을 얻을 것이다.', '파편 셋이 모이면 섬 한가운데, 근원의 제단으로 가거라. 그곳에서… 아니, 그건 그때 이야기하자.'], W);
    refreshMarkers(); updateHud(); save();
    return;
  }
  const k = fragCount();
  if (S.flags.ending) return say(['하늘이 닫혔구나. 존재와 공허, 두 힘이 모두 너를 인정했다.', '고맙다, 경계의 아이야. 이제 섬은 숨을 쉴 수 있다.'], W);
  if (S.flags.awakened) return say(['니힐로스가 깨어났구나… 공허는 악이 아니다. 존재가 너무 많아지면 세계는 숨 쉴 곳을 잃지.', '하지만 지금의 공허는 굶주려 있다. 빛과 존재의 힘이 공허에 잘 통한다는 것을 잊지 마라.'], W);
  if (k >= 3) return say(['파편이 모두 모였구나. 제단으로 가거라.', '무엇이 기다리든, 네 정령들을 믿거라. 샘지기에게 들르는 것도 잊지 말고.'], W);
  return say([`남은 균열은 ${3 - k}개다. 수호자들은 균열의 힘을 빌려 점점 강해지고 있지.`, '상성을 잘 생각하거라. 공허에는 빛과 존재가, 존재에는 공허와 그림자가 강하다.', '이 섬의 정령은 열여섯. 많이 만날수록 길이 보일 것이다.'], W);
}
async function talkHealer(n) {
  await say(['정령들이 지쳐 보이네. 잠깐 쉬어 가렴.'], n.name);
  await healAll(true);
  const gifts = [];
  if (S.items.crystal < 5) { gifts.push(`봉인결정 ×${5 - S.items.crystal}`); S.items.crystal = 5; }
  if (S.items.potion < 3) { gifts.push(`회복약 ×${3 - S.items.potion}`); S.items.potion = 3; }
  const legendWaiting = (S.flags.awakened && (!S.dex.caught.nihilos || !S.dex.caught.ensia)) || Object.keys(World.legends || {}).length > 0;
  if (legendWaiting && S.items.origin < 2) { gifts.push(`근원결정 ×${3 - S.items.origin}`); S.items.origin = 3; }
  if (gifts.length) { toast(gifts.join(' · ') + '을(를) 받았다'); await say(['모자란 건 채워 뒀어. 조심해서 다녀와!'], n.name); }
  else await say(['언제든 다시 오렴. 샘물은 마르지 않으니까.'], n.name);
  save();
}
async function healAll(fx) {
  for (const m of S.party.concat(S.box)) { m.hp = maxHp(m); m.status = null; }
  if (fx) {
    Snd.fx('heal');
    const p = World.player.root.position;
    World.fx.burst(new THREE.Vector3(p.x, p.y + 1, p.z), 60, { color: [0x9dffb0, 0x8ff3ff, 0xffffff], speed: 3, size: 0.35, life: 1.2, up: 2 });
    toast('정령들의 체력이 모두 회복되었다');
  }
  updateHud();
}
let kidIdx = 0;
async function talkKid(n) {
  const tips = ['있잖아, 풀숲에 들어가면 정령이 튀어나와! 체력을 빨간색까지 깎으면 봉인이 훨씬 잘 된대.', '마비나 화상에 걸린 정령은 봉인하기가 더 쉬워!', '별씨라는 정령은 제단 근처 풀숲에서만 아주 가끔 나온대. 공허한테 엄청 강하다던데?', '화면을 끌면 시점이 돌아가! 휠이나 두 손가락으로 확대도 돼.', '정령 메뉴에서 맨 앞에 세운 정령이 너를 졸졸 따라다녀. 귀엽지?'];
  await say([tips[kidIdx++ % tips.length]], n.name);
}
async function talkTraveler(n) {
  if (!S.flags.travelerGift) {
    await say(['오, 여기까지 오다니. 이 길 끝에 마지막 균열이 있어.', '그림자 수호자는 만만치 않아. 이거 가져가.'], n.name);
    S.items.elixir += 2; S.flags.travelerGift = true; toast('고급회복약 ×2를 받았다'); save(); return;
  }
  await say(['밤하늘의 금이 생긴 뒤로 별이 조금씩 사라지고 있어. 너는 그걸 막을 수 있을까?'], n.name);
}
async function talkGuardian(n) {
  const closed = S.flags['closed_' + n.rift];
  if (closed) return say([n.after], n.name);
  if (!S.party.length) return say(['정령도 없이 여기까지 온 거야? 마을로 돌아가.'], n.name);
  await say(n.pre, n.name);
  const c = await ask('승부를 받아들일까?', ['승부한다', '아직은…'], n.name);
  if (c !== 0) return say(['준비가 되면 다시 와.'], n.name);
  const k = fragCount();
  const foes = n.team.map(([sp, lv]) => makeMon(sp, lv + k * 2));
  const res = await battleFlow({ kind: 'trainer', foes, trainer: { name: n.name, lose: n.lose }, theme: 'rift', music: 'battle' });
  if (res === 'win') await closeRift(n);
}
async function closeRift(n) {
  G.busy = true;
  const o = World.rifts[n.rift], rp = o.g.position;
  await say([n.lose.length ? '균열을 닫자. 네 정령의 힘을 빌려줘.' : ''], n.name);
  World.cine = { pos: new THREE.Vector3(rp.x + (World.player.root.position.x - rp.x) * 0.9, rp.y + 6, rp.z + (World.player.root.position.z - rp.z) * 0.9 + 4), look: new THREE.Vector3(rp.x, rp.y + 4, rp.z), k: 2 };
  await wait(1.0);
  Snd.fx('rumble'); World.shake = 1.2;
  await Tw.add(1.6, (k) => { o.U.uOpen.value = 1 - k; o.open = 1 - k; o.shards.scale.setScalar(1 - k); }, ease.in);
  o.tear.visible = o.pts.visible = o.shards.visible = false;
  Snd.fx('fragment');
  const c = new THREE.Vector3(rp.x, rp.y + 4.4, rp.z);
  World.fx.burst(c, 160, { color: [0xffd98a, 0xffffff, 0xc77dff], speed: 10, size: 0.6, life: 1.4 });
  o.bloom.visible = true;
  S.flags['closed_' + n.rift] = true;
  World.healTarget = fragCount() / 3;
  recolorTerrain();
  const frag = part(GEO.octa, E(0xffd98a, 3.2), World.scene, [c.x, c.y, c.z], [0.35, 0.6, 0.35]);
  await wait(0.6);
  const pp = World.player.root.position;
  await Tw.add(1.1, (k) => { frag.position.lerpVectors(c, new THREE.Vector3(pp.x, pp.y + 1.5, pp.z), k); frag.position.y += Math.sin(k * Math.PI) * 3; frag.rotation.y += 0.2; }, ease.inOut);
  World.scene.remove(frag);
  World.fx.burst(new THREE.Vector3(pp.x, pp.y + 1.2, pp.z), 60, { color: [0xffd98a, 0xffffff], speed: 4, size: 0.4, life: 1, up: 2 });
  World.cine = null;
  S.items.potion += 2; S.items.crystal += 3;
  toast(`존재의 파편을 얻었다 (${fragCount()}/3)`);
  await say([`존재의 파편을 얻었다! (${fragCount()}/3)`, '하늘의 균열이 조금 가늘어졌다.'], '');
  toast('회복약 ×2 · 봉인결정 ×3을 받았다');
  placeRiftState(); refreshMarkers(); updateHud();
  if (fragCount() === 3) await say(['세 개의 파편이 공명하고 있다… 섬 한가운데, 근원의 제단이 부르고 있다.'], '');
  G.busy = false; save();
  await checkLegendAwakenings();
}

// ---------------------------------------------------------------- starter selection
function starterSelect() {
  return new Promise((resolve) => {
    G.busy = true;
    const el = $('#select'); el.hidden = false; showHud(false);
    let i = 1;
    const peds = World.pedestals;
    const render = () => {
      const sp = STARTERS[i], s = SPECIES[sp], names = ['체력', '공격', '방어', '속도'];
      el.innerHTML = `<div class="sel-card">
        <div class="sel-head"><h3>${s.n}</h3><div class="types">${s.t.map(typeChip).join('')}</div></div>
        <p class="sel-desc">${s.d}</p>
        <div class="sel-stats">${s.b.map((v, k) => `<span>${names[k]}</span><div class="bar"><i style="width:${v / 80 * 100}%;background:${TYPES[s.t[0]].c}"></i></div><span>${v}</span>`).join('')}</div>
        <div class="sel-match"><span class="lbl">강한 상대</span>${Object.keys(TYPES).filter((t) => typeEff(s.t[0], [t]) > 1).map(typeChip).join('') || '<em>없음</em>'}
          <span class="lbl">조심할 상대</span>${Object.keys(TYPES).filter((t) => typeEff(t, s.t) > 1).map(typeChip).join('') || '<em>없음</em>'}</div>
        <div class="sel-moves"><span class="lbl">처음 기술</span>${s.learn.filter(([lv]) => lv <= 5).map(([, mv]) => `<b style="--tc:${TYPES[MOVES[mv].t].c}">${MOVES[mv].n}</b>`).join('')}</div>
        <div class="sel-row"><button class="sel-nav" id="sPrev" aria-label="이전">◀</button><button class="btn primary" id="sOk">${josa(s.n, '과와')} 함께하기</button><button class="sel-nav" id="sNext" aria-label="다음">▶</button></div>
      </div>`;
      const pd = peds[i], y = pd.y;
      World.cine = { pos: new THREE.Vector3(pd.x * 0.55, y + 2.3, pd.z + 5.4), look: new THREE.Vector3(pd.x, y + 0.9, pd.z), k: 3 };
      peds.forEach((p, k) => { if (p.rig) p.rig.moving = k === i ? 1 : 0; });
      $('#sPrev').onclick = () => { Snd.fx('select'); i = (i + 2) % 3; render(); };
      $('#sNext').onclick = () => { Snd.fx('select'); i = (i + 1) % 3; render(); };
      $('#sOk').onclick = async () => {
        Snd.fx('confirm');
        el.hidden = true; hotkeyHandler = null;
        const c = await ask(`정말 ${josa(s.n, '으로')} 할까?`, ['응, 이 아이로 할래', '다시 고를래']);
        if (c === 0) { peds.forEach((p) => { if (p.rig) p.rig.moving = 0; }); resolve(sp); }
        else { el.hidden = false; render(); bindKeys(); }
      };
    };
    const bindKeys = () => {
      hotkeyHandler = (code) => {
        if (code === 'ArrowLeft' || code === 'KeyA') $('#sPrev').click();
        if (code === 'ArrowRight' || code === 'KeyD') $('#sNext').click();
        if (code === 'Enter' || code === 'KeyE' || code === 'Space') $('#sOk').click();
      };
    };
    render(); bindKeys();
  });
}
async function starterJoin(pd) {
  const r = pd.rig; pd.chosen = true;
  const pp = World.player.root.position;
  const from = r.root.position.clone(), to = new THREE.Vector3(pp.x + 1.3, groundY(pp.x + 1.3, pp.z), pp.z);
  Snd.fx('confirm');
  World.fx.burst(new THREE.Vector3(from.x, from.y + 0.6, from.z), 50, { color: [0xffd98a, 0xffffff], speed: 4, size: 0.35, life: 0.9 });
  await Tw.add(0.8, (k) => { r.root.position.lerpVectors(from, to, k); r.root.position.y += Math.sin(k * Math.PI) * 1.6; r.root.rotation.y += 0.25; }, ease.inOut);
  disposeRig(r); pd.rig = null;
  setFollower(pd.sp);
  World.follower.root.position.copy(to);
  World.cine = null; G.busy = false; showHud(true);
}
function setupPedestals() {
  for (const pd of World.pedestals) {
    if (pd.rig) { disposeRig(pd.rig); pd.rig = null; }
    if (S.flags.starter === pd.sp) continue;
    const r = makeSpiritModel(pd.sp); r.root.scale.setScalar(0.85);
    r.root.position.set(pd.x, pd.y, pd.z); r.root.rotation.y = Math.PI;
    World.scene.add(r.root); pd.rig = r; pd.chosen = false;
  }
}

// ---------------------------------------------------------------- encounters & battles
function onPlayerMoved(d) {
  if (!S.party.length || G.busy) return;
  const p = World.player.root.position, z = zoneAt(p.x, p.z);
  if (!z) return;
  if (Math.random() < 0.25) World.fx.emit({ x: p.x + rand(-0.5, 0.5), y: p.y + 0.4, z: p.z + rand(-0.5, 0.5), vx: rand(-1, 1), vy: rand(1, 2), vz: rand(-1, 1), grav: 4, color: 0x9ad86a, size: 0.18, life: 0.6, intensity: 0.8 });
  G.encDist += d;
  if (G.encDist >= G.encNext) { G.encDist = 0; G.encNext = rand(7, 15); startWild(z); }
}
function startWild(zone) {
  const e = rollPool(POOLS[zone.pool]);
  const foe = makeMon(e.sp, randi(e.lv[0], e.lv[1]));
  return battleFlow({ kind: 'wild', foes: [foe], theme: zone.pool === 'altar' ? 'rift' : 'field', music: 'battle' });
}
async function transitionIn(kind) {
  const wipe = $('#wipe');
  if (kind === 'legend') { await fadeTo(1, 1.2); return; }
  for (let i = 0; i < 2; i++) { await flashScreen('#ffffff', 0.85, 0.16); }
  wipe.style.opacity = '1';
  await Tw.add(0.55, (k) => { wipe.style.clipPath = `circle(${k * 150}% at 50% 50%)`; wipe.style.transform = `rotate(${k * 120}deg) scale(1.6)`; }, ease.in);
  $('#fade').style.transitionDuration = '0s'; $('#fade').style.opacity = '1';
  await sleep(30);
  wipe.style.opacity = '0'; wipe.style.clipPath = 'circle(0% at 50% 50%)';
}
async function battleFlow(cfg) {
  G.busy = true; Input.keys = {}; Input.joy.active = false;
  Snd.fx('encounter');
  showHud(false);
  await transitionIn(cfg.kind);
  G.mode = 'battle';
  Snd.play(cfg.music || 'battle');
  let res;
  try { res = await runBattle(cfg); }
  catch (err) { console.error(err); res = 'run'; }
  await fadeTo(1, 0.5);
  $('#battleUI').hidden = true; $('#pops').innerHTML = '';
  disposeRig(Battle.allyRig); disposeRig(Battle.foeRig); Battle.allyRig = Battle.foeRig = null;
  G.mode = 'world';
  if (res === 'lose') {
    await healAll(false);
    const hx = -6, hz = 47.5;
    World.player.root.position.set(hx, groundY(hx, hz), hz); World.player.root.rotation.y = Math.PI / 2; World.camYaw = Math.PI / 2; snapCamera();
    if (World.follower) World.follower.root.position.set(hx + 1, groundY(hx + 1, hz), hz + 1);
  }
  setFollower(S.party[0] && S.party[0].sp);
  setLook(0xbcd4ff, 0.45); Post.U.uSun.value.z = 0;
  Snd.play('world');
  await fadeTo(0, 0.6);
  if (res === 'lose') await say(['정신이 드니? 쓰러져 있는 걸 데려왔어.', '정령들은 샘물로 다 치료해 뒀으니 걱정 마.'], '샘지기 하나');
  showHud(true);
  G.busy = false; G.encDist = 0; G.encNext = rand(8, 15);
  save();
  return res;
}

// ---------------------------------------------------------------- the altar & the legends
function refreshLegendRig() {
  if (World.legendRig) { disposeRig(World.legendRig); World.legendRig = null; }
  let sp = null;
  if (S.flags.awakened && !S.flags.nihilosDone) sp = 'nihilos';
  else if (S.flags.nihilosDone && !S.flags.ensiaDone) sp = 'ensia';
  if (!sp) { World.extraRigs = []; return; }
  const r = makeSpiritModel(sp); r.root.scale.setScalar(1.25);
  r.root.position.set(SITES.altar.x, World.altarY + 4, SITES.altar.z - 1.5);
  r.root.rotation.y = 0;
  World.scene.add(r.root); World.legendRig = r; World.extraRigs = [r];
}
async function altarInteract() {
  if (!S.party.length) return say(['오래된 제단이다. 가운데에 세 개의 홈이 파여 있다.'], '');
  if (fragCount() < 3) return say([`제단 가운데 세 개의 홈이 있다. 그중 ${fragCount()}개가 금빛으로 빛나고 있다.`, '존재의 파편이 더 필요하다.'], '');
  if (!S.flags.awakened) return altarAwaken();
  if (!S.flags.nihilosDone) {
    const c = await ask('니힐로스가 제단 위에서 너를 내려다보고 있다. 맞설까?', ['맞선다', '아직은…']);
    if (c === 0) return legendBattle('nihilos');
    return;
  }
  if (!S.flags.ensiaDone) {
    const c = await ask('엔시아가 빛 속에서 기다리고 있다. 맞설까?', ['맞선다', '아직은…']);
    if (c === 0) return legendBattle('ensia');
    return;
  }
  const missing = ['nihilos', 'ensia'].filter((s) => !S.dex.caught[s]);
  if (missing.length) {
    const c = await ask('제단에 아직 전설의 기척이 남아 있다. 다시 불러낼까?', [...missing.map((s) => SPECIES[s].n + '에게 도전'), '그만둔다']);
    if (c < missing.length) { if (S.items.origin < 2) { S.items.origin = 3; toast('제단이 근원결정 ×3을 빚어 주었다'); } return legendBattle(missing[c], true); }
    return;
  }
  return say(['제단은 고요하다. 존재와 공허가 이곳에서 함께 잠들어 있다.'], '');
}
async function altarAwaken() {
  G.busy = true; showHud(false);
  const A = SITES.altar, ay = World.altarY;
  World.cine = { pos: new THREE.Vector3(A.x + 10, ay + 6, A.z + 14), look: new THREE.Vector3(A.x, ay + 3, A.z), k: 1.6 };
  await say(['세 개의 파편이 제단의 홈으로 빨려 들어간다…'], '');
  for (let i = 0; i < 3; i++) { World.sockets[i].material = E(0xffd98a, 3.4); Snd.fx('fragment'); World.fx.burst(World.sockets[i].getWorldPosition(new THREE.Vector3()), 40, { color: [0xffd98a, 0xffffff], speed: 4, size: 0.35, life: 0.9 }); await wait(0.6); }
  Snd.stop();
  Snd.fx('rumble'); World.shake = 2.5;
  World.crackOverride = true;
  const c0 = World.skyU.uCrack.value;
  World.cine = { pos: new THREE.Vector3(A.x + 6, ay + 3, A.z + 18), look: new THREE.Vector3(A.x, ay + 22, A.z - 40), k: 1.2 };
  await Tw.add(3, (k) => { World.skyU.uCrack.value = lerp(c0, 2.4, k); World.healTarget = World.heal = lerp(1, 0.35, k); }, ease.inOut);
  await say([{ who: '???', cls: 'void', t: '…존재하는 것들아.' }]);
  // Nihilos descends from the crack
  const r = makeSpiritModel('nihilos'); r.root.scale.setScalar(1.25);
  const dir = World.skyU.uCrackDir.value.clone();
  const start = new THREE.Vector3(A.x, ay, A.z).addScaledVector(dir, 90), end = new THREE.Vector3(A.x, ay + 4, A.z - 1.5);
  r.root.position.copy(start); World.scene.add(r.root); World.extraRigs = [r]; World.legendRig = r;
  Snd.play('void');
  World.cine = { pos: new THREE.Vector3(A.x + 4, ay + 2.5, A.z + 13), look: start.clone(), k: 2 };
  await Tw.add(3.6, (k) => {
    r.root.position.lerpVectors(start, end, k);
    World.cine.look.copy(r.root.position).add(new THREE.Vector3(0, 3, 0));
    if (Math.random() < 0.8) World.fx.emit({ x: r.root.position.x + rand(-2, 2), y: r.root.position.y + rand(0, 5), z: r.root.position.z + rand(-2, 2), color: 0xb04bff, size: 0.6, life: 1.4, vx: rand(-1, 1), vy: rand(-1, 1), vz: rand(-1, 1) });
  }, ease.out);
  World.shake = 1;
  flashScreen('#c77dff', 0.6, 0.6);
  await say([
    { who: '니힐로스', cls: 'void', t: '너희는 너무 많이 빚었다. 너무 많이 남겼다. 이름, 기억, 약속… 그 무게로 세계가 숨을 쉬지 못한다.' },
    { who: '니힐로스', cls: 'void', t: '나는 지우러 왔다. 모든 것이 처음의 고요로 돌아가도록.' },
    { who: '니힐로스', cls: 'void', t: '작은 존재여. 네 곁의 정령들도 결국 나에게 돌아온다. 그래도 맞서겠느냐?' },
  ]);
  S.flags.awakened = true; World.crackOverride = false;
  if (S.items.origin < 3) { S.items.origin = 3; }
  toast('제단이 근원결정 ×3을 빚어 주었다');
  await say(['제단에서 금빛 결정 세 개가 떠올랐다. 근원결정… 전설의 정령도 봉인할 수 있다.'], '');
  World.cine = null;
  refreshMarkers(); updateHud(); save();
  await legendBattle('nihilos');
}
const LEGENDS = {
  nihilos:  { theme: 'void', music: 'void', title: '공허, 니힐로스', sub: 'THE VOID', cls: 'void', line: '니힐로스의 얼굴에 뚫린 구멍이 너를 바라본다…', sfx: 'void', flash: '#000000', lv: [0, 18] },
  ensia:    { theme: 'being', music: 'being', title: '존재, 엔시아', sub: 'THE BEING', cls: 'being', line: '엔시아의 빛이 모든 그림자를 지운다…', sfx: 'genesis', flash: '#fff6dc', lv: [0, 18] },
  asterion: { theme: 'star', music: 'star', title: '별, 아스테리온', sub: 'THE STARS', cls: 'star', line: '아스테리온의 몸속에서 이름 없는 별들이 흐른다…', sfx: 'chime', flash: '#cfefff', lv: [2, 14] },
  abyssea:  { theme: 'abyss', music: 'abyss', title: '심해, 아비세아', sub: 'THE ABYSS', cls: 'abyss', line: '바다가 숨을 멈췄다…', sfx: 'whale', flash: '#06263a', lv: [2, 16] },
  danha:    { theme: 'dawn', music: 'dawn', title: '여명, 단하', sub: 'THE DAWN', cls: 'dawn', line: '단하의 포효에 하늘이 붉게 물든다!', sfx: 'roar', flash: '#ffb070', lv: [3, 22] },
  limina:   { theme: 'boundary', music: 'limina', title: '경계, 리미나', sub: 'THE BOUNDARY', cls: 'limina', line: '존재와 공허가 한 몸 안에서 함께 숨 쉬고 있다…', sfx: 'void', flash: '#ffffff', lv: [4, 26] },
};
async function legendBattle(sp, rematch = false) {
  const L = LEGENDS[sp];
  const top = Math.max(...S.party.map((m) => m.lv));
  const lv = clamp(top + L.lv[0], L.lv[1], 60);
  const foe = makeMon(sp, lv);
  const res = await battleFlow({
    kind: 'legend', foes: [foe], theme: L.theme, music: L.music,
    intro: async () => {
      cinema(true);
      Battle.shake = 1.2; Snd.fx(L.sfx); if (sp === 'danha') Snd.fx('fire');
      flashScreen(L.flash, 1, 1.2);
      Post.shock(rigCenter(Battle.foeRig), Battle.camera, 1.6); Post.kick(0.03);
      await banner(L.title, L.sub, L.cls, 1.9);
      await bmsg(L.line, 1.6);
      cinema(false);
    },
  });
  if (sp !== 'nihilos' && sp !== 'ensia') {
    if (res === 'caught') { toast(`전설의 정령 ${josa(SPECIES[sp].n, '을를')} 봉인했다!`); Snd.fx('fragment'); }
    refreshWorldLegends(); refreshMarkers(); updateHud(); save();
    if (res === 'caught') await checkLegendAwakenings();
    return res;
  }
  if (res === 'caught' || res === 'win') {
    S.flags[sp + 'Done'] = true;
    refreshLegendRig(); refreshMarkers(); updateHud();
    if (rematch) { save(); await checkLegendAwakenings(); return res; }
    if (sp === 'nihilos') {
      await say([res === 'caught' ? '니힐로스가 결정 속에서 고요해졌다… 공허가 너를 받아들였다.' : '니힐로스가 균열 속으로 물러났다. 공허는 사라지지 않는다. 다만… 조용해졌을 뿐.'], '');
      await ensiaDescends();
    } else await ending(res);
  } else { refreshLegendRig(); updateHud(); }
  return res;
}

// ---- the four wandering legends: announcements and encounters
const AWAKEN = {
  asterion: ['어딘가에서 별이 떨어지는 소리가 들렸다…', '북동쪽 별빛 봉우리에 푸른 빛기둥이 내려앉았다.'],
  abyssea: ['서쪽 바다 깊은 곳에서 길고 낮은 울음소리가 들려온다…', '고래울음 바위로 가 보자. 무언가가 수면 아래를 맴돌고 있다.'],
  danha: ['새벽 하늘을 붉은 용이 가로지른다!', '동쪽 해돋이 언덕의 제단석이 붉게 빛나고 있다.'],
  limina: ['존재와 공허가 동시에 너를 부른다…', '남쪽, 경계의 모래톱 앞바다에서 반은 빛이고 반은 어둠인 무언가가 헤엄치고 있다.'],
};
async function checkLegendAwakenings(silent = false) {
  for (const sp of ['asterion', 'abyssea', 'danha', 'limina']) {
    if (!legendPresent(sp) || S.flags['seen_' + sp]) continue;
    S.flags['seen_' + sp] = true;
    refreshWorldLegends(); refreshMarkers();
    if (!silent) { Snd.fx('chime'); await say(AWAKEN[sp], ''); toast(`전설의 기척: ${World.legendSites[sp].name}`); }
  }
  refreshWorldLegends(); refreshMarkers(); updateHud();
}
async function legendEncounter(sp) {
  const L = World.legends[sp]; if (!L) return;
  G.busy = true; showHud(false);
  const r = L.rig, site = L.site, P = World.player.root.position;
  const toP = new THREE.Vector3(P.x - site.x, 0, P.z - site.z).normalize();
  L.mode = 'scene';
  if (sp === 'asterion') {
    World.cine = { pos: new THREE.Vector3(site.x + toP.x * 9 + 3, site.y + 3.5, site.z + toP.z * 9), look: new THREE.Vector3(site.x, site.y + 2.2, site.z), k: 1.8 };
    r.root.rotation.y = Math.atan2(P.x - site.x, P.z - site.z);
    await wait(1.0); Snd.fx('chime');
    await Tw.add(0.6, (k) => { r.root.rotation.x = -Math.sin(k * Math.PI) * 0.45; }, ease.inOut);
    World.fx.burst(new THREE.Vector3(site.x, site.y + 2, site.z), 120, { color: [0x8fe0ff, 0xffffff, 0xb48cff], speed: 7, size: 0.5, life: 1.4 });
    await say(['별빛 봉우리 위, 별자리로 이루어진 사슴이 너를 내려다본다.', '그 몸속에서 아직 이름 없는 별들이 반짝이고 있다…'], '');
  } else if (sp === 'abyssea') {
    const c = site.close; r.root.visible = true; r.root.scale.setScalar(1.35);
    World.cine = { pos: new THREE.Vector3(site.x + 6, site.y + 3.5, site.z + 7), look: new THREE.Vector3(c.x, 3, c.z), k: 1.6 };
    r.root.position.set(c.x, -9, c.z); r.root.rotation.set(-0.6, Math.atan2(P.x - c.x, P.z - c.z), 0);
    await wait(0.8); Snd.fx('whale');
    await Tw.add(2.4, (k) => { r.root.position.y = lerp(-9, 2.2, ease.out(k)); r.root.rotation.x = lerp(-0.6, -0.1, k); if (Math.random() < 0.6) World.fx.burst(new THREE.Vector3(c.x + rand(-3, 3), 0.3, c.z + rand(-3, 3)), 4, { color: [0xdff8ff, 0x7fdcff], speed: 6, up: 5, grav: 9, size: 0.8, life: 1.2, drag: 0.5 }); }, ease.lin);
    World.shake = 0.8;
    await say(['바다가 갈라지고, 빛나는 무늬를 두른 거대한 고래가 떠올랐다.', '그 울음에 바닷물이 숨을 멈춘다…'], '');
  } else if (sp === 'danha') {
    const hover = new THREE.Vector3(site.x + toP.x * -1 + 0, site.y + 6.5, site.z - toP.z);
    World.cine = { pos: new THREE.Vector3(site.x + toP.x * 12, site.y + 4, site.z + toP.z * 12), look: r.root.position.clone(), k: 2.2 };
    const from = r.root.position.clone();
    Snd.fx('roar');
    await Tw.add(3.2, (k) => {
      r.root.position.lerpVectors(from, hover, ease.inOut(k)); r.root.scale.setScalar(lerp(2.2, 1.35, k));
      r.root.rotation.set(0, Math.atan2(P.x - r.root.position.x, P.z - r.root.position.z), -0.35 * (1 - k));
      World.cine.look.copy(r.root.position).add(new THREE.Vector3(0, 2, 0));
      if (Math.random() < 0.7) World.fx.emit({ x: r.root.position.x + rand(-1.5, 1.5), y: r.root.position.y + rand(0, 3), z: r.root.position.z + rand(-1.5, 1.5), vy: -rand(0.5, 2), color: [0xff8a3d, 0xffd25a][Math.random() < 0.5 ? 0 : 1], size: 0.9, life: 1.6, intensity: 1.6 });
    }, ease.lin);
    World.shake = 1.0; flashScreen('#ffb070', 0.4, 0.6);
    await say(['붉은 노을을 두른 용이 해돋이 언덕에 내려앉았다!', '앞발에 쥔 여의주에서 아침 햇살이 흘러넘친다.'], '');
  } else if (sp === 'limina') {
    const hover = new THREE.Vector3(site.x, 4.5, site.z + 9);
    const from = r.root.position.clone();
    World.cine = { pos: new THREE.Vector3(site.x - 7, site.y + 3, site.z - 7), look: hover.clone(), k: 1.6 };
    Snd.fx('void');
    await Tw.add(3, (k) => { r.root.position.lerpVectors(from, hover, ease.inOut(k)); r.root.rotation.set(0.25 * k, Math.atan2(P.x - r.root.position.x, P.z - r.root.position.z), 0); }, ease.lin);
    Snd.fx('genesis'); flashScreen('#ffffff', 0.5, 0.6);
    await say(['반은 금빛, 반은 공허로 된 거대한 가오리가 수면 위로 미끄러져 왔다.', '존재와 공허, 둘을 모두 품은 너를 알아보는 듯하다.'], '');
  }
  const c = await ask(`${SPECIES[sp].n}에게 맞설까?`, ['맞선다', '아직은…']);
  World.cine = null; G.busy = false;
  if (c === 0) await legendBattle(sp);
  const still = World.legends[sp];
  if (still) {
    still.mode = 'idle'; still.rig.root.rotation.x = 0;
    if (sp === 'asterion') { still.rig.root.position.set(site.x, site.y, site.z); still.rig.root.rotation.y = Math.atan2(-site.x, -site.z); }
    if (sp === 'danha') still.rig.root.scale.setScalar(2.2);
  }
  showHud(true);
}

async function ensiaDescends() {
  G.busy = true; showHud(false);
  const A = SITES.altar, ay = World.altarY;
  if (World.legendRig) { disposeRig(World.legendRig); World.legendRig = null; }
  World.cine = { pos: new THREE.Vector3(A.x - 6, ay + 3, A.z + 16), look: new THREE.Vector3(A.x, ay + 30, A.z), k: 1.4 };
  Snd.play('being');
  await Tw.add(1.6, (k) => { World.altarBeam.material.opacity = k * 0.55; }, ease.inOut);
  const r = makeSpiritModel('ensia'); r.root.scale.setScalar(1.25);
  const start = new THREE.Vector3(A.x, ay + 70, A.z - 1.5), end = new THREE.Vector3(A.x, ay + 3.4, A.z - 1.5);
  r.root.position.copy(start); World.scene.add(r.root); World.legendRig = r; World.extraRigs = [r];
  await Tw.add(4, (k) => {
    r.root.position.lerpVectors(start, end, k);
    World.cine.look.copy(r.root.position).add(new THREE.Vector3(0, 3, 0));
    if (Math.random() < 0.8) World.fx.emit({ x: r.root.position.x + rand(-2.5, 2.5), y: r.root.position.y + rand(0, 6), z: r.root.position.z + rand(-2.5, 2.5), color: 0xffd98a, size: 0.6, life: 1.5, vy: rand(-1, 1) });
  }, ease.out);
  flashScreen('#fff6dc', 0.9, 0.9);
  await Tw.add(1.2, (k) => { World.altarBeam.material.opacity = 0.55 * (1 - k); }, ease.inOut);
  await say([
    { who: '엔시아', cls: '', t: '두려워하지 마라. 나는 너를 벌하러 온 것이 아니다.' },
    { who: '엔시아', cls: '', t: '공허가 없다면 나도 없다. 비어 있는 곳이 있어야 무언가가 존재할 수 있으니.' },
    { who: '엔시아', cls: '', t: '그러나 균형은 증명되어야 한다. 네가 정말 그 경계에 설 수 있는 자인지, 내 빛으로 확인하겠다.' },
  ]);
  World.cine = null;
  G.busy = false;
  await legendBattle('ensia');
}
async function ending(res) {
  G.busy = true; showHud(false);
  const A = SITES.altar, ay = World.altarY;
  await say([{ who: '엔시아', t: res === 'caught' ? '…그래. 네 곁이라면, 빛도 쉬어 갈 수 있겠구나.' : '충분하다. 너는 증명했다.' }, { who: '엔시아', t: '보아라. 하늘이 닫힌다.' }]);
  World.cine = { pos: new THREE.Vector3(A.x + 4, ay + 3, A.z + 20), look: new THREE.Vector3(A.x, ay + 26, A.z - 50), k: 1 };
  Snd.fx('genesis');
  const c0 = World.skyU.uCrack.value;
  World.crackOverride = true;
  await Tw.add(4, (k) => { World.skyU.uCrack.value = lerp(c0, 0, k); }, ease.inOut);
  World.crackOverride = false;
  S.flags.ending = true; World.dawnTarget = 1; World.healTarget = 1;
  setTimeout(() => refreshWorldEnv(), 4000);
  Snd.play('title');
  await wait(2.5);
  const caught = Object.keys(S.dex.caught).length;
  const el = $('#ending'); el.hidden = false;
  el.innerHTML = `<p class="eyebrow">정령의 섬</p><h2>경계 위의 아이</h2>
    <p>존재는 빚고, 공허는 비운다. 그 사이에서 숨 쉬는 모든 것이 바로 세계다.<br>하늘의 균열은 닫혔고, 섬에는 처음으로 새벽이 왔다.</p>
    <p style="font-size:14px;color:var(--muted);font-family:var(--f-ui)">도감 ${caught} / ${DEX_ORDER.length} · 함께한 정령 ${S.party.length + S.box.length}</p>
    <button class="btn primary" id="endOk">계속 탐험하기</button>`;
  el.style.opacity = '0'; el.style.transition = 'opacity 1.4s'; requestAnimationFrame(() => { el.style.opacity = '1'; });
  await new Promise((r) => { $('#endOk').onclick = r; });
  el.hidden = true; World.cine = null; refreshLegendRig(); refreshMarkers(); placeRiftState();
  showHud(true); G.busy = false; save();
  await checkLegendAwakenings();
}

// ---------------------------------------------------------------- menus (overworld modal)
function openModal(title, tabs, renderTab, start = 0) {
  const md = $('#modal'); md.hidden = false; $('#mTitle').textContent = title;
  const nav = $('#mTabs'); nav.innerHTML = '';
  let cur = start;
  const draw = () => { [...nav.children].forEach((b, i) => b.classList.toggle('on', i === cur)); renderTab(cur, $('#mBody'), draw); };
  tabs.forEach((t, i) => { const b = document.createElement('button'); b.textContent = t; b.onclick = () => { cur = i; Snd.fx('select'); draw(); }; nav.appendChild(b); });
  draw();
}
function closeModal() { $('#modal').hidden = true; G.lock = 0.2; Input.actionQueued = false; updateHud(); }
$('#mClose').onclick = () => { Snd.fx('back'); closeModal(); };
$('#modal').addEventListener('click', (e) => { if (e.target.id === 'modal') closeModal(); });

function monDetail(m, actions) {
  const s = SPECIES[m.sp], names = ['체력', '공격', '방어', '속도'];
  const vals = [maxHp(m), stat(m, 1), stat(m, 2), stat(m, 3)];
  return `<div class="detail">
    <div style="display:flex;gap:14px;align-items:center"><img src="${Icons.get(m.sp)}" alt="" style="width:96px;height:96px;border-radius:14px;background:rgba(255,255,255,.04)">
      <div style="display:flex;flex-direction:column;gap:6px;min-width:0"><b style="font-family:var(--f-display);font-size:22px">${s.n} <span style="font-size:13px;color:var(--muted);font-family:var(--f-ui)">Lv.${m.lv}</span></b><div class="types" style="display:flex;gap:5px">${s.t.map(typeChip).join('')}</div>
      <span style="font-size:12px;color:var(--muted)">다음 레벨까지 ${expNeed(m.lv) - m.exp} EXP${s.evo ? ` · Lv.${s.evo.lv}에 진화` : ''}</span></div></div>
    <p>${s.d}</p>
    <div class="sel-stats">${vals.map((v, k) => `<span>${names[k]}</span><div class="bar"><i style="width:${clamp(v / (k ? 90 : 150), 0, 1) * 100}%;background:${TYPES[s.t[0]].c}"></i></div><span>${k === 0 ? m.hp + '/' : ''}${v}</span>`).join('')}</div>
    <div class="section-h">기술</div>
    <div class="moves">${m.moves.map((id) => `<div><span>${MOVES[id].n}</span>${typeChip(MOVES[id].t)}</div>`).join('')}</div>
    ${actions ? `<div class="acts">${actions}</div>` : ''}
  </div>`;
}
function openParty(start = 0) {
  let sel = 0;
  openModal('정령', ['동료', '보관함', '도감'], (tab, body, redraw) => {
    if (tab === 0) {
      body.innerHTML = S.party.map((m, i) => {
        const f = m.hp / maxHp(m);
        return `<button class="mon-row ${i === sel ? 'sel' : ''}" data-i="${i}"><img src="${Icons.get(m.sp)}" alt=""><div class="grow"><div class="top"><b>${monName(m)}${i === 0 ? '<span class="badge">선두</span>' : ''}</b><span>Lv.${m.lv} · ${m.hp}/${maxHp(m)}</span></div><div class="bar"><i style="width:${f * 100}%;background:${hpColor(f)}"></i></div></div></button>`;
      }).join('') || '<p style="color:var(--muted)">아직 함께하는 정령이 없어요. 마을의 장로와 이야기해 보세요.</p>';
      const m = S.party[sel];
      if (m) body.insertAdjacentHTML('beforeend', monDetail(m, `${sel > 0 ? '<button class="chip" id="aLead">선두로 세우기</button>' : ''}${S.party.length > 1 ? '<button class="chip" id="aBox">보관함으로 보내기</button>' : ''}`));
      body.querySelectorAll('.mon-row').forEach((b) => (b.onclick = () => { sel = +b.dataset.i; Snd.fx('select'); redraw(); }));
      const al = $('#aLead'); if (al) al.onclick = () => { const [x] = S.party.splice(sel, 1); S.party.unshift(x); sel = 0; setFollower(x.sp); Snd.fx('confirm'); save(); redraw(); };
      const ab = $('#aBox'); if (ab) ab.onclick = () => { const [x] = S.party.splice(sel, 1); S.box.push(x); sel = 0; setFollower(S.party[0].sp); Snd.fx('confirm'); save(); redraw(); };
    } else if (tab === 1) {
      body.innerHTML = S.box.length ? S.box.map((m, i) => `<div class="mon-row"><img src="${Icons.get(m.sp)}" alt=""><div class="grow"><div class="top"><b>${monName(m)}</b><span>Lv.${m.lv}</span></div><div class="types" style="display:flex;gap:5px">${monTypes(m).map(typeChip).join('')}</div></div><button class="chip" data-i="${i}" ${S.party.length >= 6 ? 'disabled' : ''}>${S.party.length >= 6 ? '동료 가득' : '데려오기'}</button></div>`).join('')
        : '<p style="color:var(--muted)">보관함이 비어 있어요. 동료가 6마리를 넘으면 새로 봉인한 정령이 이곳으로 와요.</p>';
      body.querySelectorAll('button[data-i]').forEach((b) => (b.onclick = () => { const [x] = S.box.splice(+b.dataset.i, 1); x.hp = maxHp(x); S.party.push(x); Snd.fx('confirm'); save(); redraw(); }));
    } else {
      const seen = Object.keys(S.dex.seen).length, caught = Object.keys(S.dex.caught).length;
      body.innerHTML = `<p style="margin:0;color:var(--muted);font-size:13px">본 정령 ${seen} · 봉인한 정령 ${caught} / ${DEX_ORDER.length}</p><div class="dex">${DEX_ORDER.map((sp) => {
        const s = SPECIES[sp], no = String(s.no).padStart(3, '0');
        const lc = s.legend ? ` class="leg${s.mythic ? ' myth' : ''}"` : '';
        const tag = s.legend ? `<span class="tag">${s.mythic ? '환상' : '전설'}</span>` : '';
        if (S.dex.caught[sp]) return `<div${lc}><img src="${Icons.get(sp)}" alt="">${tag}<b>${s.n}</b><span class="no">No.${no}</span></div>`;
        if (S.dex.seen[sp]) return `<div class="sil${s.legend ? ' leg' + (s.mythic ? ' myth' : '') : ''}"><img src="${Icons.get(sp)}" alt="">${tag}<b>${s.n}</b><span class="no">No.${no} · 봄${s.home ? ' · ' + s.home : ''}</span></div>`;
        if (s.legend && legendPresent(sp)) return `<div class="leg${s.mythic ? ' myth' : ''}"><span class="unk">✦</span>${tag}<b style="color:var(--muted)">???</b><span class="no">${s.home}</span></div>`;
        return `<div><span class="unk">?</span><b style="color:var(--muted)">???</b><span class="no">No.${no}</span></div>`;
      }).join('')}</div>`;
    }
  }, start);
}
function openBag() {
  openModal('가방', [], (tab, body, redraw) => {
    const ids = ['crystal', 'origin', 'potion', 'elixir'];
    body.innerHTML = ids.map((id) => `<div class="item-row"><div><div class="nm">${ITEMS[id].n}</div><div class="ds">${ITEMS[id].d}</div></div><div style="display:flex;gap:10px;align-items:center"><span class="ct">×${S.items[id] || 0}</span>${ITEMS[id].field ? `<button class="chip" data-id="${id}" ${(S.items[id] || 0) > 0 ? '' : 'disabled'}>사용</button>` : ''}</div></div>`).join('');
    body.querySelectorAll('button[data-id]').forEach((b) => (b.onclick = () => {
      const id = b.dataset.id;
      body.innerHTML = `<p style="margin:0;color:var(--muted)">${ITEMS[id].n}을(를) 누구에게 쓸까요?</p>` + S.party.map((m, i) => { const f = m.hp / maxHp(m); return `<button class="mon-row" data-i="${i}" ${m.hp >= maxHp(m) && !m.status ? 'disabled style="opacity:.45"' : ''}><img src="${Icons.get(m.sp)}" alt=""><div class="grow"><div class="top"><b>${monName(m)}</b><span>${m.hp}/${maxHp(m)}</span></div><div class="bar"><i style="width:${f * 100}%;background:${hpColor(f)}"></i></div></div></button>`; }).join('') + '<button class="chip" id="bBack">뒤로</button>';
      body.querySelectorAll('.mon-row').forEach((r) => (r.onclick = () => { const m = S.party[+r.dataset.i]; S.items[id]--; m.hp = Math.min(maxHp(m), m.hp + ITEMS[id].heal); if (ITEMS[id].heal > 999) m.status = null; Snd.fx('heal'); toast(`${monName(m)}의 체력이 회복되었다`); save(); redraw(); }));
      $('#bBack').onclick = () => redraw();
    }));
  });
}
function openSettings() {
  let confirmReset = false;
  openModal('설정', [], (tab, body, redraw) => {
    body.innerHTML = `
      <div class="item-row"><div><div class="nm">그래픽</div><div class="ds">최고: 앰비언트 오클루전까지 / 높음: 블룸 조명·그림자·풍성한 풀숲 / 낮음: 휴대폰 배터리 절약</div></div><button class="chip" id="oGfx">${gfxLabel()}</button></div>
      <div class="item-row"><div><div class="nm">소리</div><div class="ds">배경 음악과 효과음</div></div><button class="chip" id="oSnd">${Settings.sound ? '켬' : '끔'}</button></div>
      <div class="item-row"><div><div class="nm">저장</div><div class="ds">전투가 끝날 때와 중요한 순간마다 자동으로 저장돼요.</div></div><button class="chip" id="oSave">지금 저장</button></div>
      <div class="item-row"><div><div class="nm">조작법</div><div class="ds">${isTouch ? '왼쪽 스틱 이동 · A 상호작용 · 빈 화면을 끌어 시점 회전 · 두 손가락으로 확대' : 'WASD·방향키 이동 · Shift 달리기 · E·Space 상호작용 · 드래그 또는 Q/R 시점 회전 · 휠 확대 · P 정령 · B 가방 · Esc 설정'}</div></div></div>
      <div class="item-row"><div><div class="nm">처음부터</div><div class="ds">${confirmReset ? '한 번 더 누르면 모든 기록이 지워져요.' : '저장된 모험을 지우고 새로 시작해요.'}</div></div><button class="chip" id="oReset">${confirmReset ? '정말 지우기' : '새로 시작'}</button></div>`;
    $('#oGfx').onclick = () => { cycleGfx(); redraw(); };
    $('#oSnd').onclick = () => { Snd.init(); Snd.setOn(!Settings.sound); redraw(); };
    $('#oSave').onclick = () => { save(); toast('저장했어요'); };
    $('#oReset').onclick = () => { if (!confirmReset) { confirmReset = true; redraw(); return; } try { localStorage.removeItem(SAVE_KEY); } catch (e) {} location.reload(); };
  });
}
$('#bParty').onclick = () => { if (canMove()) { Snd.fx('select'); openParty(); } };
$('#bBag').onclick = () => { if (canMove()) { Snd.fx('select'); openBag(); } };
$('#bMenu').onclick = () => { if (canMove() || G.mode === 'world') { Snd.fx('select'); openSettings(); } };
function worldHotkey(code) {
  if (G.mode !== 'world') return;
  if (!$('#modal').hidden) { if (code === 'Escape' || code === 'KeyP' || code === 'KeyB') closeModal(); return; }
  if (!canMove()) return;
  if (code === 'KeyP' || code === 'KeyI') openParty();
  if (code === 'KeyB') openBag();
  if (code === 'Escape' || code === 'KeyM') openSettings();
}

function gfxLabel() { return Settings.high ? (Settings.ultra ? '최고' : '높음') : '낮음'; }
function cycleGfx() {
  if (Settings.high && Settings.ultra) Settings.ultra = false;
  else if (Settings.high) Settings.high = false;
  else { Settings.high = true; Settings.ultra = true; }
  saveSettings(); applyQuality();
}
// ---------------------------------------------------------------- compass & area names
const Compass = { ticks: [], marks: [], key: '', range: Math.PI * 0.5 };
const wrapPi = (a) => ((((a + Math.PI) % (2 * Math.PI)) + 2 * Math.PI) % (2 * Math.PI)) - Math.PI;
function buildCompass() {
  const T = $('#cTicks'), names = { 0: '북', 90: '동', 180: '남', 270: '서' };
  T.innerHTML = ''; Compass.ticks = [];
  for (let a = 0; a < 360; a += 15) {
    const el = document.createElement(names[a] ? 'span' : 'i');
    if (names[a]) { el.textContent = names[a]; if (a === 0) el.className = 'N'; } else if (a % 45 === 0) el.className = 'mid';
    T.appendChild(el); Compass.ticks.push({ el, a: (a * Math.PI) / 180, vis: true, x: '' });
  }
}
function updateCompass() {
  if (!Compass.ticks.length) buildCompass();
  const H = -World.camYaw, R = Compass.range, p = World.player.root.position;
  const place = (o, rel, clampIt) => {
    const vis = clampIt || Math.abs(rel) < R;
    if (vis !== o.vis) { o.vis = vis; o.el.style.display = vis ? '' : 'none'; }
    if (!vis) return;
    const x = (50 + clamp(rel / R, -0.95, 0.95) * 50).toFixed(1) + '%';
    if (x !== o.x) { o.x = x; o.el.style.left = x; }
  };
  for (const t of Compass.ticks) place(t, wrapPi(t.a - H), false);
  const M = World.markers, key = M.map((m) => m.label + m.color).join('|');
  if (key !== Compass.key) {
    Compass.key = key; const box = $('#cMarks'); box.innerHTML = '';
    Compass.marks = M.map((m) => {
      const el = document.createElement('b'); el.style.color = '#' + m.color.toString(16).padStart(6, '0'); el.title = m.label;
      el.innerHTML = '<em></em><small></small>'; box.appendChild(el);
      return { el, txt: el.lastChild, vis: true, x: '', d: -1, edge: false };
    });
  }
  M.forEach((m, i) => {
    const o = Compass.marks[i]; if (!o) return;
    const dx = m.x - p.x, dz = m.z - p.z, rel = wrapPi(Math.atan2(dx, -dz) - H);
    place(o, rel, true);
    const edge = Math.abs(rel) > R * 0.95; if (edge !== o.edge) { o.edge = edge; o.el.classList.toggle('edge', edge); }
    const d = Math.round(Math.hypot(dx, dz)); if (d !== o.d) { o.d = d; o.txt.textContent = d < 4 ? '' : d + 'm'; }
  });
}
const AREA_EN = {
  '윤슬마을': 'YUNSEUL VILLAGE', '근원의 제단': 'ALTAR OF ORIGIN', '남쪽 들판': 'SOUTHERN MEADOW', '불씨 언덕': 'EMBER HILLS', '번개 습지': 'THUNDER MARSH',
  '그림자 숲길': 'SHADOW WOODS', '제단 비탈': 'ALTAR SLOPES', '동쪽 균열': 'EASTERN RIFT', '서쪽 균열': 'WESTERN RIFT', '북쪽 균열': 'NORTHERN RIFT',
  '별빛 봉우리': 'STARLIGHT PEAK', '고래울음 바위': 'WHALESONG ROCK', '해돋이 언덕': 'SUNRISE HILL', '경계의 모래톱': 'BOUNDARY SHOAL',
};
function areaAt(x, z) {
  const d = (o) => Math.hypot(x - o.x, z - o.z);
  if (d(SITES.town) < 24) return { n: '윤슬마을', sub: '치유의 샘이 있는 곳' };
  if (d(SITES.altar) < 15) return { n: '근원의 제단' };
  for (const r of SITES.rifts) if (d(r) < 15) return { n: r.name, sub: S.flags['closed_' + r.id] ? '닫힌 균열' : '공허가 새어 나오는 곳' };
  for (const sp in World.legendSites || {}) { const st = World.legendSites[sp]; if (d(st) < 14) return { n: st.name, sub: legendPresent(sp) ? '전설의 기척' : '' }; }
  for (const zn of ZONES) if (d(zn) < zn.r + 3) {
    const P = POOLS[zn.pool], lo = Math.min(...P.map((e) => e.lv[0])), hi = Math.max(...P.map((e) => e.lv[1]));
    return { n: zn.name, sub: `야생 정령 Lv.${lo}–${hi}` };
  }
  return null;
}
const Area = { cur: null, cand: null, t: 0, shown: {}, timer: 0 };
function showArea(a1, a2) {
  const el = $('#area'); el.querySelector('.a1').textContent = a1; el.querySelector('.a2').textContent = a2;
  el.classList.add('on'); clearTimeout(Area.timer); Area.timer = setTimeout(() => el.classList.remove('on'), 3400);
}
function updateArea(dt) {
  const p = World.player.root.position, a = areaAt(p.x, p.z), n = a ? a.n : null;
  if (n !== Area.cand) { Area.cand = n; Area.t = 0; return; }
  Area.t += dt;
  if (Area.t < 0.6 || n === Area.cur) return;
  Area.cur = n;
  if (!n) return;
  const now = performance.now() / 1000;
  if (now - (Area.shown[n] ?? -1e9) < 45) return;
  Area.shown[n] = now;
  showArea(n, [AREA_EN[n], a.sub].filter(Boolean).join('  ·  '));
}

// ---------------------------------------------------------------- interaction
function interactables() {
  const L = [];
  for (const n of World.npcs) L.push({ x: n.x, z: n.z, r: 3, label: `${n.name}`, verb: '대화', fn: () => n.talk(n) });
  L.push({ x: SITES.town.x, z: SITES.town.z, r: 4, label: '치유의 샘', verb: '마시기', fn: async () => { await healAll(true); await say(['샘물이 반짝인다… 정령들이 기운을 되찾았다.'], ''); save(); } });
  L.push({ x: SITES.altar.x, z: SITES.altar.z, r: 3.6, label: '근원의 제단', verb: '살펴보기', fn: altarInteract });
  for (const sp in World.legends || {}) { const st = World.legendSites[sp]; L.push({ x: st.x, z: st.z, r: sp === 'abyssea' || sp === 'limina' ? 7 : 6.5, label: S.dex.seen[sp] ? SPECIES[sp].n : `${st.name}의 기척`, verb: '다가가기', fn: () => legendEncounter(sp) }); }
  return L;
}
function worldTick(dt) {
  G.lock = Math.max(0, G.lock - dt);
  const pr = $('#prompt');
  if (G.mode === 'world' && !$('#hud').hidden) updateCompass();
  if (!canMove()) { pr.hidden = true; G.near = null; if (G.dialog || G.busy) Input.actionQueued = false; return; }
  updateArea(dt);
  const p = World.player.root.position;
  let best = null, bd = 1e9;
  for (const it of interactables()) { const d = Math.hypot(p.x - it.x, p.z - it.z); if (d < it.r && d < bd) { bd = d; best = it; } }
  G.near = best;
  if (best) { pr.hidden = false; pr.innerHTML = `<kbd>${isTouch ? 'A' : 'E'}</kbd>${best.label} · ${best.verb}`; } else pr.hidden = true;
  if (Input.actionQueued) {
    Input.actionQueued = false;
    if (best) { pr.hidden = true; Snd.fx('select'); Promise.resolve(best.fn()).catch((e) => console.error(e)).finally(() => updateHud()); }
  }
}

// ---------------------------------------------------------------- title & intro
const LORE = [
  '태초에 두 개의 이름이 있었다.',
  '모든 것을 빚는 <b class="g">존재</b>, 엔시아.',
  '모든 것을 되돌리는 <b class="v">공허</b>, 니힐로스.',
  '둘이 맞물린 자리에서 이 섬이 태어났고,<br>정령들은 그 경계에서 숨 쉬었다.',
  '그런데 어느 날 밤, 하늘에 금이 갔다.',
  '공허가 섬을 삼키기 전에,<br>누군가는 그 경계에 서야 한다.',
];
function titleCam(dt) {
  G.t += dt;
  const a = G.t * 0.035 + 0.6, R = G.mode === 'lore' ? 60 : 92;
  World.cine = { pos: new THREE.Vector3(Math.sin(a) * R, G.mode === 'lore' ? 22 : 34, Math.cos(a) * R), look: new THREE.Vector3(0, G.mode === 'lore' ? 16 : 10, -14), k: 1.2 };
}
async function playLore() {
  G.mode = 'lore';
  const el = $('#lore'), tx = $('#loreText'); el.hidden = false;
  let skip = false;
  $('#loreSkip').onclick = () => { skip = true; };
  for (const line of LORE) {
    if (skip) break;
    tx.style.opacity = '0'; await sleep(450); if (skip) break;
    tx.innerHTML = line; tx.style.opacity = '1';
    for (let i = 0; i < 32 && !skip; i++) await sleep(100);
  }
  tx.style.opacity = '0';
  await fadeTo(1, 0.8);
  el.hidden = true;
}
async function enterWorld(fresh) {
  World.cine = null;
  const p = S.pos || SITES.spawn;
  const x = walkable(p.x, p.z) ? p.x : SITES.spawn.x, z = walkable(p.x, p.z) ? p.z : SITES.spawn.z;
  World.player.root.position.set(x, groundY(x, z), z);
  World.player.root.rotation.y = Math.PI;
  World.camYaw = S.yaw || 0; World.camDist = 12;
  setFollower(S.party[0] && S.party[0].sp);
  setupPedestals(); placeRiftState(); refreshLegendRig(); refreshWorldLegends(); refreshMarkers();
  snapCamera();
  G.mode = 'world';
  Area.cur = Area.cand = fresh ? '윤슬마을' : null; Area.t = 0;
  if (fresh) Area.shown['윤슬마을'] = performance.now() / 1000;
  Snd.play('world');
  await fadeTo(0, 1.0);
  showHud(true);
  if (!fresh) setTimeout(() => { if (G.mode === 'world' && !G.busy) checkLegendAwakenings(); }, 1500);
  if (fresh) {
    await banner('윤슬마을', 'THE BOUNDARY ISLE', 'plain', 2.4);
    toast('분수 앞의 장로에게 다가가 E(또는 A)를 눌러 보세요');
  } else toast('모험을 이어서 시작합니다');
}

// ---------------------------------------------------------------- main loop
let lastT = performance.now();
function frame(now) {
  const rdt = Math.min(0.05, (now - lastT) / 1000); lastT = now;
  const dt = rdt * timeScale();
  Post.update(rdt);
  Shared.time.value += dt;
  Tw.update(dt);
  try {
    if (G.mode === 'battle') { updateBattle(dt); renderScene(Battle.scene, Battle.camera); }
    else {
      if (G.mode === 'title' || G.mode === 'lore') titleCam(dt);
      updateTitleRig(dt, G.mode === 'title' || G.mode === 'lore');
      updateWorld(dt, canMove());
      worldTick(dt);
      renderScene(World.scene, World.camera);
    }
  } catch (e) { console.error(e); }
  requestAnimationFrame(frame);
}

async function boot() {
  $('#loadMsg').textContent = '섬을 빚는 중…';
  await sleep(30);
  buildWorld();
  buildBattle();
  for (const d of NPC_DEFS) addNpc(d);
  for (const d of NPC_DEFS) Icons.portrait(d.id, d.look);
  applyQuality();
  setupPedestals(); placeRiftState(); refreshMarkers();
  G.mode = 'title';
  $('#btnGfx').textContent = '그래픽: ' + gfxLabel();
  $('#btnSnd').textContent = '소리: ' + (Settings.sound ? '켬' : '끔');
  const existing = loadSave();
  if (existing) $('#btnCont').hidden = false;
  if (isTouch) { $('#keysHelp').textContent = '왼쪽 스틱으로 이동 · A 버튼으로 상호작용 · 화면을 끌어 시점 회전'; document.body.classList.add('has-touch'); }
  requestAnimationFrame(frame);
  window.__booted = true; clearTimeout(window.__bootTimer);
  await sleep(120);
  $('#loading').hidden = true; $('#title').hidden = false;
  let armed = false;
  $('#btnNew').onclick = async () => {
    if (existing && !armed) { armed = true; $('#btnNew').textContent = '한 번 더 누르면 새로 시작'; return; }
    Snd.init(); Snd.play('title'); Snd.fx('confirm');
    S = newState(); setupPedestals(); placeRiftState(); refreshMarkers();
    $('#title').hidden = true;
    await playLore();
    await enterWorld(true);
    save();
  };
  $('#btnCont').onclick = async () => {
    Snd.init(); Snd.fx('confirm');
    S = existing;
    $('#title').hidden = true;
    await fadeTo(1, 0.6);
    await enterWorld(false);
  };
  $('#btnGfx').onclick = () => { cycleGfx(); $('#btnGfx').textContent = '그래픽: ' + gfxLabel(); };
  $('#btnSnd').onclick = () => { Snd.init(); Snd.setOn(!Settings.sound); $('#btnSnd').textContent = '소리: ' + (Settings.sound ? '켬' : '끔'); };
  window.addEventListener('beforeunload', () => { if (G.mode === 'world' && S.party.length) save(); });
}

// small debugging surface (used by the automated test harness)
window.__game = { get S() { return S; }, set S(v) { S = v; }, G, World, Battle, startWild, battleFlow, legendBattle, makeMon, enterWorld, setupPedestals, placeRiftState, refreshMarkers, refreshLegendRig, setFollower, closeRift, NPC_DEFS, altarAwaken, ensiaDescends, ending, SPECIES, Icons, updateHud, legendEncounter, checkLegendAwakenings, refreshWorldLegends, makeSpiritModel, snapCamera, say, showArea, areaAt, Area, updateCompass, starterSelect };
boot().catch((e) => { console.error(e); $('#loadMsg').textContent = '시작하는 중 문제가 생겼어요: ' + e.message; });
