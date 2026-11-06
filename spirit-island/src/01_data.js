// ============================================================================
//  data: types, moves, spirits, items + spirit math
// ============================================================================
const TYPES = {
  normal:  { n: '일반',   c: '#cfc6b4', hex: 0xcfc6b4 },
  fire:    { n: '불',     c: '#ff8a4c', hex: 0xff6a2a },
  water:   { n: '물',     c: '#5cb8ff', hex: 0x3fa7ff },
  grass:   { n: '풀',     c: '#6fdc78', hex: 0x4fd060 },
  thunder: { n: '번개',   c: '#ffd84a', hex: 0xffd23f },
  earth:   { n: '대지',   c: '#d39a5c', hex: 0xc08a4f },
  light:   { n: '빛',     c: '#fff1a8', hex: 0xfff1a8 },
  shadow:  { n: '그림자', c: '#a885ff', hex: 0x8b5cff },
  being:   { n: '존재',   c: '#f2d48a', hex: 0xffd98a },
  void:    { n: '공허',   c: '#c77dff', hex: 0xb04bff },
};
// attacker -> defender multipliers (missing = 1)
const CHART = {
  normal:  { earth: 0.5, void: 0 },
  fire:    { grass: 2, water: 0.5, fire: 0.5, earth: 0.5 },
  water:   { fire: 2, earth: 2, water: 0.5, grass: 0.5 },
  grass:   { water: 2, earth: 2, fire: 0.5, grass: 0.5 },
  thunder: { water: 2, earth: 0, grass: 0.5, thunder: 0.5 },
  earth:   { fire: 2, thunder: 2, grass: 0.5 },
  light:   { shadow: 2, void: 2, light: 0.5 },
  shadow:  { light: 2, being: 2, shadow: 0.5 },
  being:   { void: 2, shadow: 2, being: 0.5 },
  void:    { being: 2, light: 2, normal: 2, void: 0.5 },
};
function typeEff(atk, defTypes) { let m = 1; for (const d of defTypes) { const v = CHART[atk] && CHART[atk][d]; if (v !== undefined) m *= v; } return m; }
function typeChip(t) { const T = TYPES[t]; return `<span class="type" style="background:${T.c}">${T.n}</span>`; }

// fx: dash slash bolt burst beam rain strike aura glare heal drain void genesis
const MOVES = {
  rush:      { n: '돌진',         t: 'normal',  p: 40,  a: 100, fx: 'dash',    d: '온몸으로 부딪친다.' },
  claw:      { n: '발톱긁기',     t: 'normal',  p: 50,  a: 95,  fx: 'slash',   d: '날카로운 발톱으로 긁는다.' },
  charge:    { n: '맹돌격',       t: 'normal',  p: 75,  a: 90,  fx: 'dash',    d: '힘을 실어 전력으로 들이받는다.' },
  focus:     { n: '기합모으기',   t: 'normal',  p: 0,   a: 100, fx: 'aura',    eff: { self: { atk: 1 } }, d: '공격이 오른다.' },
  glare:     { n: '위압',         t: 'normal',  p: 0,   a: 100, fx: 'glare',   eff: { foe: { def: -1 } }, d: '상대의 방어가 내려간다.' },
  ember:     { n: '불티',         t: 'fire',    p: 40,  a: 100, fx: 'bolt',    eff: { burn: 0.1 }, d: '작은 불꽃을 날린다. 가끔 화상.' },
  flamedash: { n: '화염돌진',     t: 'fire',    p: 70,  a: 95,  fx: 'dash',    d: '불꽃을 두르고 돌진한다.' },
  inferno:   { n: '업화',         t: 'fire',    p: 95,  a: 90,  fx: 'burst',   eff: { burn: 0.2 }, d: '모든 것을 태우는 불길. 화상을 입히기 쉽다.' },
  spray:     { n: '물보라',       t: 'water',   p: 40,  a: 100, fx: 'bolt',    d: '물방울을 세차게 쏜다.' },
  wave:      { n: '파도치기',     t: 'water',   p: 70,  a: 100, fx: 'rain',    d: '거센 물결을 덮친다.' },
  tsunami:   { n: '해일',         t: 'water',   p: 95,  a: 85,  fx: 'burst',   d: '바다를 통째로 쏟아붓는다.' },
  drizzle:   { n: '단비',         t: 'water',   p: 0,   a: 100, fx: 'heal',    eff: { heal: 0.45 }, d: '체력을 크게 회복한다.' },
  leaf:      { n: '잎날',         t: 'grass',   p: 40,  a: 100, fx: 'slash',   d: '날카로운 잎으로 벤다.' },
  vinedrain: { n: '흡수덩굴',     t: 'grass',   p: 60,  a: 100, fx: 'drain',   eff: { drain: 0.5 }, d: '준 피해의 절반만큼 회복한다.' },
  petal:     { n: '꽃폭풍',       t: 'grass',   p: 90,  a: 90,  fx: 'rain',    d: '꽃잎이 소용돌이친다.' },
  spark:     { n: '스파크',       t: 'thunder', p: 40,  a: 100, fx: 'bolt',    eff: { para: 0.1 }, d: '전기를 튀긴다. 가끔 마비.' },
  shocknet:  { n: '전격망',       t: 'thunder', p: 0,   a: 90,  fx: 'glare',   eff: { para: 1 }, d: '상대를 마비시킨다.' },
  thunderfall:{ n: '낙뢰',        t: 'thunder', p: 90,  a: 85,  fx: 'strike',  eff: { para: 0.2 }, d: '하늘에서 벼락을 내리꽂는다.' },
  sandwind:  { n: '모래바람',     t: 'earth',   p: 0,   a: 100, fx: 'rain',    eff: { foe: { spd: -1 } }, d: '상대의 속도가 내려간다.' },
  rock:      { n: '바위던지기',   t: 'earth',   p: 60,  a: 90,  fx: 'bolt',    d: '바위를 던진다.' },
  quake:     { n: '대지진동',     t: 'earth',   p: 90,  a: 95,  fx: 'burst',   d: '땅을 뒤흔든다.' },
  flash:     { n: '섬광',         t: 'light',   p: 45,  a: 100, fx: 'burst',   d: '눈부신 빛을 터뜨린다.' },
  lance:     { n: '빛의창',       t: 'light',   p: 80,  a: 95,  fx: 'beam',    d: '빛을 창처럼 모아 꿰뚫는다.' },
  mend:      { n: '치유광',       t: 'light',   p: 0,   a: 100, fx: 'heal',    eff: { heal: 0.5 }, d: '체력을 절반 회복한다.' },
  shclaw:    { n: '그림자손톱',   t: 'shadow',  p: 45,  a: 100, fx: 'slash',   d: '그림자로 만든 손톱.' },
  darkwave:  { n: '어둠파동',     t: 'shadow',  p: 80,  a: 95,  fx: 'void',    d: '짙은 어둠의 파동.' },
  nightmare: { n: '악몽',         t: 'shadow',  p: 0,   a: 100, fx: 'glare',   eff: { foe: { atk: -1 } }, d: '상대의 공격이 내려간다.' },
  starshot:  { n: '별조각',       t: 'being',   p: 55,  a: 100, fx: 'bolt',    d: '존재의 조각을 쏜다.' },
  origin:    { n: '근원파동',     t: 'being',   p: 85,  a: 100, fx: 'beam',    d: '모든 것이 시작된 곳의 파동.' },
  proof:     { n: '존재증명',     t: 'being',   p: 0,   a: 100, fx: 'aura',    eff: { self: { atk: 1, def: 1, spd: 1 }, heal: 0.25 }, d: '모든 능력이 오르고 체력을 조금 회복한다.' },
  genesis:   { n: '창세의빛',     t: 'being',   p: 120, a: 90,  fx: 'genesis', d: '세계가 처음 빛났던 순간을 재현한다.' },
  nibble:    { n: '틈새갉기',     t: 'void',    p: 45,  a: 100, fx: 'slash',   d: '존재의 틈을 갉아먹는다.' },
  erase:     { n: '허무의손길',   t: 'void',    p: 60,  a: 100, fx: 'void',    eff: { reset: true }, d: '상대의 능력 변화를 모두 지운다.' },
  vanish:    { n: '소멸',         t: 'void',    p: 0,   a: 100, fx: 'void',    eff: { foe: { def: -2 } }, d: '상대의 방어가 크게 내려간다.' },
  horizon:   { n: '사건의지평선', t: 'void',    p: 85,  a: 100, fx: 'drain',   eff: { drain: 0.5 }, d: '빛조차 돌아오지 못하는 경계. 피해의 절반을 흡수한다.' },
  collapse:  { n: '공허붕괴',     t: 'void',    p: 120, a: 90,  fx: 'void',    d: '존재를 무(無)로 되돌린다.' },
};

// b = [hp, atk, def, spd]
const SPECIES = {
  hwarr:   { no: 1,  n: '화르르',   t: ['fire'],    b: [45, 60, 45, 65], rate: 45,  xp: 62,  evo: { to: 'yeomho', lv: 16 },
    learn: [[1, 'rush'], [1, 'glare'], [4, 'ember'], [9, 'claw'], [13, 'flamedash'], [21, 'focus'], [27, 'inferno']],
    d: '꼬리 끝 불씨가 꺼지지 않는 한 절대 포기하지 않는다. 기분이 좋으면 불꽃이 하트 모양이 된다.' },
  yeomho:  { no: 2,  n: '염호',     t: ['fire'],    b: [72, 94, 66, 96], rate: 45,  xp: 150,
    learn: [[1, 'rush'], [1, 'glare'], [4, 'ember'], [9, 'claw'], [13, 'flamedash'], [16, 'charge'], [21, 'focus'], [27, 'inferno']],
    d: '세 갈래 꼬리의 불꽃으로 밤을 밝힌다. 공허의 어둠도 이 불꽃 앞에서는 잠시 물러선다.' },
  mullong: { no: 3,  n: '물롱',     t: ['water'],   b: [55, 50, 62, 45], rate: 45,  xp: 62,  evo: { to: 'padolong', lv: 16 },
    learn: [[1, 'rush'], [1, 'glare'], [4, 'spray'], [9, 'claw'], [13, 'wave'], [19, 'drizzle'], [27, 'tsunami']],
    d: '머리 위 물방울에는 처음 태어난 바다의 기억이 담겨 있다. 울면 비가 온다.' },
  padolong:{ no: 4,  n: '파도롱',   t: ['water'],   b: [88, 80, 92, 64], rate: 45,  xp: 150,
    learn: [[1, 'rush'], [1, 'glare'], [4, 'spray'], [9, 'claw'], [13, 'wave'], [16, 'charge'], [19, 'drizzle'], [27, 'tsunami']],
    d: '몸을 감싼 물의 고리는 밀물과 썰물을 따라 빛난다. 섬의 바다를 지키는 수호자.' },
  saessak: { no: 5,  n: '새싹뿔',   t: ['grass'],   b: [50, 55, 55, 56], rate: 45,  xp: 62,  evo: { to: 'supppul', lv: 16 },
    learn: [[1, 'rush'], [1, 'glare'], [4, 'leaf'], [9, 'claw'], [13, 'vinedrain'], [21, 'focus'], [27, 'petal']],
    d: '머리의 새싹은 주인을 믿을수록 자란다. 아침 이슬을 좋아한다.' },
  supppul: { no: 6,  n: '숲뿔사슴', t: ['grass'],   b: [80, 86, 80, 80], rate: 45,  xp: 150,
    learn: [[1, 'rush'], [1, 'glare'], [4, 'leaf'], [9, 'claw'], [13, 'vinedrain'], [16, 'charge'], [21, 'focus'], [27, 'petal']],
    d: '뿔에서 피어난 꽃은 밤이 되면 빛을 낸다. 지나간 자리에 숲이 생긴다는 전설이 있다.' },
  jjirit:  { no: 7,  n: '찌릿파리', t: ['thunder'], b: [45, 62, 40, 75], rate: 120, xp: 70,
    learn: [[1, 'spark'], [5, 'glare'], [10, 'shocknet'], [15, 'charge'], [20, 'thunderfall']],
    d: '폭풍우가 지나간 뒤 바닷가에 떠다니는 해파리 정령. 만지면 머리카락이 선다.' },
  bawimong: { no: 8, n: '바위몽',   t: ['earth'],   b: [62, 62, 80, 28], rate: 140, xp: 72,
    learn: [[1, 'rush'], [5, 'sandwind'], [9, 'rock'], [15, 'focus'], [20, 'quake']],
    d: '등의 보랏빛 결정은 수천 년 동안 공허를 막아 온 흔적이다. 느리지만 단단하다.' },
  bandiru: { no: 9,  n: '반디루',   t: ['light'],   b: [42, 52, 45, 74], rate: 170, xp: 64,
    learn: [[1, 'flash'], [4, 'glare'], [9, 'mend'], [14, 'lance'], [22, 'focus']],
    d: '꽁무니의 빛은 길 잃은 정령을 집으로 데려다준다. 공허의 존재를 싫어한다.' },
  geurim:  { no: 10, n: '그림냥',   t: ['shadow'],  b: [52, 68, 45, 78], rate: 120, xp: 70,
    learn: [[1, 'shclaw'], [4, 'nightmare'], [9, 'claw'], [14, 'darkwave'], [22, 'focus']],
    d: '그림자에서 그림자로 옮겨 다닌다. 빛의 정령을 놀리는 것이 취미.' },
  somgu:   { no: 11, n: '솜구름',   t: ['normal'],  b: [65, 45, 52, 42], rate: 200, xp: 50,
    learn: [[1, 'rush'], [3, 'glare'], [7, 'focus'], [12, 'charge']],
    d: '하늘에서 떨어진 구름 조각이 정령이 되었다. 껴안으면 잠이 온다.' },
  beoseot: { no: 12, n: '버섯콩',   t: ['grass'],   b: [56, 50, 58, 40], rate: 190, xp: 52,
    learn: [[1, 'rush'], [3, 'leaf'], [8, 'vinedrain'], [13, 'focus']],
    d: '비 온 다음 날 무리지어 나타난다. 모자의 점 개수로 나이를 알 수 있다.' },
  teum:    { no: 13, n: '틈벌레',   t: ['void'],    b: [50, 72, 55, 62], rate: 90,  xp: 84,
    learn: [[1, 'nibble'], [8, 'nightmare'], [12, 'vanish'], [16, 'erase'], [22, 'horizon']],
    d: '하늘의 균열에서 떨어져 나온 공허의 조각. 존재하는 것을 조금씩 갉아먹는다.' },
  byeolssi:{ no: 14, n: '별씨',     t: ['being'],   b: [55, 64, 60, 70], rate: 60,  xp: 96,
    learn: [[1, 'starshot'], [8, 'mend'], [14, 'proof'], [20, 'origin']],
    d: '엔시아가 흘린 빛에서 태어났다고 전해진다. 제단 근처에서 아주 드물게 보인다.' },
  nihilos: { no: 15, n: '니힐로스', t: ['void'],    b: [108, 106, 92, 98], rate: 3, xp: 300, legend: true,
    learn: [[1, 'erase'], [1, 'vanish'], [1, 'horizon'], [1, 'darkwave'], [40, 'collapse']],
    d: '공허 그 자체. 모든 존재는 결국 니힐로스에게로 돌아간다. 그 얼굴의 구멍을 오래 들여다본 자는 이름을 잃는다.' },
  ensia:   { no: 16, n: '엔시아',   t: ['being'],   b: [114, 100, 100, 94], rate: 3, xp: 300, legend: true,
    learn: [[1, 'origin'], [1, 'proof'], [1, 'lance'], [1, 'mend'], [40, 'genesis']],
    d: '존재 그 자체. 엔시아가 눈을 뜨자 첫 번째 빛이 생겼다. 공허가 없으면 자신도 없다는 것을 아는 유일한 존재.' },
};
const DEX_ORDER = Object.keys(SPECIES).sort((a, b) => SPECIES[a].no - SPECIES[b].no);
const STARTERS = ['hwarr', 'mullong', 'saessak'];

const ITEMS = {
  crystal: { n: '봉인결정', d: '약해진 정령을 결정 속에 봉인해 동료로 만든다.', battle: true, catch: 1 },
  potion:  { n: '회복약',   d: '정령 하나의 체력을 50 회복한다.', battle: true, heal: 50, field: true },
  elixir:  { n: '고급회복약', d: '정령 하나의 체력을 모두 회복하고 상태 이상을 치료한다.', battle: true, heal: 9999, field: true },
  origin:  { n: '근원결정', d: '존재와 공허의 틈에서 빚은 결정. 전설의 정령도 봉인할 수 있을 만큼 강하다.', battle: true, catch: 22 },
};

// ---------------------------------------------------------------- spirit math
function learnedMoves(sp, lv) {
  const L = SPECIES[sp].learn.filter(([l]) => l <= lv).map(([, m]) => m);
  return [...new Set(L)].slice(-4);
}
function maxHp(m) { return Math.floor((2 * SPECIES[m.sp].b[0] + m.iv[0]) * m.lv / 100) + m.lv + 10; }
function stat(m, i) { return Math.floor((2 * SPECIES[m.sp].b[i] + m.iv[i]) * m.lv / 100) + 5; }
function expNeed(lv) { return Math.floor(10 + lv * lv * 0.95); }
let _uid = 1;
function makeMon(sp, lv) {
  const m = { uid: Date.now().toString(36) + (_uid++), sp, lv, exp: 0, iv: [randi(0, 15), randi(0, 15), randi(0, 15), randi(0, 15)], moves: learnedMoves(sp, lv), status: null };
  m.hp = maxHp(m);
  return m;
}
function monName(m) { return SPECIES[m.sp].n; }
function monTypes(m) { return SPECIES[m.sp].t; }
function stageMul(s) { return s >= 0 ? (2 + s) / 2 : 2 / (2 - s); }
function hpColor(f) { return f > 0.5 ? 'var(--hp-good)' : f > 0.2 ? 'var(--hp-mid)' : 'var(--hp-low)'; }

// encounter pools for the tall-grass meadows
const POOLS = {
  south: [{ sp: 'somgu', lv: [3, 5], w: 40 }, { sp: 'beoseot', lv: [3, 5], w: 35 }, { sp: 'bandiru', lv: [4, 6], w: 25 }],
  east:  [{ sp: 'bawimong', lv: [7, 10], w: 40 }, { sp: 'geurim', lv: [8, 10], w: 25 }, { sp: 'somgu', lv: [7, 9], w: 20 }, { sp: 'hwarr', lv: [8, 9], w: 4 }, { sp: 'saessak', lv: [8, 9], w: 4 }, { sp: 'mullong', lv: [8, 9], w: 4 }],
  west:  [{ sp: 'jjirit', lv: [8, 11], w: 40 }, { sp: 'bandiru', lv: [8, 10], w: 25 }, { sp: 'beoseot', lv: [8, 10], w: 20 }, { sp: 'mullong', lv: [9, 10], w: 4 }, { sp: 'hwarr', lv: [9, 10], w: 4 }, { sp: 'saessak', lv: [9, 10], w: 4 }],
  north: [{ sp: 'geurim', lv: [12, 15], w: 35 }, { sp: 'teum', lv: [12, 15], w: 30 }, { sp: 'jjirit', lv: [12, 14], w: 20 }, { sp: 'bawimong', lv: [13, 15], w: 15 }],
  altar: [{ sp: 'teum', lv: [15, 18], w: 45 }, { sp: 'bandiru', lv: [15, 17], w: 30 }, { sp: 'bawimong', lv: [15, 18], w: 17 }, { sp: 'byeolssi', lv: [16, 18], w: 8 }],
};
function rollPool(pool) {
  const tot = pool.reduce((s, e) => s + e.w, 0); let r = Math.random() * tot;
  for (const e of pool) { r -= e.w; if (r <= 0) return e; }
  return pool[0];
}
