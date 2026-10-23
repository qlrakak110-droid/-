export const meta = {
  name: 'club-allages-text-sweep',
  description: 'Make every CLUB OCEAN interior text all-ages: no alcohol/brand/age-gate/유흥주점 wording, drinks as 음료/에이드/목테일; then verify',
  phases: [
    { title: 'Sweep', detail: 'rewrite club interior texts in T_club / T_clubmain' },
    { title: 'Verify', detail: 'independent grep + sim + visual check' },
  ],
}
const S = '/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad'
const BI = '/home/user/-/src/StarterPlayer/StarterPlayerScripts/GwangalliBuildingInterior'
const RULES = `
# Context
Roblox game "광안리 (Gwangalli)". The club CLUB OCEAN 광안 is played by all ages. The owner asked for "술 같은 음료" (drinks that look like a real club's drinks but are 음료). Our team's rule for the club: drinks are non-alcoholic 음료 (signature 에이드, 목테일 / mocktail, 무알콜 스파클링, 탄산, 주스, 에너지 드링크, 생수, 커피), no real alcohol words, no real brand names, no age gate (no "19+", no "N년생부터 입장/출입 불가", no 신분증 필수 for age), no "유흥주점" licence text (use 휴게음식점영업 or 일반음식점영업 — prefer 휴게음식점영업), no romance wording or hearts in 합석/social contexts. The existing in-game club order menu (place server BottleService / GwangalliClubPlus UI) uses fictional names: signature ades ~9,000, mocktails ~10,000, bottle-service style 'premium sparkling' sets; read ${S}/bld/src for the place's BottleService / club menu script (grep -rln "BottleService\\|Bottle" ${S}/bld/src | head) and src/ReplicatedStorage/GwangalliClubPlusShared + src/ServerScriptService/GwangalliClubPlus to reuse the same names and prices so wall menus match what players can order.
Files you may edit: ${BI}/T_club.luau and ${BI}/T_clubmain.luau ONLY (other agents edit other files; never git commit/push/checkout). Keep visuals: bottles on back bars can stay as glass bottles but their labels/texts become syrups, sparkling waters, juices, 무알콜 — e.g. 'BLUE LAGOON 에이드', '자몽 스파클링', '진저 피즈(무알콜)', '블루 큐라소 시럽', 'OCEAN 스파클링 (무알콜)'. Beer taps become '수제 탄산 · 콤부차 · 하이볼 스타일 무알콜' or 'SODA TAP' etc. Champagne cellar → '스파클링 셀러 (무알콜)'. 'DRESS CODE' signs and house rules may stay without age lines (e.g. 슬리퍼 · 트레이닝복 입장 불가, 안전 수칙, 분실물 안내).
Tools: offline sim ${S}/bprev (simall.sh <keys>, run.sh <key> renders a sheet; use --q ultra for club; heavy, render few). Club fixture keys: grep club ${S}/bprev/batch_all.txt. Luau syntax check: ${S}/luau/luau-compile --binary f >/dev/null.
`
phase('Sweep')
const a = await agent(`${RULES}
# Your job
1. List every user-visible string in T_club.luau and T_clubmain.luau (txt(...), K:text, lightbox, acrylicStand, Props.frame text, menu tables, label arrays, sign texts) and find all violations: alcohol words (술, 소주, 맥주, 생맥주, 하이볼, 칵테일, 위스키, 보드카, 진, 데킬라, 샷, 샴페인, 와인, 예거, 잭콕, 소맥, 알콜/알코올, IPA, BEER, BAR SHOTS, WINE, CHAMPAGNE, COCKTAIL, %도수 like '4.8%' '40%'), real brands (카스, 테라, 참이슬, 코로나, 하이네켄, Jäger, Jack, Moët, Dom, Hennessy, Absolut, Grey Goose, Patrón etc.), age gates (19+, 년생, 성인, 미성년, 신분증 필수 for age), 유흥주점, romance/hearts in social contexts. Also comment-only mentions are fine to leave but prefer updating them.
2. Rewrite each to an all-ages equivalent consistent with the real in-game menu names/prices. Keep string lengths similar so layouts still fit (check text box widths).
3. Compile, run simall.sh on all club fixtures (blocked must stay 0, no errors), render 2 sheets (club_main, club_lounge2f) with --q ultra to confirm texts read right.
Return: the full list of changed strings (old -> new, file:line), sim results, sheet paths.`, { label: 'sweep:club-text', phase: 'Sweep' })
phase('Verify')
const v = await agent(`${RULES}
# Your job: VERIFY the sweep below independently. Assume it missed things.
Sweep report:
-----
${a}
-----
1. grep T_club.luau and T_clubmain.luau yourself for every banned pattern (case-insensitive, Korean and English, including inside menu tables and multi-line strings) and fix any leftover user-visible one.
2. Also grep (READ-ONLY, report only, do not edit) src/ServerScriptService/GwangalliClubPlus, src/StarterPlayer/StarterPlayerScripts/GwangalliClubPlus, src/ReplicatedStorage/GwangalliClubPlusShared for the same patterns and list hits with file:line.
3. Check that new strings fit their boxes (rough char count vs width) and that nothing else changed (git diff --stat should show only the two files; read the diff).
4. Re-run simall.sh on club fixtures; compile.
Return: leftovers fixed, ClubPlus hits (file:line + text), final grep counts, sim results.`, { label: 'verify:club-text', phase: 'Verify' })
return { a, v }
