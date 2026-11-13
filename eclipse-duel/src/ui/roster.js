// Roster and menu data of 「흑일무림 黑日武林」: the one place where the player-facing names live (MURIM.md § 2-3).
// src/fighters/registry.js re-exports it as ROSTER (plus the ultimate moods); the menus fall back to it until the game
// passes its own through ui.show('select', { roster }). Code ids (`kael`, `iska`, `vorn`), slots, icons and
// `weaponArt` keys never change: only what is read on screen.
//
// Naming rule: Korean reading first, Hanja as the accent, a short English gloss third.
//   normals  기본 초식   three characters: an image + the technique (斬 cut, 劈 cleave, 掃 sweep, 突 charge, 刺 thrust ...)
//   skills   절기 絶技   four characters
//   ultimate 오의 奧義   four characters, fixed by MURIM.md
// Every 초식 is our own invention and says what the move does (src/fighters/MOVES.md has the full table).

/**
 * @typedef {object} RosterMove
 * @property {string} slot    light1 light2 light3 heavy fheavy dheavy skill1 skill2 skill3 ult
 * @property {string} name    Korean reading (e.g. 잔양비참)
 * @property {string} hanja   Hanja (殘陽飛斬)
 * @property {string} nameEn  English gloss
 * @property {string} desc    one line: what it does
 * @property {number} [cost]  내공 cost (skills) / 오의 gauge (ult)
 * @property {number} [cd]    cooldown seconds
 * @property {string} [icon]  icon name (src/ui/icons.js)
 */

/**
 * Stats are 1..5. `name` / `hanja` / `nameEn` = the hero; `title` = 별호; `sect` = 문파; `weapon`; `art` = inner art
 * (내공심법); `seal` = the two characters carved on the hero's seal; `emblem` = sect emblem icon.
 * @type {Array<object>}
 */
export const DEFAULT_ROSTER = [
  {
    id: 'kael', name: '염무강', hanja: '炎武剛', nameEn: 'YEOM MU-GANG',
    title: '적염패도', titleHanja: '赤焰覇刀', titleEn: 'Crimson Flame Tyrant Saber',
    sect: '적양문', sectHanja: '赤陽門', sectEn: 'Red Sun Gate', seal: '赤陽', emblem: 'sect-kael',
    weapon: '참마대도', weaponHanja: '斬馬大刀', weaponEn: 'Great Saber', weaponArt: 'greatsword',
    art: '열양진기', artHanja: '烈陽眞氣', artEn: 'Blazing-Sun Qi', element: 'ember',
    blurb: '산을 가르는 느리고 무거운 일도. 한 번 닿으면 끝난다. 중초에는 호신강기가 실린다.',
    blurbEn: 'Slow, mountain-splitting arcs. Heavies carry guard aura.',
    stats: { power: 5, speed: 2, reach: 4, difficulty: 2 },
    moves: [
      { slot: 'light1', name: '사양참', hanja: '斜陽斬', nameEn: 'Slanting-Sun Cut', desc: '비스듬히 내리긋는 일도' },
      { slot: 'light2', name: '반조격', hanja: '返照擊', nameEn: 'Afterglow Strike', desc: '호를 되돌려 올려치는 역수' },
      { slot: 'light3', name: '낙일벽', hanja: '落日劈', nameEn: 'Setting-Sun Cleave', desc: '바닥까지 내려찍어 쓰러뜨린다' },
      { slot: 'heavy', name: '염륜소', hanja: '炎輪掃', nameEn: 'Flame-Wheel Sweep', desc: '삼백 도 회전 베기 · 호신강기' },
      { slot: 'fheavy', name: '염마돌', hanja: '炎馬突', nameEn: 'Flame-Steed Charge', desc: '어깨로 3.2m 돌진해 찌른다' },
      { slot: 'dheavy', name: '승염참', hanja: '昇炎斬', nameEn: 'Rising-Flame Cut', desc: '땅을 갈라 불기둥으로 띄운다' },
      { slot: 'skill1', name: '잔양비참', hanja: '殘陽飛斬', nameEn: 'Waning-Sun Flying Slash', desc: '불타는 초승 도기를 날린다', cost: 25, cd: 4, icon: 'kael-crescent' },
      { slot: 'skill2', name: '열지분염', hanja: '裂地噴炎', nameEn: 'Earth-Rending Eruption', desc: '갈라진 땅에서 불기둥 넷이 치솟는다', cost: 35, cd: 7, icon: 'kael-eruption' },
      { slot: 'skill3', name: '열양호신', hanja: '烈陽護身', nameEn: 'Blazing-Sun Ward', desc: '받아치기 자세 · 맞으면 화염으로 되튕긴다', cost: 30, cd: 9, icon: 'kael-bulwark' },
      { slot: 'ult', name: '흑일분천', hanja: '黑日焚天', nameEn: 'Black Sun Burns the Heavens', desc: '도약 일도가 닿으면 다섯 숨의 연환살', cost: 100, icon: 'kael-ult' },
    ],
  },
  {
    id: 'iska', name: '설리화', hanja: '雪梨花', nameEn: 'SEOL RI-HWA',
    title: '빙월쌍도', titleHanja: '氷月雙刀', titleEn: 'Frost-Moon Twin Blades',
    sect: '한월궁', sectHanja: '寒月宮', sectEn: 'Cold Moon Palace', seal: '寒月', emblem: 'sect-iska',
    weapon: '월아쌍도', weaponHanja: '月牙雙刀', weaponEn: 'Twin Crescent Blades', weaponArt: 'crescents',
    art: '한빙진기', artHanja: '寒氷眞氣', artEn: 'Cold-Ice Qi', element: 'frost',
    blurb: '달빛처럼 가볍고 서리처럼 날카롭다. 쾌도 연환과 원거리 견제, 허공을 딛는 신법.',
    blurbEn: 'Light as moonlight, sharp as frost. Fast strings, zoning, aerial footwork.',
    stats: { power: 3, speed: 5, reach: 3, difficulty: 4 },
    moves: [
      { slot: 'light1', name: '한광섬', hanja: '寒光閃', nameEn: 'Cold-Gleam Flash', desc: '오른손의 빠른 일섬' },
      { slot: 'light2', name: '쌍월전', hanja: '雙月剪', nameEn: 'Twin-Moon Shears', desc: '좌우로 엇갈려 베는 가위질' },
      { slot: 'light3', name: '성선무', hanja: '星扇舞', nameEn: 'Star-Fan Dance', desc: '돌며 두 번 베어 밀어낸다' },
      { slot: 'heavy', name: '빙륜선', hanja: '氷輪旋', nameEn: 'Ice-Wheel Whirl', desc: '온몸으로 도는 삼연참' },
      { slot: 'fheavy', name: '은하도', hanja: '銀河渡', nameEn: 'Silver-River Crossing', desc: '얼음길을 미끄러지며 베어 지난다' },
      { slot: 'dheavy', name: '신월승', hanja: '新月昇', nameEn: 'New-Moon Rising', desc: '공중제비로 올려 베어 띄운다' },
      { slot: 'skill1', name: '한성삼사', hanja: '寒星三射', nameEn: 'Three Cold-Star Shots', desc: '빙정 셋을 잇달아 쏜다 · 셋째는 빙결', cost: 20, cd: 3.5, icon: 'iska-shards' },
      { slot: 'skill2', name: '빙순파지', hanja: '氷筍破地', nameEn: 'Ice Shoots Break the Earth', desc: '땅을 뚫고 점점 커지는 얼음 죽순', cost: 30, cd: 6, icon: 'iska-procession' },
      { slot: 'skill3', name: '월영환신', hanja: '月影幻身', nameEn: 'Moon-Shadow Phantom', desc: '빙상 잔영을 남기고 등 뒤를 벤다', cost: 25, cd: 7, icon: 'iska-afterimage' },
      { slot: 'ult', name: '빙성낙월', hanja: '氷星落月', nameEn: 'Frost Star, Falling Moon', desc: '성진이 닫히면 다섯 숨의 연환살', cost: 100, icon: 'iska-ult' },
    ],
  },
  {
    id: 'vorn', name: '뇌진천', hanja: '雷震天', nameEn: 'NOE JIN-CHEON',
    title: '천뢰신창', titleHanja: '天雷神槍', titleEn: 'Heaven-Thunder Spear',
    sect: '뇌운보', sectHanja: '雷雲堡', sectEn: 'Thundercloud Keep', seal: '雷雲', emblem: 'sect-vorn',
    weapon: '뇌룡창', weaponHanja: '雷龍槍', weaponEn: 'Thunder-Dragon Spear', weaponArt: 'spear',
    art: '뇌정신공', artHanja: '雷霆神功', artEn: 'Thunderclap Art', element: 'volt',
    blurb: '가장 긴 간격과 벼락 같은 돌진. 호신강기를 꿰뚫는 창끝.',
    blurbEn: 'Longest reach, thunderbolt dashes, guard-piercing thrusts.',
    stats: { power: 4, speed: 3, reach: 5, difficulty: 3 },
    moves: [
      { slot: 'light1', name: '전광자', hanja: '電光刺', nameEn: 'Lightning-Flash Thrust', desc: '간격이 긴 빠른 찌르기' },
      { slot: 'light2', name: '용미격', hanja: '龍尾擊', nameEn: 'Dragon-Tail Strike', desc: '창을 돌려 창준으로 친다' },
      { slot: 'light3', name: '뇌침관', hanja: '雷針貫', nameEn: 'Thunder-Needle Pierce', desc: '창끝에서 뇌기가 뻗는 관통 찌르기' },
      { slot: 'heavy', name: '풍뢰소', hanja: '風雷掃', nameEn: 'Wind-and-Thunder Sweep', desc: '낮게 쓸어 쓰러뜨린다' },
      { slot: 'fheavy', name: '분뢰돌', hanja: '奔雷突', nameEn: 'Racing-Thunder Charge', desc: '4m 뇌전 돌진 · 호신강기 관통' },
      { slot: 'dheavy', name: '충천창', hanja: '衝天槍', nameEn: 'Sky-Piercing Spear', desc: '하늘로 찔러 올려 띄운다' },
      { slot: 'skill1', name: '천뢰일척', hanja: '天雷一擲', nameEn: "Heaven's Thunder, One Throw", desc: '뇌기로 빚은 창을 던진다 · 마비', cost: 25, cd: 4, icon: 'vorn-javelin' },
      { slot: 'skill2', name: '낙뢰삼격', hanja: '落雷三擊', nameEn: 'Three Falling Thunderbolts', desc: '상대의 발밑에 벼락 셋', cost: 35, cd: 7, icon: 'vorn-stormfall' },
      { slot: 'skill3', name: '화뢰섬보', hanja: '化雷閃步', nameEn: 'Thunder-Form Flash Step', desc: '벼락이 되어 꿰뚫고 지난다', cost: 20, cd: 5, icon: 'vorn-arcstep' },
      { slot: 'ult', name: '구천뇌벌', hanja: '九天雷罰', nameEn: 'Ninefold Heaven Thunder Judgment', desc: '돌진 찌르기가 닿으면 다섯 숨의 연환살', cost: 100, icon: 'vorn-ult' },
    ],
  },
];

/** CPU ranks (value is what ui emits in the 'pick' event): 삼류 → 이류 → 일류 → 절정. */
export const DIFFICULTIES = [
  { value: 'easy', name: '삼류', hanja: '三流', nameEn: 'THIRD-RATE' },
  { value: 'normal', name: '이류', hanja: '二流', nameEn: 'SECOND-RATE' },
  { value: 'hard', name: '일류', hanja: '一流', nameEn: 'FIRST-RATE' },
  { value: 'nightmare', name: '절정', hanja: '絶頂', nameEn: 'PEAK' },
];

/** Quality tiers shown in the menus (value matches ctx.quality.tier). */
export const QUALITIES = [
  { value: 'low', name: '낮음', hanja: '下', nameEn: 'LOW' },
  { value: 'mid', name: '중간', hanja: '中', nameEn: 'MID' },
  { value: 'high', name: '높음', hanja: '上', nameEn: 'HIGH' },
];

/** Inner-energy (element) display names. */
export const ELEMENTS = {
  ember: { name: '열양', hanja: '烈陽', nameEn: 'FIRE' },
  frost: { name: '한빙', hanja: '寒氷', nameEn: 'FROST' },
  volt: { name: '뇌정', hanja: '雷霆', nameEn: 'LIGHTNING' },
};

/** The arena and the wording shared by screens and the HUD (MURIM.md § 3-4). */
export const ARENA = { arena: '천무대', arenaHanja: '天武臺', arenaEn: 'HEAVEN-MARTIAL TERRACE' };
export const TITLE = { name: '흑일무림', hanja: '黑日武林', nameEn: 'ECLIPSE DUEL', tag: '검은 해가 뜨는 밤, 강호는 비무로 답한다', tagEn: 'Under the black sun, the martial world answers in duels' };
