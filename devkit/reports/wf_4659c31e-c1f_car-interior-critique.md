# car-interior-critique (wf_4659c31e-c1f)

- status: completed
- failed agents (never finished, usually the usage limit): none

## critique:carnival

```json
{
 "car": "Kia Carnival KA4 (2021-2023), style key \"carnival\"",
 "summary": "The cabin already follows the KA4 layout (one glass panel with the twin 12.3-inch screens and a brow over the cluster half, a satin vent band over a wood band, a knurled dial on a tall console, KRELL door woofers), so it reads as a Carnival from a distance. The biggest gaps are a broken centre stack (the start button sits on the left centre vent, the vents are hidden behind the display's lower edge, and the infotainment and climate strips overlap with two knobs stacked at each end) and a generic wheel and console (a ball-shaped hub, lower spokes like round pipes, and a grey deck with chrome cupholder rings instead of a piano-black panel).",
 "issues": [
  {
   "rank": 1,
   "severity": "high",
   "area": "vents",
   "observed": "carnival_1_driver.png: under the nav, the metal band shows no vent slots; the centre vents are hidden behind the panoramic display's lower edge (only a 4 px sliver of the left vent shows). carnival_3_center.png: only the lower rim curves of the two centre vents peek out. Below that, the InfoTouch strip (y 2.12-2.22) and the ClimateTouch panel (y 2.015-2.165) overlap into one cluttered strip, with InfoKnob (y 2.17) and SmallKnob (y 2.09) stacked at each end. carnival_3_center.png and carnival_4_dash.png: the strips float 0.13 in front of the recessed DashLower face (z -2.38).",
   "real": "KA4: the panoramic glass sits on the upper pad. Directly below it is the satin metal garnish with two slim centre vents and the hazard button between them, all clearly visible from the driver's seat. Under that, the gloss-black infotainment touch strip (volume and tune knobs at its ends) is set into the wood band. Below that is a separate gloss-black climate panel, then the charging tray and console, as distinct stacked layers on a solid fascia.",
   "fix": "Dash.luau, Dash.build metal_wood branch, plus one line in body(). Measured: top 2.75, conTop 1.99, face -2.30, DashLower face -2.38. Display glass centre y 2.777 (yS 2.77, h 0.44); the bezel/DisplayEdge bottom is at y 2.497-2.509, z -2.07. I projected these points through the harness cameras: driver (-1.30,3.59,0.75) and (-1.30,3.54,0.35), centre (0.55,3.19,0.55), dash (1.235,3.54,1.0) and (1.235,3.39,0.55). The projection reproduces the render (start button predicted at (585,335) in _3_center, observed at about (582,337)). The old band (my 2.45, top 2.525) is half to two-thirds hidden. my = min(top-0.405, scrBottom-0.21) = 2.345 puts the band top at 2.41, which clears the display edge by 1-7 px in every shot. New stack: band h 0.13 (2.28-2.41), vents h 0.06; wood wy = my-0.115 = 2.23, h 0.10 (2.18-2.28); ambient line on the band/wood seam at 2.28; info strip iy = wy, h 0.08 (2.19-2.27); climate at max(conTop+0.115, iy-0.125) = 2.105 (2.03-2.18), leaving a 0.01 gap and sitting on the deck top (2.03). A new StackBack (1.24 wide, conTop 1.99 to 2.28, z face-0.03, depth 0.12) fills the recess behind the strips. For metal_wood the glovebox top moves to mid-0.24 = 2.12 so it is not hidden under the lowered wood band.",
   "code": "-- Dash.luau, Dash.build: replace the whole `elseif g == \"metal_wood\" then` branch (lines 298-321) with:\n\telseif g == \"metal_wood\" then\n\t\t-- 카니발 KA4: 화면 바로 아래 금속 띠(슬롯 송풍구 2 + 비상등, 양끝 슬롯) -> 우드 띠(가운데 인포 터치 띠) -> 공조 터치 띠\n\t\t-- 띠 윗면(my + 0.065)이 시선상 화면 아래 끝보다 아래여야 송풍구가 보임: top 2.75, 화면 아래 2.557 -> my 2.345\n\t\tlocal scrBottom = math.min(F.clusterBottom or top, scrY - ch / 2)\n\t\tlocal my = math.min(top - 0.405, scrBottom - 0.21)\n\t\tK:rbox(\"MetalBand\", Vector3.new(width - 0.12, 0.13, 0.05), 0.024, CFrame.new(0, my, face + 0.01), P.trim)\n\t\tfor _, s in { -1, 1 } do\n\t\t\tvent(K, P, \"CentreVent\", CFrame.new(cx + s * 0.34, my, face + 0.03), 0.5, 0.06)\n\t\t\tvent(K, P, \"SideVent\", CFrame.new(s * (half - 0.42), my, face + 0.03), 0.5, 0.06)\n\t\tend\n\t\tK:box(\"Hazard\", Vector3.new(0.08, 0.06, 0.04), CFrame.new(cx, my, face + 0.04), P.hazard)\n\t\tlocal wy = my - 0.115\n\t\tK:rbox(\"WoodBand\", Vector3.new(width - 0.2, 0.1, 0.05), 0.022, CFrame.new(0, wy, face + 0.006), P.wood)\n\t\tif amb then\n\t\t\tK:cyl(\"DashAmbient\", width - 0.3, 0.016, CFrame.new(0, my - 0.065, face + 0.03), amb)\n\t\tend\n\t\t-- 센터 페시아 몸체 (콘솔 윗면 ~ 우드 띠 윗면): 띠들이 0.08 들어간 하단 대시 면 앞에 떠 보이지 않게\n\t\tlocal fy0, fy1 = conTop, wy + 0.05\n\t\tif fy1 - fy0 > 0.05 then\n\t\t\tK:panel(\"StackBack\", 1.24, fy1 - fy0, 0.12, 0.06, CFrame.new(cx, (fy0 + fy1) / 2, face - 0.03), P.hard)\n\t\tend\n\t\t-- 인포테인먼트 터치 띠: 우드 띠 가운데 (양끝 볼륨 · 튠 노브)\n\t\tlocal iy = wy\n\t\tK:panel(\"InfoTouch\", 1.0, 0.08, 0.03, 0.035, CFrame.new(cx, iy, face + 0.04), P.gloss)\n\t\tfor _, s in { -1, 1 } do\n\t\t\tK:cyl(\"InfoKnob\", 0.05, 0.08, CFrame.new(cx + s * 0.42, iy, face + 0.07) * ROT_X_TO_Z, P.alloy)\n\t\tend\n\t\tfor i = -2, 2 do\n\t\t\tK:box(\"TouchIcon\", Vector3.new(0.04, 0.024, 0.004), CFrame.new(cx + i * 0.12, iy, face + 0.057), P.markWhite)\n\t\tend\n\t\t-- 공조 터치 띠 (높이 0.15): 인포 띠 아래 0.01 틈, 콘솔 윗면 위 -> y 2.105 (2.03..2.18)\n\t\tclimate(K, F, P, S, cx, math.max(conTop + 0.115, iy - 0.125), face + 0.05)\n\n-- Dash.luau body(), line 119:\n\tlocal gTop = mid - 0.1\n-- ->\n\tlocal gTop = if S.garnish == \"metal_wood\" then mid - 0.24 else mid - 0.1 -- 카니발: 내려간 우드 띠(아래 끝 2.18) 밑으로",
   "partsDelta": 6
  },
  {
   "rank": 2,
   "severity": "high",
   "area": "console",
   "observed": "carnival_1_driver.png and carnival_3_center.png: a red disc with a chrome ring sits directly under the nav screen, on top of the left centre vent. Cockpit.build places the start button at (W.X - side*(R+0.32), dashMidY+0.05, face+0.03) = (-0.31, 2.41, -2.27). The left CentreVent spans x -0.59..-0.09, y 2.42..2.48, so the two intersect.",
   "real": "The KA4 has no button in the vent band; only the hazard switch sits between the centre vents. ENGINE START/STOP is a dark round button with a satin ring, low on the driver side next to the wireless-charging tray and shift dial, and it is not red.",
   "fix": "Cockpit.luau Cockpit.build: skip the dash start button when S.shifter == \"dial\" (only carnival uses \"dial\"; G80 uses \"dial_wood\"). Console.luau dial branch: add StartRing d 0.13 and a black StartButton d 0.10 at (x + side*0.385, top + 0.012, pz) = (-0.385, 2.042, -2.00). This is beside the 0.6-wide wireless pad (pad x ±0.30, ring x -0.45..-0.32, inside the deck edge ±0.47). pz = zU + 0.26 with zU = max(z0 -2.60, face+0.04 = -2.26).",
   "code": "-- Cockpit.luau, Cockpit.build, line 356:\n\tif S.startButton then\n-- ->\n\tif S.startButton and S.shifter ~= \"dial\" then -- 카니발: 콘솔 충전 패드 옆 (Console)\n\n-- Console.luau, inside `else -- dial (카니발)`, right after `local gz = zU + L * 0.42`:\n\t\tif S.startButton then\n\t\t\t-- 시동 버튼: 무선 충전 패드(폭 0.6) 운전석 쪽 옆, 데크 끝(±0.47) 안\n\t\t\tlocal sb = CFrame.new(x + side * 0.385, top + 0.012, pz)\n\t\t\tK:cyl(\"StartRing\", 0.03, 0.13, sb * ROT_X_TO_Y, P.chrome)\n\t\t\tK:cyl(\"StartButton\", 0.04, 0.1, sb * CFrame.new(0, 0.012, 0) * ROT_X_TO_Y, P.hardDark)\n\t\tend",
   "partsDelta": 0
  },
  {
   "rank": 3,
   "severity": "high",
   "area": "wheel",
   "observed": "carnival_2_wheel.png and carnival_1_driver.png: the wheel centre reads as a round black dome, like a ball, built from the ellipsoid Airbag (0.6 x 0.38 x 0.18) in front of the ellipsoid HubShell (0.66 x 0.43 x 0.22).",
   "real": "The KA4 airbag cover is a wide, flat-faced, horizontally stretched rounded trapezoid: broad at the top, narrowing to a smaller chin at the bottom, with the flat chrome KIA wordmark.",
   "fix": "Styles.luau LIST.carnival.wheel: add hubShape = \"trap\". Cockpit.luau wheel(): build two K:panel pads instead of the ellipsoid. Airbag: 0.60 x 0.274 (hub.Y*0.72) x 0.18, r 0.11, at W*(0, hy+0.038 = 0.008, 0.06), spanning y -0.129..0.145. AirbagChin: 0.42 x 0.19 x 0.162, r 0.08, at W*(0, -0.106, 0.055), reaching down to -0.20 and recessed 0.014. The front face lands at z 0.15, so the KIA strokes (z 0.152) stay 0.006 proud. The button pads (inner edge x 0.27) still tuck under the pad's 0.30 half-width. Keep the HubShell ellipsoid as the shroud behind it.",
   "code": "-- Styles.luau, LIST.carnival.wheel { ... }: add the field\n\thubShape = \"trap\",\n\n-- Cockpit.luau, wheel(), replace lines 94-98:\n\t\tif kind == \"three\" then\n\t\t\tK:rbox(\"Airbag\", Vector3.new(hub.Z, hub.Y, hub.X), 0.1, W * CFrame.new(0, hy, 0.06) * ROT_X_TO_Z, P.wheelHub)\n\t\telseif ws.hubShape == \"trap\" then\n\t\t\t-- 카니발 KA4: 가로로 넓은 둥근 사다리꼴 패드 (위 폭 0.6 · 아래 턱 폭 0.42), 앞면 평평 z 0.15 (엠블럼 0.152 바로 뒤)\n\t\t\tK:panel(\"Airbag\", hub.X, hub.Y * 0.72, hub.Z, 0.11, W * CFrame.new(0, hy + hub.Y * 0.1, 0.06), P.wheelHub)\n\t\t\tK:panel(\"AirbagChin\", hub.X * 0.7, hub.Y * 0.5, hub.Z * 0.9, 0.08, W * CFrame.new(0, hy - hub.Y * 0.2, 0.055), P.wheelHub)\n\t\telse\n\t\t\tK:ell(\"Airbag\", hub, W * CFrame.new(0, hy, 0.06), P.wheelHub)\n\t\tend",
   "partsDelta": 11
  },
  {
   "rank": 4,
   "severity": "medium",
   "area": "wheel",
   "observed": "carnival_2_wheel.png: the lower spokes are two thin round rods (seg d 0.08) that run almost parallel and slightly diverge, from x ±0.075 at the hub to ±0.111 at the rim. They look like pipes, and the gloss trim is a second thin rod.",
   "real": "The KA4 wheel has two slim, flat lower spokes that leave the bottom corners of the airbag and converge into a narrow V at the 6 o'clock rim, with a gloss-black inlay.",
   "fix": "Styles.luau LIST.carnival.wheel: add lowerV = true. Cockpit.luau wheel(): add a branch ahead of the vee4/u4 one that builds a flat rbox blade per side. Each blade runs from (±0.13, hy - 0.42*hub.Y = -0.19), inside the new chin from issue 3, to the rim at -90°±4° on radius R-0.03 = 0.64, i.e. (±0.045, -0.638). Blade: length about 0.456, in-plane width 0.085, depth 0.05, r 0.022, z -0.01. A gloss inlay box ((len-0.1) x 0.032 x 0.012) sits on the face. The two blades meet at the rim with a gap of about 0.004, forming the V.",
   "code": "-- Styles.luau, LIST.carnival.wheel { ... }: add the field\n\tlowerV = true,\n\n-- Cockpit.luau, wheel(), replace lines 131-142 (`if kind == \"vee4\" or kind == \"u4\" then ... end`) with:\n\t\t\tif ws.lowerV then\n\t\t\t\t-- 카니발 KA4: 허브 턱 양끝(±0.13, -0.19)에서 6시 림(±4°, 반지름 0.64)으로 모이는 납작한 V 블레이드 + 하이글로시 인레이\n\t\t\t\tlocal a = Vector2.new(s * 0.13, hy - hub.Y * 0.42)\n\t\t\t\tlocal t = math.rad(-90 + s * 4)\n\t\t\t\tlocal b = Vector2.new(math.cos(t) * (R - 0.03), math.sin(t) * (R - 0.03))\n\t\t\t\tlocal d = b - a\n\t\t\t\tlocal bc = W * CFrame.new((a.X + b.X) / 2, (a.Y + b.Y) / 2, -0.01) * CFrame.Angles(0, 0, math.atan2(d.Y, d.X))\n\t\t\t\tK:rbox(\"LowerSpoke\", Vector3.new(d.Magnitude, 0.085, 0.05), 0.022, bc, P.hard)\n\t\t\t\tif ws.lowerTrim then\n\t\t\t\t\tK:box(\"LowerSpokeTrim\", Vector3.new(d.Magnitude - 0.1, 0.032, 0.012), bc * CFrame.new(0, 0, 0.027), if ws.lowerTrim == \"gloss\" then P.gloss else P.satin)\n\t\t\t\tend\n\t\t\telseif kind == \"vee4\" or kind == \"u4\" then\n\t\t\t\tlocal spread = if kind == \"vee4\" then 32 else 10\n\t\t\t\tlocal t = math.rad(-90 + s * spread)\n\t\t\t\tlocal a = (W * CFrame.new(s * 0.075, hy - hub.Y * 0.42, 0)).Position\n\t\t\t\tlocal b = (W * CFrame.new(math.cos(t) * (R - 0.03), math.sin(t) * (R - 0.03), -0.01)).Position\n\t\t\t\tK:seg(\"LowerSpoke\", a, b, 0.08, P.hard)\n\t\t\t\tif ws.lowerTrim then\n\t\t\t\t\tlocal a2 = (W * CFrame.new(s * 0.075, hy - hub.Y * 0.42, 0.04)).Position\n\t\t\t\t\tlocal b2 = (W * CFrame.new(math.cos(t) * (R - 0.08), math.sin(t) * (R - 0.08), 0.03)).Position\n\t\t\t\t\tK:seg(\"LowerSpokeTrim\", a2, b2, 0.032, if ws.lowerTrim == \"gloss\" then P.gloss else P.satin)\n\t\t\t\tend\n\t\t\tend",
   "partsDelta": 10
  },
  {
   "rank": 5,
   "severity": "medium",
   "area": "console",
   "observed": "carnival_1_driver.png and carnival_3_center.png: the console top is a wide matte grey-blue deck. A small gloss plate (0.8 x 0.62) surrounds only the dial and keys, and the two cupholders behind it are bright chrome rings (P.chrome, r 0.14) that read as glowing white ellipses on the bare deck.",
   "real": "On the KA4, a single large piano-black panel edged in satin trim holds the shift dial, the buttons around it and the two side-by-side cupholders. The cupholders are recessed dark openings in that panel, not bright chrome rings.",
   "fix": "Console.luau: give cupholders() an optional ringLook. In the dial branch, gz = zU + L*0.42 = -1.416 (zU -2.26, L = arm.z0 (-0.25) - zU = 2.01). Use one plate 0.84 x 1.30 centred at gz+0.32 (z -1.746..-0.446; the charge pad ends at -1.84 and the armrest starts at -0.25), plus a 0.88 x 1.34 satin rim 0.006 lower. Set the plate's reflectance to 0.05 so it stays black instead of mirror-grey in bright light (the same problem that was fixed on the Sonata deck). Raise the cupholders (x ±0.19, z gz+0.62 = -0.796) to top+0.002 so they sit just proud of the plate's top face (top+0.015), with P.hard rims.",
   "code": "-- Console.luau, replace cupholders() (lines 32-38):\nlocal function cupholders(K: any, P: any, x: number, y: number, z: number, along: boolean, ringLook: any?)\n\tfor _, s in { -1, 1 } do\n\t\tlocal c = if along then CFrame.new(x, y, z + s * 0.17) else CFrame.new(x + s * 0.19, y, z)\n\t\tK:cyl(\"CupholderRing\", 0.03, 0.31, c * ROT_X_TO_Y, ringLook or P.chrome)\n\t\tK:cyl(\"Cupholder\", 0.035, 0.27, c * CFrame.new(0, 0.005, 0) * ROT_X_TO_Y, P.duct)\n\tend\nend\n\n-- Console.luau, dial branch: replace\n\t\tK:slab(\"DialPlate\", w - 0.2, 0.62, 0.03, 0.14, CFrame.new(x, top, gz), P.gloss)\n-- ->\n\t\t-- KA4: 다이얼 · 버튼 · 컵홀더를 피아노 블랙 판 한 장 + 새틴 테두리가 감쌈 (z gz-0.33 .. gz+0.97 = -1.746 .. -0.446)\n\t\tlocal pc = CFrame.new(x, top, gz + 0.32)\n\t\tK:slab(\"DialPlateRim\", w - 0.12, 1.34, 0.02, 0.15, pc * CFrame.new(0, -0.006, 0), P.satin)\n\t\tK:slab(\"DialPlate\", w - 0.16, 1.3, 0.03, 0.14, pc, { c = P.gloss.c, m = P.gloss.m, r = 0.05 })\n-- and replace\n\t\tcupholders(K, P, x, top - 0.01, gz + 0.62, false)\n-- ->\n\t\tcupholders(K, P, x, top + 0.002, gz + 0.62, false, P.hard) -- 판 윗면(top + 0.015) 위로, 어두운 테두리",
   "partsDelta": 6
  },
  {
   "rank": 6,
   "severity": "low",
   "area": "wheel",
   "observed": "carnival_2_wheel.png: each spoke pad shows four blank grey rounded buttons with no graphics.",
   "real": "The KA4 switch pads are gloss black with backlit white icons: audio, voice, phone and volume on the left; cruise, distance and lane-following on the right.",
   "fix": "Styles.luau LIST.carnival.wheel: add icons = true. Cockpit.luau wheel(), in the ButtonPanel loop: add a 0.026 x 0.009 white icon on each of the four buttons per pad at pan*(bx, by, 0.022). The button face is at z 0.020, so the icon sits 0.004 proud. The icons are Neon (markWhite), so they also read as backlit at night.",
   "code": "-- Styles.luau, LIST.carnival.wheel { ... }: add the field\n\ticons = true,\n\n-- Cockpit.luau, wheel(), inside `for i = 0, 3 do` of the ButtonPanel branch, right after K:box(\"Button\", ...):\n\t\t\t\t\tif ws.icons then\n\t\t\t\t\t\tK:box(\"ButtonIcon\", Vector3.new(0.026, 0.009, 0.004), pan * CFrame.new(bx, by, 0.022), P.markWhite)\n\t\t\t\t\tend",
   "partsDelta": 8
  },
  {
   "rank": 7,
   "severity": "low",
   "area": "lights",
   "observed": "carnival_1_driver.png, carnival_3_center.png and carnival_5_night.png: a bright neon line (ConsoleAmbient, x ±0.52, y 1.94, 1.8 long) runs along each top edge of the console. In daylight it reads as a white glowing tube.",
   "real": "Pre-facelift KA4 mood lighting runs in the crash-pad garnish and the door-trim lines, not along the console flanks. Those are already built as DashAmbient and DoorAmbient.",
   "fix": "Styles.luau LIST.carnival: add consoleAmbient = false. Console.luau line 101: gate the console ambient on that field. Footwell lights and the dash and door lines are unchanged. This also removes 2 parts.",
   "code": "-- Styles.luau, LIST.carnival { ... }: add the field\n\tconsoleAmbient = false,\n\n-- Console.luau, line 101:\n\t\tif P.ambient then\n-- ->\n\t\tif P.ambient and S.consoleAmbient ~= false then",
   "partsDelta": -2
  },
  {
   "rank": 8,
   "severity": "low",
   "area": "headliner",
   "observed": "carnival_4_dash.png: the overhead console is the generic box with two map lamps, an SOS button and one roof switch. Nothing marks it as a minivan.",
   "real": "The KA4 overhead console carries the left and right power sliding-door buttons and the power tailgate button next to the map lamps, one of the cabin's signature details.",
   "fix": "Trim.luau Trim.build: oc = (0, roofY-0.06 = 4.57, lz0+0.45 = -0.53); the box is 0.78 x 0.12 x 0.5, bottom face at -0.06. Add the sliding-door L/R switches at oc*(±0.24, -0.065, -0.16) and the tailgate switch at oc*(0, -0.065, 0.04). These clear RoofSwitch (x ±0.07, z -0.15..-0.09), the MapLamps (x 0.12..0.32, z -0.04..0.08) and SOS (z 0.125..0.175). Gated by S.key.",
   "code": "-- Trim.luau, Trim.build, right after the RoofSwitch line (line 142):\n\t\tif F.style.key == \"carnival\" then\n\t\t\t-- 파워 슬라이딩 도어 좌 · 우 + 파워 테일게이트 (맵램프 앞 · 사이)\n\t\t\tfor _, s in { -1, 1 } do\n\t\t\t\tK:box(\"SlideDoorSwitch\", Vector3.new(0.1, 0.02, 0.07), oc * CFrame.new(s * 0.24, -0.065, -0.16), P.button)\n\t\t\tend\n\t\t\tK:box(\"TailgateSwitch\", Vector3.new(0.1, 0.02, 0.07), oc * CFrame.new(0, -0.065, 0.04), P.button)\n\t\tend",
   "partsDelta": 3
  }
 ]
}
```

## critique:solati

```json
{
 "car": "Hyundai Solati H350 119 ambulance (driver cab), style key \"solati\"",
 "summary": "The render gets the overall Solati layout right: a hooded twin-dial cluster with a centre LCD, an 8-inch screen with flanking vents in a silver frame, three climate knobs, a gear lever on the dash and a siren switch box. Several signature shapes still look wrong or cheap. The airbag is a black ball, the gear pod is a loose black brick, the trapezoid vents come out as chrome pills inside a half-buried frame, the A-pillar trims look like pipes, and the dash-top storage lids look like bricks sitting on the dash. Two structural gaps come from the fit: the door card stops 0.4 studs below the window, and the cab has no headliner, sun visors or dome lamps because the fit reads the patient-room Ceiling (behind the Partition).",
 "issues": [
  {
   "rank": 1,
   "severity": "high",
   "area": "wheel",
   "observed": "solati_2_wheel / solati_1_driver: the airbag is the generic ellipsoid (0.52x0.4x0.18), so the middle of the wheel reads as a black ball. The two u4 lower spokes are 0.08 rods spread only 10 degrees (they leave the hub at x=+-0.075 and meet the rim at +-0.12), so they merge into one post under the hub. (The white bar and white label on the hub are the emulator car-skin drawing the hidden WheelSpoke/WheelBadge, not Luau parts.)",
   "real": "Solati (Santa Fe DM-family wheel): a large rounded-trapezoid airbag pad (wider at the top) with a chrome H, two button spokes at 3 and 9 o'clock, and two flat lower spokes forming a narrow V that is clearly open between them.",
   "fix": "Styles.luau LIST.solati.wheel: add pad=\"trap\", lowerSpread=18, flatLower=true. Cockpit.luau wheel(): (a) new branch ws.pad==\"trap\" before the generic ellipsoid: an upper rbox pad (depth 0.1, height hub.Y*0.6=0.24, width 0.52) at W(0, hy+0.08, 0.05), a lower rbox (0.22 tall, 0.41 wide) at W(0, hy-0.08, 0.05), and a crown ellipsoid (0.44x0.34x0.09) at z 0.105, so the front sits at z 0.15 and the emblem at z 0.152 stays proud (same depth stack as vee4). The pad spans hy-0.19..hy+0.20. (b) Lower spokes: spread = ws.lowerSpread or 10, so the rim ends land at +-(cos72*0.68)=+-0.21, y -0.647. The hub ends move to x=+-0.1, y=-0.198. When ws.flatLower is set, reuse the vee4 flat rbox plate (width 0.1, thickness 0.06, r 0.028), without the satin strip. u4 cars without these fields (Tucson, Carnival) are unchanged.",
   "code": "-- Styles.luau LIST.solati\nOLD: wheel = { spokes = \"u4\", hub = Vector3.new(0.52, 0.4, 0.18), sideTrim = false, lowerTrim = nil, paddles = false },\nNEW: wheel = { spokes = \"u4\", hub = Vector3.new(0.52, 0.4, 0.18), sideTrim = false, lowerTrim = nil, paddles = false, pad = \"trap\", lowerSpread = 18, flatLower = true },\n\n-- Cockpit.luau wheel()  OLD:\n\t\telse\n\t\t\tK:ell(\"Airbag\", hub, W * CFrame.new(0, hy, 0.06), P.wheelHub)\n\t\tend\n-- NEW:\n\t\telseif ws.pad == \"trap\" then\n\t\t\t-- Solati (Santa Fe DM family): rounded trapezoid pad (top 0.52 / bottom 0.41 wide, 0.39 tall) + shallow crown (front z 0.15, emblem 0.152)\n\t\t\tK:rbox(\"Airbag\", Vector3.new(0.1, hub.Y * 0.6, hub.X), 0.11, W * CFrame.new(0, hy + hub.Y * 0.2, 0.05) * ROT_X_TO_Z, P.wheelHub)\n\t\t\tK:rbox(\"Airbag\", Vector3.new(0.1, hub.Y * 0.55, hub.X * 0.78), 0.1, W * CFrame.new(0, hy - hub.Y * 0.2, 0.05) * ROT_X_TO_Z, P.wheelHub)\n\t\t\tK:ell(\"AirbagCrown\", Vector3.new(hub.X - 0.08, hub.Y - 0.06, 0.09), W * CFrame.new(0, hy + 0.01, 0.105), P.wheelHub)\n\t\telse\n\t\t\tK:ell(\"Airbag\", hub, W * CFrame.new(0, hy, 0.06), P.wheelHub)\n\t\tend\n\n-- Cockpit.luau wheel() lower spokes  OLD:\n\t\t\t\tlocal spread = if kind == \"vee4\" then 32 else 10\n\t\t\t\tlocal t = math.rad(-90 + s * spread)\n\t\t\t\tlocal a = (W * CFrame.new(s * 0.075, hy - hub.Y * 0.42, 0)).Position\n\t\t\t\tlocal b = (W * CFrame.new(math.cos(t) * (R - 0.03), math.sin(t) * (R - 0.03), -0.01)).Position\n\t\t\t\tif kind == \"vee4\" then\n\t\t\t\t\t-- (zA / yv / spf / sl lines unchanged)\n\t\t\t\t\tK:rbox(\"LowerSpoke\", Vector3.new(sl + 0.02, 0.12, 0.06), 0.028, spf, P.hard)\n\t\t\t\t\tK:box(\"LowerSpokeTrim\", Vector3.new(sl - 0.12, 0.024, 0.01), spf * CFrame.new(0.03, 0, 0.032), P.satin)\n\t\t\t\telse\n-- NEW:\n\t\t\t\tlocal spread = if kind == \"vee4\" then 32 else (ws.lowerSpread or 10)\n\t\t\t\tlocal t = math.rad(-90 + s * spread)\n\t\t\t\tlocal a = (W * CFrame.new(s * (if ws.flatLower then 0.1 else 0.075), hy - hub.Y * 0.42, 0)).Position\n\t\t\t\tlocal b = (W * CFrame.new(math.cos(t) * (R - 0.03), math.sin(t) * (R - 0.03), -0.01)).Position\n\t\t\t\tif kind == \"vee4\" or ws.flatLower then\n\t\t\t\t\t-- (zA / yv / spf / sl lines unchanged)\n\t\t\t\t\tK:rbox(\"LowerSpoke\", Vector3.new(sl + 0.02, if kind == \"vee4\" then 0.12 else 0.1, 0.06), 0.028, spf, P.hard)\n\t\t\t\t\tif kind == \"vee4\" then\n\t\t\t\t\t\tK:box(\"LowerSpokeTrim\", Vector3.new(sl - 0.12, 0.024, 0.01), spf * CFrame.new(0.03, 0, 0.032), P.satin)\n\t\t\t\t\tend\n\t\t\t\telse",
   "partsDelta": 22
  },
  {
   "rank": 2,
   "severity": "high",
   "area": "shifter",
   "observed": "solati_3_center, solati_1_driver, solati_4_dash: GearPod is a dark rbox (0.30 wide x 0.44 tall x 0.40 deep) at (-0.68, 2.30, -6.31). It hangs below the centre stack, whose Fascia ends at mid-0.2=2.32, and sits against the light-grey lower dash (#5d6064), so it reads as a loose black brick with a stick. The boot is a small 0.2x0.12 flat ellipsoid and the knob is a plain ball.",
   "real": "The Solati's signature gear lever comes out of a rounded bulge at the lower-left of the centre stack, next to the driver's right knee. The bulge is the same charcoal plastic as the stack, so the stack and pod read as one piece. It has a leatherette boot and a knob with the 6-speed pattern printed on top.",
   "fix": "Dash.luau: (1) In the fascia branch, extend the Solati stack down to mid-0.6 = 1.92 (it was 2.32; dash bottom is 1.77), so the stack is one charcoal column that the pod and the siren box attach to. Porter keeps 0.5. (2) Replace the dash_pod block with an ellipsoid GearPod (0.5x0.56x0.64) centred at (px=-1.50+0.82=-0.68, py=mid-0.3=2.22, z=face=-6.45). It sticks out to z -6.13, and its right half overlaps the stack's left edge at x -0.72, which visually merges them. Then: a two-step rubber boot at a=(-0.68, 2.34, -6.18), a stick along dir=(0,0.7,0.71) for 0.34, a knob at (-0.68, 2.61, -5.90), and a pattern plate normal to dir. Knob clearance: its in-plane distance from the wheel centre is 0.83, more than R+0.075=0.785, and it sits 0.22 behind the wheel plane. The pod's right edge (-0.43) stays clear of the SirenBox (from -0.38).",
   "code": "-- Dash.luau fascia branch  OLD:\n\t\t\tlocal fy0, fy1 = mid - (if vk == \"trap_v\" then 0.2 else 0.5), top - 0.04\n-- NEW (Solati stack goes down to 1.92, so the gear pod and siren box sit in its lower bay):\n\t\t\tlocal fy0, fy1 = mid - (if vk == \"trap_v\" then 0.6 else 0.5), top - 0.04\n\n-- Dash.luau: replace the whole `if S.shifter == \"dash_pod\" then ... end` block with:\n\tif S.shifter == \"dash_pod\" then\n\t\t-- Solati: rounded pod rising from the lower-left of the stack (same charcoal, overlaps the stack's left edge x -0.72) + 2-step boot + lever angled 45 deg toward the driver + 6-speed pattern knob\n\t\tlocal px, py = F.wheel.c.X + toC * 0.82, mid - 0.3 -- (-0.68, 2.22)\n\t\tK:ell(\"GearPod\", Vector3.new(0.5, 0.56, 0.64), CFrame.new(px, py, face), P.hard) -- sticks out 0.32 from the dash face\n\t\tlocal dir = Vector3.new(0, 0.7, 0.71).Unit\n\t\tlocal a = Vector3.new(px, py + 0.12, face + 0.27) -- upper-front surface of the pod (slightly sunk in)\n\t\tK:ell(\"ShiftBoot\", Vector3.new(0.21, 0.16, 0.21), CFrame.new(a), P.rubber)\n\t\tK:ell(\"ShiftBootTop\", Vector3.new(0.13, 0.13, 0.13), CFrame.new(a + dir * 0.09), P.rubber)\n\t\tlocal b = a + dir * 0.34\n\t\tK:seg(\"ShiftStick\", a + dir * 0.1, b, 0.04, P.metalDark)\n\t\tlocal kc = b + dir * 0.05 -- (-0.68, 2.61, -5.90): outside the rim\n\t\tK:ball(\"ShiftKnob\", 0.15, CFrame.new(kc), P.hardDark)\n\t\tK:box(\"ShiftPattern\", Vector3.new(0.07, 0.006, 0.06), CFrame.fromMatrix(kc + dir * 0.074, Vector3.xAxis, dir), P.markWhite)\n\tend",
   "partsDelta": -3
  },
  {
   "rank": 3,
   "severity": "high",
   "area": "center screen",
   "observed": "solati_3_center: the FasciaFrame (satin) shares the screen's -10 degree tilt (ccf). Its top (about z -6.43) sinks behind the Fascia face (front at face+0.09 = -6.36), so only a silver chin under the screen shows. The TrapVents are generic Kit:vent stadium pills (0.14 wide, r = 0.38*min(w,h)) with thick chrome rims, tilted +-7 degrees.",
   "real": "Solati: an upright centre stack. One silver frame fully surrounds the 8-inch AVN and two tall vertical trapezoid vents. Each vent has a vertical edge next to the screen and an outer edge that slants outward going up.",
   "fix": "Cockpit.luau displays(), fascia branch: when S.vents == \"trap_v\", place the screen at face+0.13 with 0 degree tilt (Porter keeps face+0.1 and -10 degrees). FasciaFrame (unchanged call, ccf*(0,0,-0.035)) then sits at z -6.355; its front at -6.345 is 0.015 in front of the Fascia (-6.36), so the whole frame shows. Dash.luau trap_v: replace the pill vents with true trapezoids. Inner edge at xi = cx +- (cw/2+0.07) = +-0.49 (screen bezel ends at 0.45). Width 0.11 at the bottom and 0.17 at the top, so the outer edge reaches 0.66, inside the frame at 0.70. Height ch*0.92 = 0.33 around scrY = 2.92, vz = face+0.13. Parts: four satin rim segments plus four corner balls (d 0.035); a duct made of a box (0.11 wide) plus a WedgePart whose right-angle corner is at (xi+s*wb, y1), built with fromMatrix(X=(0,0,-s), Y=(0,-1,0)) so the hypotenuse becomes the slanted outer edge; five horizontal slats whose length follows the edge; and a tab. Same part count as Kit:vent (16 each).",
   "code": "-- Cockpit.luau displays()  OLD:\n\telse -- fascia\n\t\tccf = CFrame.new(cx, math.min(F.dashMidY + 0.42, top - ch / 2 - 0.25), face + 0.1) * CFrame.Angles(math.rad(-10), 0, 0)\n\tend\n-- NEW:\n\telse -- fascia\n\t\t-- Solati: upright stack (tilt 0, face + 0.13) so the whole silver frame behind the screen shows in front of the stack face. Porter keeps 10 deg\n\t\tlocal up = S.vents == \"trap_v\"\n\t\tccf = CFrame.new(cx, math.min(F.dashMidY + 0.42, top - ch / 2 - 0.25), face + (if up then 0.13 else 0.1)) * CFrame.Angles(math.rad(if up then 0 else -10), 0, 0)\n\tend\n\n-- Dash.luau trap_v  OLD:\n\t\t\t\tfor _, s in { -1, 1 } do\n\t\t\t\t\tvent(K, P, \"TrapVent\", CFrame.new(cx + s * (cw / 2 + 0.13), scrY, face + 0.1) * CFrame.Angles(0, 0, math.rad(s * 7)), 0.14, ch * 0.9, true)\n\t\t\t\tend\n-- NEW (keep the FasciaFrame line above it):\n\t\t\t\t-- vertical trapezoid vents: screen-side edge vertical, outer edge widens upward (bottom 0.11 -> top 0.17, height 0.33)\n\t\t\t\tlocal vh, wb, wt, vz = ch * 0.92, 0.11, 0.17, face + 0.13\n\t\t\t\tlocal y0, y1 = scrY - vh / 2, scrY + vh / 2\n\t\t\t\tfor _, s in { -1, 1 } do\n\t\t\t\t\tlocal xi = cx + s * (cw / 2 + 0.07)\n\t\t\t\t\tlocal c = { Vector3.new(xi, y0, vz + 0.02), Vector3.new(xi, y1, vz + 0.02), Vector3.new(xi + s * wt, y1, vz + 0.02), Vector3.new(xi + s * wb, y0, vz + 0.02) }\n\t\t\t\t\tfor i = 1, 4 do\n\t\t\t\t\t\tK:seg(\"TrapVentRim\", c[i], c[i % 4 + 1], 0.035, P.satin)\n\t\t\t\t\t\tK:ball(\"TrapVentRim\", 0.035, CFrame.new(c[i]), P.satin)\n\t\t\t\t\tend\n\t\t\t\t\tK:box(\"TrapVentDuct\", Vector3.new(wb, vh, 0.05), CFrame.new(xi + s * wb / 2, scrY, vz), P.duct)\n\t\t\t\t\t-- wedge: right-angle corner = (xi + s*wb, y1), hypotenuse = the slanted outer edge\n\t\t\t\t\tK:wedge(\"TrapVentDuct\", Vector3.new(0.05, vh, wt - wb), CFrame.fromMatrix(Vector3.new(xi + s * (wb + wt) / 2, scrY, vz), Vector3.new(0, 0, -s), Vector3.new(0, -1, 0)), P.duct)\n\t\t\t\t\tfor k = 1, 5 do\n\t\t\t\t\t\tlocal L = wb + (wt - wb) * (k - 0.5) / 5 - 0.035\n\t\t\t\t\t\tK:cyl(\"TrapVentSlat\", L, 0.022, CFrame.new(xi + s * (0.0175 + L / 2), y0 + vh * (k - 0.5) / 5, vz + 0.03), P.hard)\n\t\t\t\t\tend\n\t\t\t\t\tK:box(\"TrapVentTab\", Vector3.new(0.03, 0.05, 0.03), CFrame.new(xi + s * 0.07, scrY, vz + 0.05), P.satin)\n\t\t\t\tend",
   "partsDelta": 0
  },
  {
   "rank": 4,
   "severity": "high",
   "area": "other",
   "observed": "solati_1_driver (top-left and top-right diagonals) and solati_4_dash (top centre): APillarTrim is a d=0.15 grey cylinder from (+-2.95, 3.14, -7.70) to (+-2.81, 6.02, -5.10), inset 0.12 behind the glass. In this huge van windscreen it reads as scaffolding pipes framing the view.",
   "real": "The Solati has wide, flat moulded grey plastic A-pillar trims, about 10 cm wide, sitting flush against the windscreen edge.",
   "fix": "Dash.luau body(), A-pillar loop, gated by S.key == \"solati\": use a flat zbox (width 0.36, thickness 0.1, long edges r 0.05) along the pillar instead of seg. Centre line runs from x=+-(wsHalf-0.16)=2.89 at ws.Y 3.14 to +-(wsHalf-0.30)=2.75 at 6.02. Offset -nOut*0.1 with nOut=(0,0.670,-0.742) puts the back face 0.05 behind the glass centre plane (the glass inner face is at 0.04), and the width spans x 2.71..3.07, inside the cab-glass inner face at 3.10. Frame: Z = pillar direction, Y = glass normal orthogonalised, X = Y x Z (about +X). The top end hides inside CabHeader and the bottom inside the dash, as now.",
   "code": "-- Dash.luau body()  OLD:\n\tfor _, s in { -1, 1 } do\n\t\tlocal a = Vector3.new(s * (wsHalf - 0.1), ws.Y, ws.Z) - nOut * 0.12\n\t\tlocal b = Vector3.new(s * (wsHalf - 0.24), hiW.Y, hiW.Z) - nOut * 0.12\n\t\tK:seg(\"APillarTrim\", a, b, 0.15, P.pillar)\n\tend\n-- NEW:\n\tfor _, s in { -1, 1 } do\n\t\tif S.key == \"solati\" then\n\t\t\t-- van: wide flat moulded pillar trim instead of a rod (width 0.36, thickness 0.1, long edges rounded), back face almost touching the glass inner face\n\t\t\tlocal a = Vector3.new(s * (wsHalf - 0.16), ws.Y, ws.Z) - nOut * 0.1\n\t\t\tlocal b = Vector3.new(s * (wsHalf - 0.3), hiW.Y, hiW.Z) - nOut * 0.1\n\t\t\tlocal zA = (b - a).Unit\n\t\t\tlocal yA = (nOut - zA * nOut:Dot(zA)).Unit\n\t\t\tK:zbox(\"APillarTrim\", Vector3.new(0.36, 0.1, (b - a).Magnitude), 0.05, CFrame.fromMatrix((a + b) / 2, yA:Cross(zA), yA), P.pillar)\n\t\telse\n\t\t\tlocal a = Vector3.new(s * (wsHalf - 0.1), ws.Y, ws.Z) - nOut * 0.12\n\t\t\tlocal b = Vector3.new(s * (wsHalf - 0.24), hiW.Y, hiW.Z) - nOut * 0.12\n\t\t\tK:seg(\"APillarTrim\", a, b, 0.15, P.pillar)\n\t\tend\n\tend",
   "partsDelta": 10
  },
  {
   "rank": 5,
   "severity": "medium",
   "area": "dash",
   "observed": "solati_1_driver and solati_3_center (at the windscreen base): each DashBin is a 0.9x0.12x0.5 rbox standing 0.12 above the dash top at x=+-0.7. They look like two loose black bricks, and the driver-side one (x -1.15..-0.25) runs into the cluster back and cheek (x up to -0.78/-0.87, z -6.73..-6.27). The DashTray is a sharp black square.",
   "real": "The Solati dash top has lidded storage bins whose lids sit almost flush with the big flat dash shelf (rounded-rectangle lid, dark shut-line, push latch), plus an open centre tray with a 12V outlet.",
   "fix": "Dash.luau Dash.build, ex.bins block: lids are slabs that rise only 0.022 above top (3.35), on the flat deck at z face-0.42 = -6.87 (+-0.23, which stays behind the edge roll that starts at face-rr = -6.58). Each lid is a dark gap slab (0.72x0.46, r 0.09) plus a lid slab (0.68x0.42, r 0.08, P.soft) plus a round satin latch. Positions: driver-side bin at cx-toC*0.38 (x -0.74..-0.02, clear of the cluster back at -0.87 and cheek at -0.78), tray slab 0.3 wide at cx+toC*0.19 (0.04..0.34), passenger bin at cx+toC*0.76 (0.40..1.12).",
   "code": "-- Dash.luau: replace the `if ex.bins then ... end` block\n\tif ex.bins then\n\t\t-- Solati: two rounded lids standing only 0.02 above the dash top (3.35; flat where z < face-0.13) + dark shut-line + push latch, open tray between them\n\t\tfor _, bx in { cx - toC * 0.38, cx + toC * 0.76 } do\n\t\t\tlocal bc = CFrame.new(bx, top, face - 0.42)\n\t\t\tK:slab(\"BinGap\", 0.72, 0.46, 0.012, 0.09, bc * CFrame.new(0, 0.004, 0), P.hardDark)\n\t\t\tK:slab(\"DashBinLid\", 0.68, 0.42, 0.02, 0.08, bc * CFrame.new(0, 0.012, 0), P.soft)\n\t\t\tK:cyl(\"BinLatch\", 0.02, 0.07, bc * CFrame.new(0, 0.024, 0.15) * CFrame.Angles(0, 0, math.pi / 2), P.satin)\n\t\tend\n\t\tK:slab(\"DashTray\", 0.3, 0.42, 0.02, 0.06, CFrame.new(cx + toC * 0.19, top + 0.002, face - 0.42), P.hardDark)\n\tend",
   "partsDelta": 15
  },
  {
   "rank": 6,
   "severity": "medium",
   "area": "doors",
   "observed": "solati_1_driver (left edge) and solati_4_dash (driver door): the model has no DoorTrim (fit_dims trimY=nil..nil), so doorCard uses y1 = floor+2.2 = 2.72. The side glass (CabGlass) only starts at 3.125, so a 0.36-tall band of the bare CabDoor body panel (top 3.175) shows above the rounded sill. The door card looks low and stuck on.",
   "real": "The Solati door card is grey hard plastic that runs right up to the high window line, with a wide sill near dash-top height, a pull grip, a switch armrest, a deep lower bin and a round speaker.",
   "fix": "Fit.luau Fit.run, section 2, inside the existing `if #trims == 0 then` Partition block: read the body part CabDoor (size 0.42x1.55x4.20 at y 2.40, top 3.175) and set F.trimY0 = F.floorY (0.52) and F.trimY1 = 3.175-0.04 = 3.135. doorCard then gives DoorLower 0.52..1.62, DoorSoft about 1.63..2.09, DoorUpper 2.09..3.135 and DoorSill at 3.115 (x -3.04..-2.90, clear of the glass inner face at -3.10). The armrest stays at 1.98. Only cars without DoorTrim are affected (only the Solati in fit_dims).",
   "code": "-- Fit.luau  OLD:\n\tif #trims == 0 then\n\t\tlocal pt = first({ \"Partition\" })\n\t\tif pt then\n\t\t\tdoorZ1 = math.min(doorZ1, U:PointToObjectSpace(pt.Position).Z - pt.Size.Z / 2 - 0.05)\n\t\tend\n\tend\n-- NEW:\n\tif #trims == 0 then\n\t\tlocal pt = first({ \"Partition\" })\n\t\tif pt then\n\t\t\tdoorZ1 = math.min(doorZ1, U:PointToObjectSpace(pt.Position).Z - pt.Size.Z / 2 - 0.05)\n\t\tend\n\t\t-- van without door trim parts (Solati): cover the door inside up to the top of the body CabDoor (= bottom of the side glass, 3.125)\n\t\tlocal cd = first({ \"CabDoor\" }, body)\n\t\tif cd then\n\t\t\tlocal lc, sz = localBox(U, cd)\n\t\t\tF.trimY0, F.trimY1 = F.floorY, lc.Position.Y + sz.Y / 2 - 0.04 -- 0.52 .. 3.135\n\t\tend\n\tend",
   "partsDelta": 0
  },
  {
   "rank": 7,
   "severity": "medium",
   "area": "headliner",
   "observed": "Not in frame in the four shots, but follows from fit_dims: liner=-3.40..9.70 and roof=6.06 come from the patient-room Ceiling behind the Partition (z -3.48). Trim therefore builds the Headliner, OverheadConsole, MapLamps, SOS, DomeLamp and grab handles inside the patient room, and the Lights dome/map lamps light the wrong room. SunVisors at roofY-0.06 = 6.00, z -4.68 sit entirely inside the body CabHeader (y 5.825..6.195), so they are invisible. The cab ceiling is the bare white CabHeader.",
   "real": "The Solati cab has a fabric headliner, two sun visors, a centre mirror, a front map/dome lamp console and grab handles. The ambulance converter often adds an overhead console.",
   "fix": "Fit.luau, end of Fit.run (just before `return F, nil`): when F.linerZ0 > F.doorZ1-0.2 (-3.40 > -3.80; no other car qualifies: Porter has -7.25), take the cab ceiling from the body part CabHeader (6.60x0.37x1.85 at y 6.01, z -4.43), so roofY = 5.825. Set linerZ0 = max(the z where the windscreen crosses roofY, header front) = -7.70+(5.825-3.14)*(2.60/2.88) = -5.28, and linerZ1 = doorZ1 = -3.60. Trim then puts the headliner at 5.815..5.875 (llen 1.68), the overhead console at (0, 5.765, -4.83), the dome lamp at z -4.27, visors at y 5.765 (visible), the mirror at (0, 5.525, -4.75) and the belt anchor at 5.275. No new parts; existing ones move into the cab.",
   "code": "-- Fit.luau: insert just before `return F, nil` at the end of Fit.run\n\t-- ambulance: no Headliner, only Ceiling (patient-room ceiling behind the partition, z -3.40..9.70) -> driver-cab ceiling = underside of the body CabHeader\n\tif F.linerZ0 and F.linerZ0 > F.doorZ1 - 0.2 then\n\t\tlocal hd = first({ \"CabHeader\" }, body)\n\t\tif hd then\n\t\t\tlocal lc, sz = localBox(U, hd)\n\t\t\tlocal wl: Vector3, wh: Vector3 = F.wsLow, F.wsHigh\n\t\t\tF.roofY = lc.Position.Y - sz.Y / 2 -- 5.825\n\t\t\tlocal zWs = wl.Z + (F.roofY - wl.Y) * (wh.Z - wl.Z) / math.max(0.01, wh.Y - wl.Y) -- z where the windshield meets ceiling height (-5.28)\n\t\t\tF.linerZ0, F.linerZ1 = math.max(zWs, lc.Position.Z - sz.Z / 2), F.doorZ1 -- -5.28 .. -3.60\n\t\tend\n\tend",
   "partsDelta": 0
  },
  {
   "rank": 8,
   "severity": "medium",
   "area": "dash",
   "observed": "solati_3_center and solati_4_dash: the passenger-side lower dash shows a 1.25x0.46 glovebox outline built from four sharp 0.012 boxes plus a satin bar, so it reads like a kitchen drawer. The upper passenger dash face (y 2.64..3.22, x 0.7..2.3) is one flat black wall.",
   "real": "The Solati passenger side has a large lower glovebox (cooled on some trims) with a rounded-corner lid and a recessed pull, plus an upper lidded glovebox in the upper dash face, part of the van's 23 storage spaces.",
   "fix": "Dash.luau body(), gated by S.key == \"solati\", replacing the GloveGap loop and GloveHandle. Uses gx=1.645, gw=1.25, gy=2.19, gh=0.46. Lower lid: a hardDark gap panel (r 0.07) at face-0.075 (the DashLower face is at face-0.08), a P.lower lid panel 0.03 smaller at +0.005, a dark recess box, and a satin pull 0.1 below the top edge. Upper glovebox on the DashUpper face (z face) between uy0 = mid+0.18 = 2.70 and uy1 = top-rr-0.06 = 3.16: gap panel 1.15 wide (x 1.07..2.22, clear of the SideVent from 2.355) at face+0.004, a P.soft lid, and a satin latch. Other cars keep the old code.",
   "code": "-- Dash.luau body()  OLD:\n\tfor _, e in { { 0, gh / 2, gw, 0.012 }, { 0, -gh / 2, gw, 0.012 }, { gw / 2, 0, 0.012, gh }, { -gw / 2, 0, 0.012, gh } } do\n\t\tK:box(\"GloveGap\", Vector3.new(e[3], e[4], 0.01), CFrame.new(gx + e[1], gy + e[2], face - 0.075), P.hardDark)\n\tend\n\tK:box(\"GloveHandle\", Vector3.new(0.3, 0.035, 0.03), CFrame.new(gx, gy + gh / 2 - 0.08, face - 0.07), P.satin)\n-- NEW:\n\tif S.key == \"solati\" then\n\t\t-- Solati: big lower glovebox = rounded shut-line (r 0.07) + lid + pull recess, plus a lidded upper glovebox on the upper dash face (2.70..3.16)\n\t\tlocal gc = CFrame.new(gx, gy, face - 0.075)\n\t\tK:panel(\"GloveGap\", gw, gh, 0.01, 0.07, gc, P.hardDark)\n\t\tK:panel(\"GloveLid\", gw - 0.03, gh - 0.03, 0.01, 0.06, gc * CFrame.new(0, 0, 0.005), P.lower)\n\t\tK:box(\"GloveRecess\", Vector3.new(0.34, 0.07, 0.01), gc * CFrame.new(0, gh / 2 - 0.09, 0.009), P.duct)\n\t\tK:box(\"GloveHandle\", Vector3.new(0.28, 0.03, 0.02), gc * CFrame.new(0, gh / 2 - 0.1, 0.016), P.satin)\n\t\tlocal uy0, uy1 = mid + 0.18, top - rr - 0.06\n\t\tlocal uc = CFrame.new(gx, (uy0 + uy1) / 2, face + 0.004)\n\t\tK:panel(\"UpperGloveGap\", gw - 0.1, uy1 - uy0, 0.01, 0.07, uc, P.hardDark)\n\t\tK:panel(\"UpperGloveLid\", gw - 0.13, uy1 - uy0 - 0.03, 0.01, 0.06, uc * CFrame.new(0, 0, 0.004), P.soft)\n\t\tK:box(\"UpperGloveLatch\", Vector3.new(0.16, 0.035, 0.02), uc * CFrame.new(0, (uy1 - uy0) / 2 - 0.07, 0.011), P.satin)\n\telse\n\t\tfor _, e in { { 0, gh / 2, gw, 0.012 }, { 0, -gh / 2, gw, 0.012 }, { gw / 2, 0, 0.012, gh }, { -gw / 2, 0, 0.012, gh } } do\n\t\t\tK:box(\"GloveGap\", Vector3.new(e[3], e[4], 0.01), CFrame.new(gx + e[1], gy + e[2], face - 0.075), P.hardDark)\n\t\tend\n\t\tK:box(\"GloveHandle\", Vector3.new(0.3, 0.035, 0.03), CFrame.new(gx, gy + gh / 2 - 0.08, face - 0.07), P.satin)\n\tend",
   "partsDelta": 22
  },
  {
   "rank": 9,
   "severity": "low",
   "area": "console",
   "observed": "solati_3_center: right of the SirenBox, a Radio rbox (0.4 wide at x 0.48..0.88) overlaps the box's right end (0.54) and pokes 0.12 out of the dash. With the stack extended to x +-0.72 (issue 2) it would also straddle the stack edge. Its tiny LCD face can't be read, and the RadioMic is a loose 0.07 block, so the area looks cluttered.",
   "real": "Korean 119 Solati conversions use a single siren/beacon control head: rows of rocker switches with indicator LEDs plus a rotary siren-mode selector. The radio handset hangs on a clip next to the stack.",
   "fix": "Dash.luau ex.siren block: drop Radio and RadioFace (7 parts). Widen the SirenBox to 1.1 and centre it at cx+toC*0.17, so it spans x -0.38..0.72 (left edge clear of the gear pod at -0.43, right edge at the stack edge). Move the six switch columns to local x -0.47..0.23 and add a rotary mode dial (satin ring, black knob, white mark) at local x 0.40. Keep the RadioMic at x 0.95, clear of the glovebox (from 1.02).",
   "code": "-- Dash.luau: replace the `if ex.siren then ... end` block\n\tif ex.siren then\n\t\t-- 119: siren/beacon control head (2 rows of switches + LEDs + siren-mode dial on the right), mounted in the stack's lower bay. Handset to the right of the stack\n\t\tlocal sc = CFrame.new(cx + toC * 0.17, mid - 0.42, face + 0.14) * CFrame.Angles(math.rad(-12), 0, 0)\n\t\tK:rbox(\"SirenBox\", Vector3.new(1.1, 0.28, 0.2), 0.05, sc, P.hardDark)\n\t\tlocal cols = { P.hazard, P.lampBlue, P.lampAmber, P.button, P.button, P.button }\n\t\tfor r = 0, 1 do\n\t\t\tfor i = 1, 6 do\n\t\t\t\tlocal x = -0.47 + (i - 1) * 0.14\n\t\t\t\tK:box(\"SirenSwitch\", Vector3.new(0.09, 0.07, 0.04), sc * CFrame.new(x, 0.05 - r * 0.1, 0.11), if r == 0 then cols[i] else P.button)\n\t\t\t\tif r == 0 then\n\t\t\t\t\tK:box(\"SirenLed\", Vector3.new(0.025, 0.012, 0.01), sc * CFrame.new(x, 0.105, 0.105), if i <= 3 then P.ledRed else P.ledGreen)\n\t\t\t\tend\n\t\t\tend\n\t\tend\n\t\tK:cyl(\"SirenDialRing\", 0.02, 0.2, sc * CFrame.new(0.4, 0, 0.105) * ROT_X_TO_Z, P.satin)\n\t\tK:cyl(\"SirenDial\", 0.06, 0.16, sc * CFrame.new(0.4, 0, 0.13) * ROT_X_TO_Z, P.hardDark)\n\t\tK:box(\"SirenDialMark\", Vector3.new(0.012, 0.05, 0.006), sc * CFrame.new(0.4, 0.04, 0.162), P.markWhite)\n\t\tK:rbox(\"RadioMic\", Vector3.new(0.07, 0.22, 0.12), 0.03, CFrame.new(cx + toC * 0.95, mid - 0.38, face + 0.16), P.hardDark)\n\tend",
   "partsDelta": -4
  },
  {
   "rank": 10,
   "severity": "low",
   "area": "other",
   "observed": "Not in frame in the four shots. The original white Partition (5.96x5.65x0.15 at z -3.48, cab face at -3.555) behind the seat backs is a blank wall.",
   "real": "119 Solati ambulance (Autech/Sungwoo conversions): a partition behind the cab seats with a small sliding window in the middle into the patient compartment. This is listed as a signature feature.",
   "fix": "Trim.luau Trim.build, end, gated by F.style.key == \"solati\": at z = F.doorZ1+0.03 = -3.57 (doorZ1 = partition face - 0.05) and y = F.roofY-1.18 (4.645 once issue 7 is applied; above the headrest tops at about 4.0 and below the 5.825 ceiling), add a grey frame panel 1.3x0.72 (r 0.12, back face 0.005 into the partition), a dark glass panel 1.18x0.6 on its cab side, a centre mullion and a satin latch.",
   "code": "-- Trim.luau: add just before `return {}` at the end of Trim.build\n\tif F.style.key == \"solati\" then\n\t\t-- 119 partition (cab-side face = doorZ1 + 0.05 = -3.555): small sliding window in the middle (grey frame + dark glass + centre mullion + latch)\n\t\tlocal wc = CFrame.new(0, F.roofY - 1.18, F.doorZ1 + 0.03)\n\t\tK:panel(\"PartitionWindowFrame\", 1.3, 0.72, 0.04, 0.12, wc, P.hard)\n\t\tK:panel(\"PartitionWindowGlass\", 1.18, 0.6, 0.01, 0.08, wc * CFrame.new(0, 0, -0.025), P.screen)\n\t\tK:box(\"PartitionWindowMullion\", Vector3.new(0.04, 0.6, 0.02), wc * CFrame.new(0.05, 0, -0.035), P.hard)\n\t\tK:box(\"PartitionWindowLatch\", Vector3.new(0.05, 0.09, 0.025), wc * CFrame.new(0.12, 0, -0.04), P.satin)\n\tend",
   "partsDelta": 14
  },
  {
   "rank": 11,
   "severity": "low",
   "area": "cluster",
   "observed": "solati_1_driver and solati_2_wheel: the centre cluster LCD shows \"P\", but the cab has a 6-speed manual lever with a ball knob, so the display contradicts the lever.",
   "real": "The Solati 6MT cluster LCD shows the selected/recommended gear (N, 1 to 6, R) with an eco shift-up indicator. It never shows P.",
   "fix": "init.client.luau live loop (line 678): for style shifter \"manual\" or \"dash_pod\" (Porter and Solati, both manual), show \"N\" when parked, \"R\" when reversing, and otherwise a gear from 1 to 6 picked by speed (one gear per 20 km/h). The 7-seg map already has N, R and 1-6. Automatic styles are unchanged.",
   "code": "-- init.client.luau  OLD:\n\t\tlocal gear = if running then (if kmh < -0.8 then \"R\" else \"D\") else \"P\"\n-- NEW:\n\t\tlocal sh = cab.fit.style.shifter\n\t\tlocal gear = if sh == \"manual\" or sh == \"dash_pod\"\n\t\t\tthen (if not running then \"N\" elseif kmh < -0.8 then \"R\" else tostring(math.clamp(1 + math.floor(math.abs(kmh) / 20), 1, 6)))\n\t\t\telse (if running then (if kmh < -0.8 then \"R\" else \"D\") else \"P\")",
   "partsDelta": 0
  }
 ]
}
```

## critique:porter

```json
{
 "car": "Hyundai Porter II (1-ton cab-over truck, 2020s), style key \"porter\"",
 "summary": "In the given styles1 shots the studio skin's interior shell (already fixed) hides almost the whole dash, so I used the styles3 re-render of the current code (shots/styles3/porter_*.png). It shows the hooded twin-dial cluster, the bus-style 2-spoke wheel, the two-tone dash and the fascia stack (vents, screen, 3 dials) in the right places, but the cab still looks like a sedan cabin inside a truck. The biggest gaps are: no cab-over seat box (sedan rails and power-seat switches instead), a flat, featureless passenger dash with no open shelf and a tray drawn flat, a manual lever with a glowing white top and no boot, an open footwell under the dash, alloy sport pedals that overlap a footrest, and passenger-car parts (overhead SOS console, vanity covers, chrome vent rims).",
 "issues": [
  {
   "rank": 1,
   "severity": "high",
   "area": "seats",
   "observed": "styles3/porter_3_center.png and porter_4_dash.png: the driver seat and both bench halves stand on separate sedan SeatRail and SeatBase pods, with satin power-seat switch shields. Ground and footwell show between and under them, so nothing says cab-over. styles1/porter_4_dash.png shows the same rail-mounted cushions.",
   "real": "In the Porter II, the driver seat and the 2-person bench sit directly on one full-width plastic seat box with the engine underneath. It runs door to door, from the cushion front to the cab back wall, with a flat front face at knee height. The driver seat has a manual recline lever and no power-seat switches.",
   "fix": "Seats.luau, Seats.build, porter only (S.key): add an rbox 'SeatRiser'. Width = 2*halfIn-0.12 = 4.78. Height runs from floorY 0.85 to cushTop-0.26 = 1.75-0.26 = 1.49 (h 0.64). Z runs from cushion front edge+0.08 (-4.70-0.775+0.08 = -5.395) to doorZ1-0.02 = -3.67. Use r 0.09 and P.hard, plus a rubber kick strip on the face at y 0.92. In frontSeat, for porter skip SeatRail, SeatBase, SeatShield and SeatSwitch, and give the driver a manual 'ReclineLever' at x = -1.30-(0.80+0.03) = -2.13, y 1.62..1.68, z zR-0.5..zR-0.22 = -4.425..-4.145. The CushionPan bottom (1.49) sits flush on the riser top, and its front roll overhangs the riser face by 0.11. Checked with an offline build of the place's Porter fixture (car_14415): no errors. All 12 fixes are combined in /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/porterrev/porter.diff, which applies cleanly to HEAD bd78b5d (offline part count 689 -> 694).",
   "code": "Seats.luau frontSeat. OLD:\n\t-- 레일 + 받침\n\tfor _, sx in { -0.32, 0.32 } do\n\t\tK:box(\"SeatRail\", Vector3.new(0.07, 0.06, cs.Z + 0.4), CFrame.new(x + sx * w, floor + 0.04, s.z), P.metalDark)\n\tend\n\tlocal baseH = math.max(0.1, cushTop - 0.3 - floor)\n\tK:zbox(\"SeatBase\", Vector3.new(w * 0.78, baseH, cs.Z * 0.8), math.min(0.08, baseH / 2 - 0.01), CFrame.new(x, floor + baseH / 2 + 0.05, s.z + 0.05), P.hardDark)\n\t-- 옆 덮개 + 파워시트 스위치 (바깥쪽)\n\tlocal out = if x < 0 then -1 else 1\n\tif not s.inner then\nNEW:\n\t-- 레일 + 받침 (포터: Seats.build 의 전폭 엔진 덮개 상자 위에 바로 앉음 -> 레일 · 받침 · 파워시트 없음)\n\tlocal riser = F.style.key == \"porter\"\n\tif not riser then\n\t\tfor _, sx in { -0.32, 0.32 } do\n\t\t\tK:box(\"SeatRail\", Vector3.new(0.07, 0.06, cs.Z + 0.4), CFrame.new(x + sx * w, floor + 0.04, s.z), P.metalDark)\n\t\tend\n\t\tlocal baseH = math.max(0.1, cushTop - 0.3 - floor)\n\t\tK:zbox(\"SeatBase\", Vector3.new(w * 0.78, baseH, cs.Z * 0.8), math.min(0.08, baseH / 2 - 0.01), CFrame.new(x, floor + baseH / 2 + 0.05, s.z + 0.05), P.hardDark)\n\tend\n\t-- 옆 덮개 + 파워시트 스위치 (바깥쪽) / 포터 운전석: 수동 등받이 레버\n\tlocal out = if x < 0 then -1 else 1\n\tif riser then\n\t\tif not s.inner and (x < 0) == (F.side < 0) then\n\t\t\tlocal lx = x + out * (w / 2 + 0.03)\n\t\t\tK:capsule(\"ReclineLever\", Vector3.new(lx, cushTop - 0.13, zR - 0.5), Vector3.new(lx, cushTop - 0.07, zR - 0.22), 0.05, P.hardDark)\n\t\tend\n\telseif not s.inner then\n\nSeats.luau Seats.build. OLD:\nfunction Seats.build(K: any, F: any, P: any)\n\tfor _, s in F.front do\nNEW:\nfunction Seats.build(K: any, F: any, P: any)\n\tif F.style.key == \"porter\" and F.front[1] then\n\t\t-- 포터 캡오버: 좌석 밑 엔진을 덮은 전폭 받침 상자 (앞 · 뒤 모서리 둥글게) + 아래 고무 발판 띠\n\t\tlocal s0 = F.front[1]\n\t\tlocal cs: Vector3 = s0.cushSize\n\t\tlocal top = s0.cush.Y + cs.Y / 2 - 0.26\n\t\tlocal zf = s0.z - cs.Z / 2 + 0.08\n\t\tlocal zb = (F.doorZ1 :: number) - 0.02\n\t\tlocal h = top - F.floorY\n\t\tlocal w = F.halfIn * 2 - 0.12\n\t\tK:rbox(\"SeatRiser\", Vector3.new(w, h, zb - zf), 0.09, CFrame.new(0, F.floorY + h / 2, (zf + zb) / 2), P.hard)\n\t\tK:box(\"RiserKick\", Vector3.new(w - 0.1, 0.1, 0.02), CFrame.new(0, F.floorY + 0.07, zf - 0.005), P.rubber)\n\tend\n\tfor _, s in F.front do",
   "partsDelta": -38
  },
  {
   "rank": 2,
   "severity": "high",
   "area": "dash",
   "observed": "styles3/porter_3_center.png and porter_4_dash.png: from the fascia to the round passenger vent, the upper dash is one flat, featureless charcoal wall (about 1.4 x 0.75 studs). The upper/lower two-tone split is a hard 0.08 step, so the dash reads as a plain box.",
   "real": "On the passenger side of the Porter II, a wide open shelf is molded into the upper dash below the top tray. It has a rounded lip and sits above the glovebox. The charcoal upper and grey lower dash meet at a rounded horizontal ledge.",
   "fix": "Styles.porter: extras = { tray = true, shelf = true }. Dash.luau: add an ex.shelf block. ShelfCavity is a dark panel from the fascia edge+0.12 (cx+toC*(fw/2+0.12) = 0.84) to toC*(half-0.62) = 1.83, which clears the SideVent at 1.93..2.25. It spans y mid+0.26 = 2.53 to top-0.28 = 2.87 at face+0.006. Add a rounded ShelfLip capsule (d 0.10) at y 2.53, face+0.05, and a ShelfBrow capsule (d 0.06) at y 2.87. Add DashSplitRoll, a cylinder with d 0.10 at y mid+0.12 = 2.39 and z face-0.04 = -7.24. It rounds the step between the DashUpper face (-7.20) and the DashLower face (-7.28). Length is width-0.34 = 4.52, so its ends sit inside the DashEndRolls. The glovebox (y 1.76..2.17) stays below.",
   "code": "Styles.luau porter. OLD:\n\textras = { tray = true },\nNEW:\n\textras = { tray = true, shelf = true },\n\nDash.luau, insert right after the `if ex.tray then ... end` block:\n\tif ex.shelf then\n\t\t-- 포터: 조수석 쪽 위 대시의 열린 선반 (어두운 안쪽 + 둥근 아래 턱 + 위 눈썹) + 투톤 경계의 둥근 단\n\t\tlocal fw = cw + 0.6\n\t\tlocal xa, xb = cx + toC * (fw / 2 + 0.12), toC * (half - 0.62)\n\t\tlocal yb, yt = mid + 0.26, top - 0.28\n\t\tK:panel(\"ShelfCavity\", math.abs(xb - xa), yt - yb, 0.03, 0.07, CFrame.new((xa + xb) / 2, (yb + yt) / 2, face + 0.006), P.duct)\n\t\tK:capsule(\"ShelfLip\", Vector3.new(xa + toC * 0.02, yb, face + 0.05), Vector3.new(xb - toC * 0.02, yb, face + 0.05), 0.1, P.soft)\n\t\tK:capsule(\"ShelfBrow\", Vector3.new(xa + toC * 0.02, yt, face + 0.03), Vector3.new(xb - toC * 0.02, yt, face + 0.03), 0.06, P.soft)\n\t\tK:cyl(\"DashSplitRoll\", width - 0.34, 0.1, CFrame.new(0, mid + 0.12, face - 0.04), P.soft)\n\tend",
   "partsDelta": 13
  },
  {
   "rank": 3,
   "severity": "high",
   "area": "shifter",
   "observed": "styles3/porter_3_center.png and porter_1_driver.png, plus styles1/porter_3_center.png, porter_1_driver.png and porter_4_dash.png: the knob top is a glowing white Neon square (ShiftPattern = P.markWhite, 0.09x0.07) and is the brightest thing in the lower cabin. The lever is a bare thin stick out of the floor, and the low dome boot can't be seen.",
   "real": "The Porter II 5-speed lever is long and black. It rises from the floor in front of the seat box, between the driver and middle seats, from a tall pleated rubber boot on a square trim plate. The knob is a black pear shape with the 5-speed pattern printed in thin grey lines.",
   "fix": "Console.luau manualLever keeps the same base (x -0.30, z -5.775) and top b = (-0.36, 2.10, -5.495). Changes: a rounded ShiftPlate slab 0.46x0.46 at floorY+0.03, 0.02 above the CabinCarpet top 0.875. Four stacked ShiftBoot ellipsoids (d 0.36 down to 0.165, 0.11 tall each) along the lever axis at 0.05..0.305. A stick with d 0.045 starting inside the top ring. A knob ellipsoid 0.17x0.20x0.18. On the knob, a 0.08 gloss disc at +0.094, which sits on the ellipsoid surface (y+0.088 at r 0.04), carrying 4 thin non-Neon grey strokes (3 gates + crossbar).",
   "code": "Console.luau manualLever. OLD:\n\tlocal a = Vector3.new(x, floor + 0.08, z)\n\tlocal b = Vector3.new(x - toC * 0.06, floor + 1.25, z + 0.28)\n\tK:ell(\"ShiftBoot\", Vector3.new(0.34, 0.26, 0.34), CFrame.new(a + Vector3.new(0, 0.06, 0)), P.rubber)\n\tK:ell(\"ShiftBootTop\", Vector3.new(0.16, 0.14, 0.16), CFrame.new(a + Vector3.new(0, 0.2, 0.03)), P.rubber)\n\tK:seg(\"ShiftStick\", a + Vector3.new(0, 0.2, 0.03), b, 0.05, P.metalDark)\n\tK:ball(\"ShiftKnob\", 0.18, CFrame.new(b + Vector3.new(0, 0.05, 0.02)), P.hardDark)\n\tK:box(\"ShiftPattern\", Vector3.new(0.09, 0.006, 0.07), CFrame.new(b + Vector3.new(0, 0.14, 0.02)), P.markWhite)\nNEW:\n\tlocal a = Vector3.new(x, floor + 0.04, z)\n\tlocal b = Vector3.new(x - toC * 0.06, floor + 1.25, z + 0.28)\n\tlocal dir = (b - a).Unit\n\t-- 바닥 트림판(위에서 보면 둥근 사각) + 아래가 넓은 4단 주름 고무 부츠 + 긴 검은 레버 + 서양배 노브\n\tK:slab(\"ShiftPlate\", 0.46, 0.46, 0.03, 0.1, CFrame.new(a.X, floor + 0.03, a.Z), P.hardDark)\n\tfor i = 0, 3 do\n\t\tlocal d = 0.36 - i * 0.065\n\t\tK:ell(\"ShiftBoot\", Vector3.new(d, 0.11, d), CFrame.new(a + dir * (0.05 + i * 0.085)), P.rubber)\n\tend\n\tK:seg(\"ShiftStick\", a + dir * 0.3, b, 0.045, P.metalDark)\n\tlocal kc = b + Vector3.new(0, 0.06, 0.02)\n\tK:ell(\"ShiftKnob\", Vector3.new(0.17, 0.2, 0.18), CFrame.new(kc), P.hardDark)\n\t-- 노브 위 5단 무늬: 작은 광택 원판 + 가는 회색 선 4 (빛나는 흰 사각형 대신)\n\tlocal cap = CFrame.new(kc + Vector3.new(0, 0.094, 0))\n\tK:cyl(\"ShiftCap\", 0.012, 0.08, cap * CFrame.Angles(0, 0, math.pi / 2), P.gloss)\n\tlocal ink = { c = Color3.fromRGB(170, 174, 180), m = Enum.Material.SmoothPlastic }\n\tfor _, px in { -0.022, 0, 0.022 } do\n\t\tK:box(\"ShiftPattern\", Vector3.new(0.006, 0.004, 0.045), cap * CFrame.new(px, 0.007, 0), ink)\n\tend\n\tK:box(\"ShiftPattern\", Vector3.new(0.05, 0.004, 0.006), cap * CFrame.new(0, 0.007, 0), ink)",
   "partsDelta": 12
  },
  {
   "rank": 4,
   "severity": "high",
   "area": "other",
   "observed": "styles3/porter_1_driver.png, porter_3_center.png and porter_4_dash.png: under the dash and around the pedals you can see straight through to the white beach sand, black shadow shards and chassis pieces under the fascia. Commit b649af8 (after these renders) adds CabinCarpet only from dashFace-0.05 = -7.25 back and now hides the original CabCarpet, which reached z -8.305. The toe area at z -8.30..-7.25, below dashBottom 1.70, is therefore still open, in Roblox too. The new carpet is also grey needle-felt.",
   "real": "The Porter II footwell has a flat black rubber floor mat across the whole cab, running up to a vertical toe board under the dash. There is no carpet.",
   "fix": "Trim.luau floor block, porter only. Use P.rubber for CabinCarpet. Add ToeFloor (rubber) from dashFront+0.04 = -8.26 to fz0 = -7.25 at floorY+0.005, the same height as the carpet. Add ToeBoard, 4.84 x (dashBottom-floorY = 0.85) x 0.06, at z -8.23 with P.hardDark. It closes the gap up to the DashLower bottom (1.70) and stays clear of the pedal arm tops (z -7.27).",
   "code": "Trim.luau. OLD:\n\tif fz1 - fz0 > 0.5 then\n\t\tK:box(\"CabinCarpet\", Vector3.new(half * 2 - 0.06, 0.04, fz1 - fz0), CFrame.new(0, floor + 0.005, (fz0 + fz1) / 2), P.carpet)\n\tend\nNEW:\n\tlocal porter = F.style.key == \"porter\"\n\tif fz1 - fz0 > 0.5 then\n\t\tK:box(\"CabinCarpet\", Vector3.new(half * 2 - 0.06, 0.04, fz1 - fz0), CFrame.new(0, floor + 0.005, (fz0 + fz1) / 2), if porter then P.rubber else P.carpet)\n\tend\n\tif porter then\n\t\t-- 캡오버 발 공간: 대시 아래 앞벽(토보드)까지 고무 바닥으로 막음 (원래 CabCarpet 는 숨겨져 땅이 보임)\n\t\tlocal zf: number = F.dashFront + 0.04\n\t\tlocal th: number = F.dashBottom - floor\n\t\tK:box(\"ToeFloor\", Vector3.new(half * 2 - 0.06, 0.04, fz0 - zf), CFrame.new(0, floor + 0.005, (zf + fz0) / 2), P.rubber)\n\t\tK:box(\"ToeBoard\", Vector3.new(half * 2 - 0.06, th, 0.06), CFrame.new(0, floor + th / 2, zf + 0.03), P.hardDark)\n\tend",
   "partsDelta": 2
  },
  {
   "rank": 5,
   "severity": "medium",
   "area": "other",
   "observed": "styles3/porter_1_driver.png, porter_3_center.png and porter_4_dash.png show bright blue-white aluminium sport pedals with rubber stripes. In porter_3_center the clutch pad and a second alloy panel overlap. FootRest sits at x = -1.30-0.55 = -1.85 and is 0.30 wide. It intersects ClutchPedal at x -1.68 (0.36 wide), at the same y ≈1.2 and z -6.95..-7.05.",
   "real": "The Porter II has plain hanging steel pedals with black rubber pads: clutch, brake and gas. There is no dead-pedal footrest, because the clutch takes that space.",
   "fix": "Trim.luau pedals: when F.style.trimMat == 'plastic' (porter and solati, both commercial), use a P.rubber pad look and drop the PedalRubber strips. Skip FootRest whenever a clutch exists (#ped >= 3). Other cars are unchanged: they have 2 pedals and trimMat ~= 'plastic'.",
   "code": "Trim.luau. OLD:\n\tlocal gas, brake = ped[#ped], ped[#ped - 1]\nNEW:\n\tlocal gas, brake = ped[#ped], ped[#ped - 1]\n\t-- 상용차(포터 · 쏠라티, trimMat = \"plastic\"): 검은 고무 패드, 알루미늄 스포츠 페달 · 고무 띠 없음\n\tlocal sport = F.style.trimMat ~= \"plastic\"\n\tlocal pad = if sport then P.alloy else P.rubber\nOLD:\n\t\tK:panel(\"ClutchPedal\", 0.36, 0.28, 0.04, 0.08, c, P.alloy)\nNEW:\n\t\tK:panel(\"ClutchPedal\", 0.36, 0.28, 0.04, 0.08, c, pad)\nOLD:\n\t\tK:panel(\"BrakePedal\", 0.44, 0.3, 0.04, 0.08, c, P.alloy)\n\t\tfor i = -1, 1 do\nNEW:\n\t\tK:panel(\"BrakePedal\", 0.44, 0.3, 0.04, 0.08, c, pad)\n\t\tfor i = -1, (if sport then 1 else -2) do\nOLD:\n\t\t-- 풋레스트\n\t\tlocal fx = brake.X + F.side * 0.55\n\t\tK:panel(\"FootRest\", 0.3, 0.5, 0.04, 0.08, CFrame.new(fx, floor + 0.35, brake.Z - 0.1) * CFrame.Angles(math.rad(-40), 0, 0), P.alloy)\nNEW:\n\t\t-- 풋레스트: 수동(클러치 있음)은 그 자리에 클러치 페달이 있어 생략 (겹침)\n\t\tif #ped < 3 then\n\t\t\tlocal fx = brake.X + F.side * 0.55\n\t\t\tK:panel(\"FootRest\", 0.3, 0.5, 0.04, 0.08, CFrame.new(fx, floor + 0.35, brake.Z - 0.1) * CFrame.Angles(math.rad(-40), 0, 0), P.alloy)\n\t\tend\nOLD:\n\t\tK:panel(\"GasPedal\", 0.26, 0.6, 0.04, 0.07, c, P.alloy)\n\t\tfor i = -2, 2 do\nNEW:\n\t\tK:panel(\"GasPedal\", 0.26, 0.6, 0.04, 0.07, c, pad)\n\t\tfor i = -2, (if sport then 2 else -3) do",
   "partsDelta": -14
  },
  {
   "rank": 6,
   "severity": "medium",
   "area": "center screen",
   "observed": "styles3/porter_2_wheel.png and porter_3_center.png: the 8\" screen is a bare glass rectangle in a thin bezel with nothing around it, and its top edge is cut off by the fascia. NavGlass sits at face+0.10 = -7.10 with a -10° tilt, and the Fascia front face is at face+0.09 = -7.11. So the top 0.066 of the 0.36-tall screen, including the NavTop bar (y +0.15, z -7.1145), is behind the fascia surface.",
   "real": "The 2020+ Porter II 8-inch display audio has a gloss-black head-unit face, a column of hard keys on each side of the screen, and a power/volume knob and a tune knob at the lower corners. It sits in the fascia below the two vents.",
   "fix": "Cockpit.luau fascia branch: for porter, z = face+0.15 = -7.05, which moves the top-edge front to -7.071, clear of -7.11. Solati is untouched because its satin FasciaFrame is tied to this z. Dash.luau porter fascia branch, after the TopVents: add an AvnFace gloss panel (cw+0.34 = 1.18) x (ch+0.06 = 0.42) behind the bezel at ccf*(0,0,-0.035). Add 3 AvnKey boxes per side at x = ±(cw/2+0.085) = ±0.505 and y +0.13/+0.055/-0.02, and AvnKnob cylinders at y -0.145. The face's bottom edge (y 2.488) clears the hazard switch (top 2.475), and its top (2.902) meets the TopVent rims (2.905).",
   "code": "Cockpit.luau displays(). OLD:\n\t\tccf = CFrame.new(cx, math.min(F.dashMidY + 0.42, top - ch / 2 - 0.25), face + 0.1) * CFrame.Angles(math.rad(-10), 0, 0)\nNEW:\n\t\t-- 포터: 페시아 앞면(face + 0.09)보다 확실히 앞으로 (-10° 숙임에 화면 윗부분이 페시아에 묻히지 않게)\n\t\tccf = CFrame.new(cx, math.min(F.dashMidY + 0.42, top - ch / 2 - 0.25), face + (if S.key == \"porter\" then 0.15 else 0.1)) * CFrame.Angles(math.rad(-10), 0, 0)\n\nDash.luau porter fascia branch. OLD:\n\t\t\t\t\tvent(K, P, \"TopVent\", CFrame.new(cx + s * 0.27, scrY + ch / 2 + 0.14, face + 0.1), 0.42, 0.15)\n\t\t\t\tend\nNEW (the vent look is issue 9):\n\t\t\t\t\tvent(K, P, \"TopVent\", CFrame.new(cx + s * 0.27, scrY + ch / 2 + 0.14, face + 0.1), 0.42, 0.15, false, { frame = P.hardDark, duct = P.duct, slat = P.hard, knob = P.satin })\n\t\t\t\tend\n\t\t\t\t-- 포터 8\" 디스플레이 오디오: 광택 판 + 화면 양옆 단축키 3개씩 + 아래 볼륨 · 튜닝 노브\n\t\t\t\tK:panel(\"AvnFace\", cw + 0.34, ch + 0.06, 0.03, 0.06, ccf * CFrame.new(0, 0, -0.035), P.gloss)\n\t\t\t\tfor _, s in { -1, 1 } do\n\t\t\t\t\tfor i = 0, 2 do\n\t\t\t\t\t\tK:box(\"AvnKey\", Vector3.new(0.09, 0.055, 0.03), ccf * CFrame.new(s * (cw / 2 + 0.085), ch / 2 - 0.05 - i * 0.075, -0.005), P.button)\n\t\t\t\t\tend\n\t\t\t\t\tK:cyl(\"AvnKnob\", 0.05, 0.075, ccf * CFrame.new(s * (cw / 2 + 0.085), -ch / 2 + 0.035, 0) * ROT_X_TO_Z, P.alloy)\n\t\t\t\tend",
   "partsDelta": 14
  },
  {
   "rank": 7,
   "severity": "medium",
   "area": "dash",
   "observed": "styles1/porter_1_driver.png, styles3/porter_1_driver.png and porter_4_dash.png: the top tray shows only as a lighter flat strip. Its rim is frameRect boxes rotated flat (0.05 wide, 0.03 tall), so there is no visible lip. It spans x = 0.35 ± 1.63 = -1.28..1.98, so it runs into the cluster pod: the hood covers x -1.97..-0.57 and ClusterBack z -7.48..-7.06, against tray z -7.87..-7.37.",
   "real": "The Porter II dash top has a wide open storage tray with a raised rounded rim and dividers. It runs from beside the cluster hood to the passenger end, behind the defroster grille.",
   "fix": "Rewrite ex.tray in Dash.luau. X runs from cluster.X + (cluster.w+0.3)/2 + 0.15 = -0.42 to half-0.3 = 2.15. Z runs face-0.66..face-0.18 = -7.86..-7.38, behind the DefrostSlot row at -7.96 and in front of DashRoll at -7.33. Use a thin floor at top+0.006, a raised rounded lip (4 segments + 4 corner balls, d 0.07, so 0.07 tall) and 2 round dividers. frameRect (Dash.luau lines 57-63) is then unused and can be deleted.",
   "code": "Dash.luau. OLD:\n\tif ex.tray then\n\t\t-- 포터: 대시 위 전폭 수납 트레이 (테두리 + 바닥)\n\t\tlocal tw, td = width - 1.6, 0.5\n\t\tlocal tc = CFrame.new(toC * 0.35, top + 0.02, face - 0.42)\n\t\tK:box(\"TrayFloor\", Vector3.new(tw, 0.02, td), tc, P.hardDark)\n\t\tframeRect(K, \"TrayRim\", tc * CFrame.Angles(math.rad(90), 0, 0), tw, td, 0.05, P.hard)\n\tend\nNEW:\n\tif ex.tray then\n\t\t-- 포터: 대시 위 열린 수납 트레이. 계기판 차양 오른쪽부터 조수석 끝까지, 성에 슬롯 뒤.\n\t\t-- 0.07 솟은 둥근 턱(원통 4 + 모서리 공 4) + 둥근 칸막이 2\n\t\tlocal cl: Vector3 = F.cluster\n\t\tlocal xa = cl.X + toC * ((S.cluster.w + 0.3) / 2 + 0.15)\n\t\tlocal xb = toC * (half - 0.3)\n\t\tlocal tz0, tz1 = face - 0.66, face - 0.18\n\t\tlocal ly = top + 0.035\n\t\tK:box(\"TrayFloor\", Vector3.new(math.abs(xb - xa) - 0.04, 0.012, tz1 - tz0 - 0.04), CFrame.new((xa + xb) / 2, top + 0.006, (tz0 + tz1) / 2), P.hardDark)\n\t\tlocal c = { Vector3.new(xa, ly, tz0), Vector3.new(xb, ly, tz0), Vector3.new(xb, ly, tz1), Vector3.new(xa, ly, tz1) }\n\t\tfor i = 1, 4 do\n\t\t\tK:seg(\"TrayLip\", c[i], c[i % 4 + 1], 0.07, P.hard)\n\t\t\tK:ball(\"TrayLip\", 0.07, CFrame.new(c[i]), P.hard)\n\t\tend\n\t\tfor _, f in { 1 / 3, 2 / 3 } do\n\t\t\tlocal dx = xa + (xb - xa) * f\n\t\t\tK:seg(\"TrayDivider\", Vector3.new(dx, top + 0.03, tz0 + 0.03), Vector3.new(dx, top + 0.03, tz1 - 0.03), 0.06, P.hard)\n\t\tend\n\tend",
   "partsDelta": 6
  },
  {
   "rank": 8,
   "severity": "medium",
   "area": "headliner",
   "observed": "styles1/porter_1_driver.png and porter_4_dash.png, plus styles3/porter_1_driver.png and porter_4_dash.png: a black passenger-car overhead console with a red SOS button and two map lamps hangs above the mirror. Both sun visors show black VanityCover rectangles that read as holes in the light headliner.",
   "real": "The Porter II has no overhead console, SOS button or map lamps, just one rectangular room lamp with a 3-position switch in the middle of the headliner. The sun visors are plain vinyl with no vanity-mirror cover.",
   "fix": "Trim.luau: wrap OverheadConsole, MapLamp, SOS and RoofSwitch in `if F.style.key ~= \"porter\"`, keeping `oc` for the Carnival switches. For porter, give the existing center DomeLamp (z = lz0+llen*0.6 = -5.03) a grey rounded DomeHousing 0.56x0.05x0.32 and a small RoofSwitch behind the lens. Skip VanityCover for porter. Lights.build still finds the part by its 'DomeLamp' name, so the night lamp keeps working.",
   "code": "Trim.luau. OLD:\n\t\tlocal oc = CFrame.new(0, roofY - 0.06, lz0 + 0.45)\n\t\tK:rbox(\"OverheadConsole\", Vector3.new(0.78, 0.12, 0.5), 0.05, oc, P.hard)\n\t\tfor _, s in { -1, 1 } do\n\t\t\tK:box(\"MapLamp\", Vector3.new(0.2, 0.02, 0.12), oc * CFrame.new(s * 0.22, -0.065, 0.02), P.lampLens)\n\t\tend\n\t\tK:box(\"SOS\", Vector3.new(0.08, 0.02, 0.05), oc * CFrame.new(0, -0.065, 0.15), P.hazard)\n\t\tK:box(\"RoofSwitch\", Vector3.new(0.14, 0.02, 0.06), oc * CFrame.new(0, -0.065, -0.12), P.button)\nNEW:\n\t\tlocal oc = CFrame.new(0, roofY - 0.06, lz0 + 0.45)\n\t\tif F.style.key ~= \"porter\" then -- 포터: 오버헤드 콘솔 · 맵램프 · SOS 없음 (지붕 가운데 실내등 하나)\n\t\t\tK:rbox(\"OverheadConsole\", Vector3.new(0.78, 0.12, 0.5), 0.05, oc, P.hard)\n\t\t\tfor _, s in { -1, 1 } do\n\t\t\t\tK:box(\"MapLamp\", Vector3.new(0.2, 0.02, 0.12), oc * CFrame.new(s * 0.22, -0.065, 0.02), P.lampLens)\n\t\t\tend\n\t\t\tK:box(\"SOS\", Vector3.new(0.08, 0.02, 0.05), oc * CFrame.new(0, -0.065, 0.15), P.hazard)\n\t\t\tK:box(\"RoofSwitch\", Vector3.new(0.14, 0.02, 0.06), oc * CFrame.new(0, -0.065, -0.12), P.button)\n\t\tend\nOLD:\n\t\tK:box(\"DomeLamp\", Vector3.new(0.4, 0.02, 0.2), CFrame.new(0, roofY - 0.01, lz0 + llen * 0.6), P.lampLens)\nNEW:\n\t\tlocal dl = CFrame.new(0, roofY - 0.01, lz0 + llen * 0.6)\n\t\tif F.style.key == \"porter\" then\n\t\t\t-- 포터: 회색 사각 하우징 + 렌즈 + 3단 스위치\n\t\t\tK:rbox(\"DomeHousing\", Vector3.new(0.56, 0.05, 0.32), 0.022, dl * CFrame.new(0, -0.005, 0), P.hard)\n\t\t\tdl = dl * CFrame.new(0, -0.03, -0.03)\n\t\t\tK:box(\"RoofSwitch\", Vector3.new(0.1, 0.02, 0.04), dl * CFrame.new(0, 0, 0.13), P.button)\n\t\tend\n\t\tK:box(\"DomeLamp\", Vector3.new(0.4, 0.02, 0.2), dl, P.lampLens)\nOLD:\n\t\tK:box(\"VanityCover\", Vector3.new(0.5, 0.012, 0.26), v * CFrame.new(-s * 0.1, -0.035, 0.04), P.hard)\nNEW:\n\t\tif F.style.key ~= \"porter\" then\n\t\t\tK:box(\"VanityCover\", Vector3.new(0.5, 0.012, 0.26), v * CFrame.new(-s * 0.1, -0.035, 0.04), P.hard)\n\t\tend",
   "partsDelta": -5
  },
  {
   "rank": 9,
   "severity": "medium",
   "area": "vents",
   "observed": "styles3/porter_3_center.png, porter_4_dash.png and porter_1_driver.png: both TopVents have bright chrome rims (the default vent look uses P.chrome) and the round side vents have satin rims. They glare as white rings on the charcoal dash.",
   "real": "Porter II vents have black or dark-grey plastic surrounds, black louvers and a small tab. There is no chrome.",
   "fix": "Dash.luau: give TopVent a dark look (frame P.hardDark, slats P.hard, knob P.satin); that call is in the issue 6 code. Set the SideVent frame to P.hardDark when vk == 'top_rect' (porter only). Ray keeps gloss and Solati keeps satin.",
   "code": "Dash.luau (TopVent: see the NEW vent(...) call in issue 6). OLD:\n\t\t\tlocal look = { frame = if vk == \"pod_v\" then P.gloss else P.satin, duct = P.duct, slat = P.hard, knob = P.satin }\nNEW:\n\t\t\tlocal look = { frame = if vk == \"pod_v\" then P.gloss elseif vk == \"top_rect\" then P.hardDark else P.satin, duct = P.duct, slat = P.hard, knob = P.satin }",
   "partsDelta": 0
  },
  {
   "rank": 10,
   "severity": "low",
   "area": "console",
   "observed": "styles3/porter_3_center.png and porter_4_dash.png: below the 3 climate dials, the fascia is an empty flat black panel about 0.27 studs tall, down to its bottom edge (fy0 = mid-0.5 = 1.77).",
   "real": "The Porter II lower center fascia has a small coin/phone tray with a cupholder area, a 12 V socket and USB under the climate controls.",
   "fix": "Dash.luau porter fascia branch, after climate(): add a dark CoinTray panel (fw-0.5 = 0.94 x 0.16) at y fy0+0.13 = 1.90 (the climate plate bottom is ≈2.05) and face+0.092, in front of the fascia face at -7.11. Add a rounded lip capsule at y 1.82, x ±0.44, plus a satin 12 V socket at x +0.18 and a USB slot at x -0.18.",
   "code": "Dash.luau. OLD:\n\t\t\tclimate(K, F, P, S, cx, scrY - ch / 2 - 0.3, face + 0.1)\n\t\tend\nNEW:\n\t\t\tclimate(K, F, P, S, cx, scrY - ch / 2 - 0.3, face + 0.1)\n\t\t\tif S.key == \"porter\" then\n\t\t\t\t-- 공조 아래: 동전 트레이(어두운 홈 + 둥근 턱) + 12V 소켓 + USB\n\t\t\t\tlocal ty = fy0 + 0.13\n\t\t\t\tK:panel(\"CoinTray\", fw - 0.5, 0.16, 0.02, 0.05, CFrame.new(cx, ty, face + 0.092), P.duct)\n\t\t\t\tK:capsule(\"CoinTrayLip\", Vector3.new(cx - (fw - 0.56) / 2, ty - 0.08, face + 0.11), Vector3.new(cx + (fw - 0.56) / 2, ty - 0.08, face + 0.11), 0.05, P.hard)\n\t\t\t\tK:cyl(\"PowerOutlet\", 0.03, 0.08, CFrame.new(cx + 0.18, ty + 0.01, face + 0.1) * ROT_X_TO_Z, P.satin)\n\t\t\t\tK:box(\"UsbPort\", Vector3.new(0.07, 0.03, 0.02), CFrame.new(cx - 0.18, ty + 0.01, face + 0.105), P.hardDark)\n\t\t\tend\n\t\tend",
   "partsDelta": 11
  },
  {
   "rank": 11,
   "severity": "low",
   "area": "cluster",
   "observed": "styles1/porter_2_wheel.png, styles3/porter_2_wheel.png and porter_1_driver.png: the cluster LCD shows a big 'P' on a manual truck, and it would show 'D' while driving.",
   "real": "A manual Porter II has no P or D. Its 3.5\" LCD shows trip and fuel and, on newer trims, the current gear or a shift indicator.",
   "fix": "Cockpit.luau: set out.manual = S.shifter == 'manual' in Cockpit.build. In Cockpit.live, map P to N and D to 1..5 by speed (<15, <30, <50, <70 km/h, then 5), and keep R. Offline check: P shows N, and D at 42 km/h shows 3.",
   "code": "Cockpit.luau Cockpit.build. OLD:\n\tout.screens = displays(K, F, P, S)\nNEW:\n\tout.screens = displays(K, F, P, S)\n\tout.manual = S.shifter == \"manual\"\n\nCockpit.luau Cockpit.live. OLD:\n\tGauges.show(c.gear, state.gear)\nNEW:\n\tlocal gear: string = state.gear\n\tif ck.manual then\n\t\t-- 수동(포터): P / D 대신 N · 속도로 고른 단수 1~5, R 은 그대로\n\t\tif gear == \"D\" then\n\t\t\tlocal v = math.abs(state.kmh)\n\t\t\tgear = if v < 15 then \"1\" elseif v < 30 then \"2\" elseif v < 50 then \"3\" elseif v < 70 then \"4\" else \"5\"\n\t\telseif gear ~= \"R\" then\n\t\t\tgear = \"N\"\n\t\tend\n\tend\n\tGauges.show(c.gear, gear)",
   "partsDelta": 0
  },
  {
   "rank": 12,
   "severity": "low",
   "area": "seats",
   "observed": "styles3/porter_4_dash.png and porter_3_center.png: the passenger bench shows as two identical bucket-style backs, and nothing hints at the fold-down middle console.",
   "real": "The Porter II middle backrest folds forward into an armrest/console with cupholders. Its outline and pull loop are visible on the backrest.",
   "fix": "Seats.luau frontSeat, inner seat of the porter bench (x = 0.55, w = 1.2, H = 2.0): add 2 vertical FoldSeam lines on the insert edges (±w*0.25 = ±0.30, z -0.185, just proud of the insert front at -0.18), a horizontal seam at H*0.25, and a rubber FoldPull loop at backC*(0, H/2-0.05, -0.17), which sits on the shoulder roll surface.",
   "code": "Seats.luau frontSeat. OLD:\n\tK:ell(\"BackShoulder\", Vector3.new(w - 0.2, 0.3, 0.34), backC * CFrame.new(0, H / 2 - 0.12, 0), seatLook)\nNEW:\n\tK:ell(\"BackShoulder\", Vector3.new(w - 0.2, 0.3, 0.34), backC * CFrame.new(0, H / 2 - 0.12, 0), seatLook)\n\tif s.inner and F.style.key == \"porter\" then\n\t\t-- 포터 가운데 자리: 앞으로 접으면 컵홀더 콘솔이 되는 등받이 가운데 부분 (경계선 3 + 위 당김 고리)\n\t\tfor _, sx in { -1, 1 } do\n\t\t\tK:box(\"FoldSeam\", Vector3.new(0.012, H * 0.62, 0.01), backC * CFrame.new(sx * w * 0.25, -0.06, -0.185), P.hardDark)\n\t\tend\n\t\tK:box(\"FoldSeam\", Vector3.new(w * 0.5, 0.012, 0.01), backC * CFrame.new(0, H * 0.25, -0.185), P.hardDark)\n\t\tK:box(\"FoldPull\", Vector3.new(0.16, 0.035, 0.04), backC * CFrame.new(0, H / 2 - 0.05, -0.17), P.rubber)\n\tend",
   "partsDelta": 4
  }
 ]
}
```

## verify:carnival

```json
{
 "car": "carnival",
 "checked": [
  {
   "rank": 1,
   "ok": true,
   "problem": "",
   "correctedCode": ""
  },
  {
   "rank": 2,
   "ok": true,
   "problem": "",
   "correctedCode": ""
  },
  {
   "rank": 3,
   "ok": false,
   "problem": "The geometry and API use are correct. I checked them in a Luau sim of the carnival fixture (face -2.30, wheel R 0.671). In wheel-local coordinates the Airbag panel spans x ±0.30, y -0.129..0.145, z -0.03..0.15. The chin spans x ±0.21, y -0.201..-0.011, with its front at 0.136, so it sits 0.014 back. The KIA strokes are at z 0.148..0.156, inside the 0.129..0.145 face. The ButtonPanels (x ±0.265..0.474, z 0.036..0.056) tuck under the pad edge. The code block, though, was written against an old snapshot. The current airbag if-chain also holds the `S.key == \"tucson\"`, `kind == \"two\"` (G80) and `kind == \"vee4\"` (Sonata and taxi) pads. Replacing lines 94-98 with a three/trap/else chain would delete those branches and put the ball ellipsoid back on four other cars; on today's line numbers it does not even parse. Add the trap pad as one extra elseif instead. HEAD cd5f277 already does this correctly at Cockpit.luau:105-108.",
   "correctedCode": "-- Styles.luau, LIST.carnival.wheel: add  hubShape = \"trap\",\n-- Cockpit.luau, wheel(): do NOT replace the airbag if-chain. Insert one branch before `elseif kind == \"vee4\" then`:\n\t\telseif ws.hubShape == \"trap\" then\n\t\t\t-- 카니발 KA4: 가로로 넓은 둥근 사다리꼴 패드 (위 폭 0.6 · 아래 턱 폭 0.42), 앞면 평평 (엠블럼 바로 뒤)\n\t\t\tK:panel(\"Airbag\", hub.X, hub.Y * 0.72, hub.Z, 0.11, W * CFrame.new(0, hy + hub.Y * 0.1, 0.06), P.wheelHub)\n\t\t\tK:panel(\"AirbagChin\", hub.X * 0.7, hub.Y * 0.5, hub.Z * 0.9, 0.08, W * CFrame.new(0, hy - hub.Y * 0.2, 0.055), P.wheelHub)\n-- (keep the existing three / tucson / two / vee4 / else-ell branches unchanged)"
  },
  {
   "rank": 4,
   "ok": false,
   "problem": "The new lowerV blade is correct. Sim, wheel-local: each blade (rbox 0.458 x 0.085 x 0.05, long edges rounded r 0.022) runs from x ±0.13..±0.17 at y -0.186, under the chin bottom (-0.201), to x ±0.003 at y -0.648. The ends sit inside the rim tube (inner radius 0.606), and the two blades are about 0.006 apart at 6 o'clock. The gloss inlay (z 0.012..0.024) fits on the 0.041 flat front face (z 0.015). The code block is stale, though. It replaces the whole `if kind == \"vee4\" or kind == \"u4\" then ... end` with the old body that only builds K:seg rods. The current branch also builds the Sonata and taxi vee4 flat rbox blades with satin trim, and the Tucson flat box spokes. Pasting the block would turn those cars' lower spokes back into round pipes. Only put the lowerV branch in front and keep the existing body. HEAD cd5f277 does this at Cockpit.luau:151-162.",
   "correctedCode": "-- Styles.luau, LIST.carnival.wheel: add  lowerV = true,\n-- Cockpit.luau, wheel(), inside `for _, s in { -1, 1 } do`: change ONLY the line\n\t\t\tif kind == \"vee4\" or kind == \"u4\" then\n-- to the block below; everything after it (vee4 flat blades, tucson spokes, seg fallback) stays as is:\n\t\t\tif ws.lowerV then\n\t\t\t\t-- 카니발 KA4: 허브 턱 양끝에서 6시 림(±4°)으로 모이는 납작한 V 블레이드 + 하이글로시 인레이\n\t\t\t\tlocal a2 = Vector2.new(s * 0.13, hy - hub.Y * 0.42)\n\t\t\t\tlocal t = math.rad(-90 + s * 4)\n\t\t\t\tlocal b2 = Vector2.new(math.cos(t) * (R - 0.03), math.sin(t) * (R - 0.03))\n\t\t\t\tlocal d = b2 - a2\n\t\t\t\tlocal bc = W * CFrame.new((a2.X + b2.X) / 2, (a2.Y + b2.Y) / 2, -0.01) * CFrame.Angles(0, 0, math.atan2(d.Y, d.X))\n\t\t\t\tK:rbox(\"LowerSpoke\", Vector3.new(d.Magnitude, 0.085, 0.05), 0.022, bc, P.hard)\n\t\t\t\tif ws.lowerTrim then\n\t\t\t\t\tK:box(\"LowerSpokeTrim\", Vector3.new(d.Magnitude - 0.1, 0.032, 0.012), bc * CFrame.new(0, 0, 0.027), if ws.lowerTrim == \"gloss\" then P.gloss else P.satin)\n\t\t\t\tend\n\t\t\telseif kind == \"vee4\" or kind == \"u4\" then"
  },
  {
   "rank": 5,
   "ok": false,
   "problem": "The plate geometry is right. Sim: DialPlate x ±0.42, z -1.746..-0.446, y 2.010..2.040. DialPlateRim x ±0.44, z -1.766..-0.426, top at 2.029. The charge pad ends at z -1.84 and the armrest starts at -0.25, and every part sits inside the ±0.47 deck. Raising the cupholders to top+0.002 is also needed: at top-0.01 they sit entirely under the plate's top face (2.040). The cupholders() replacement is the problem. It is a shared helper also used by sonata (buttons_col), sonata_taxi (lever), tucson (buttons_row) and ray (lowTray). The proposed version defaults every other caller to `ringLook or P.chrome` and drops CupholderLip. That undoes the d3edf45 fix (P.hardDark ring, satin lip and duct, added because the chrome discs read as white hot-plates). The observed \"bright chrome rings\" are already gone in the current code. Leave cupholders() alone and only change the dial branch. A smaller note: the rim's top face (2.029) stands only 0.004 above the deck, so the satin edge reads as a thin line.",
   "correctedCode": "-- Console.luau: leave cupholders() as it is (P.hardDark ring + P.satin lip + P.duct, shared by all models).\n-- dial branch: replace\n\t\tK:slab(\"DialPlate\", w - 0.2, 0.62, 0.03, 0.14, CFrame.new(x, top, gz), P.gloss)\n-- ->\n\t\t-- KA4: 다이얼 · 버튼 · 컵홀더를 피아노 블랙 판 한 장 + 새틴 테두리가 감쌈 (z gz-0.33 .. gz+0.97)\n\t\tlocal pc = CFrame.new(x, top, gz + 0.32)\n\t\tK:slab(\"DialPlateRim\", w - 0.12, 1.34, 0.02, 0.15, pc * CFrame.new(0, -0.006, 0), P.satin)\n\t\tK:slab(\"DialPlate\", w - 0.16, 1.3, 0.03, 0.14, pc, P.glossMatte)\n-- init.client.luau palette() (if missing):  glossMatte = { c = rgb(7, 7, 9), m = SP, r = 0.05 },\n-- and replace\n\t\tcupholders(K, P, x, top - 0.01, gz + 0.62, false)\n-- ->\n\t\tcupholders(K, P, x, top + 0.002, gz + 0.62, false) -- 판 윗면(top + 0.015) 위로"
  },
  {
   "rank": 6,
   "ok": true,
   "problem": "",
   "correctedCode": ""
  },
  {
   "rank": 7,
   "ok": true,
   "problem": "",
   "correctedCode": ""
  },
  {
   "rank": 8,
   "ok": true,
   "problem": "",
   "correctedCode": ""
  }
 ]
}
```

## verify:solati

```json
{
 "car": "solati",
 "checked": [
  {
   "rank": 1,
   "ok": true,
   "problem": "",
   "correctedCode": ""
  },
  {
   "rank": 2,
   "ok": false,
   "problem": "The pod collides with the right column stalk. Cockpit column() puts the wiper StalkTip ellipsoid at W*(R+0.02,-0.16,-0.22) = (-0.77, 2.27, -6.20). It is 0.13 long along the stalk, so its end reaches x -0.706. The proposed GearPod (semi-axes 0.25/0.28/0.32 at (-0.68, 2.22, -6.45)) contains the tip's centre line (normalised 0.70, under 1), and the tip end also sits inside the ShiftBoot at a=(-0.68, 2.34, -6.18) (0.93, under 1), so the wiper stalk vanishes into the pod. The pod also covers the lower-left corner of the ClimatePlate (1.16x0.34 at y 2.44, z -6.35). The plate corner points sit 0.14 inside the pod surface (normalised 0.40), and the pod reaches the plate edge up to y 2.45. Two minor points: the knob is 0.22 TOWARD the driver from the rim plane, not behind it (clearance is still 0.09), and at y 2.10 the pod's right edge (-0.43) is only 0.05 from the SirenBox. Fix: keep the fascia extension to mid-0.6. Make the pod smaller, lower and further right: centre (-0.62, 2.02), radii 0.22/0.26/0.30. It then spans x -0.84..-0.40 and y 1.76..2.28, still overlaps the stack's left edge at -0.72, and clears the stalk tip (1.43), the plate corner (1.22) and the boot (2.07). The knob moves to (-0.62, 2.39, -5.91), 0.065 outside the rim. This pairs with the narrower siren box in rank 9 (-0.33..0.67), which leaves a 0.07 gap.",
   "correctedCode": "-- Dash.luau fascia branch: keep\n\t\t\tlocal fy0, fy1 = mid - (if vk == \"trap_v\" then 0.6 else 0.5), top - 0.04\n-- Dash.luau: replace the `if S.shifter == \"dash_pod\" then ... end` block with\n\tif S.shifter == \"dash_pod\" then\n\t\t-- Solati: rounded pod at the stack's lower left (same charcoal, overlaps the stack's left edge -0.72) + 2-step boot + lever tilted 45 deg toward the driver + 6-speed knob.\n\t\t-- Kept low and to the right to clear the wiper stalk tip (-0.77, 2.27, -6.20), the climate plate's lower-left corner and the siren box (-0.33..): pod x -0.84..-0.40, y 1.76..2.28\n\t\tlocal px, py = F.wheel.c.X + toC * 0.88, mid - 0.5 -- (-0.62, 2.02)\n\t\tlocal pr = Vector3.new(0.22, 0.26, 0.3) -- pod radii\n\t\tK:ell(\"GearPod\", pr * 2, CFrame.new(px, py, face), P.hard)\n\t\tlocal dir = Vector3.new(0, 0.7, 0.71).Unit\n\t\tlocal a = Vector3.new(px, py + 0.1, face + pr.Z * math.sqrt(1 - (0.1 / pr.Y) ^ 2) - 0.015) -- sunk 0.015 into the pod's upper front face (-6.19)\n\t\tK:ell(\"ShiftBoot\", Vector3.new(0.21, 0.16, 0.21), CFrame.new(a), P.rubber)\n\t\tK:ell(\"ShiftBootTop\", Vector3.new(0.13, 0.13, 0.13), CFrame.new(a + dir * 0.09), P.rubber)\n\t\tlocal b = a + dir * 0.34\n\t\tK:seg(\"ShiftStick\", a + dir * 0.1, b, 0.04, P.metalDark)\n\t\tlocal kc = b + dir * 0.05 -- (-0.62, 2.39, -5.91): 0.065 outside the rim\n\t\tK:ball(\"ShiftKnob\", 0.15, CFrame.new(kc), P.hardDark)\n\t\tK:box(\"ShiftPattern\", Vector3.new(0.07, 0.006, 0.06), CFrame.fromMatrix(kc + dir * 0.074, Vector3.xAxis, dir), { c = Color3.fromRGB(170, 174, 180), m = Enum.Material.SmoothPlastic })\n\tend"
  },
  {
   "rank": 3,
   "ok": true,
   "problem": "",
   "correctedCode": ""
  },
  {
   "rank": 4,
   "ok": false,
   "problem": "Stale. The OLD block (K:seg \"APillarTrim\" d=0.15 at nOut*0.12) is no longer in Dash.luau. Commit 724c72d (made after these renders) already replaced it for every car, Solati included, with a flat zbox: 0.34 wide, 0.09 thick, 0.17 inside the glass, outer edge folded 30 degrees toward the door glass. This fix cannot apply. A solati branch on top would only re-add a second, unfolded variant. One small note on the existing generic trim: at dash-top height its folded outer edge reaches x about 3.10, which is the side-glass inner face, but that is hidden in the dash corner.",
   "correctedCode": "-- no change: Dash.luau body() already builds APillarTrim as a flat folded zbox for all cars (commit 724c72d)."
  },
  {
   "rank": 5,
   "ok": true,
   "problem": "",
   "correctedCode": ""
  },
  {
   "rank": 6,
   "ok": true,
   "problem": "",
   "correctedCode": ""
  },
  {
   "rank": 7,
   "ok": false,
   "problem": "The Fit.luau part is correct. It gives roofY 5.825, linerZ0 -5.276 and linerZ1 -3.605 (llen 1.67), and no other car qualifies. But Trim.build's grab-handle list is not adapted to such a short liner. It places two passenger-side handles (x +2.88): one at lz0+0.9 = -4.38 (z -4.66..-4.10) and one at lz0+llen*0.7 = -4.11 (z -4.39..-3.83). These overlap by 0.29 at the same x, so the cab shows a doubled, garbled handle. A fix is needed in Trim.luau. The gate llen < 2.5 only matches the Solati: the other liners are 3.18 to 8.38.",
   "correctedCode": "-- Trim.luau Trim.build, grab handles  OLD:\n\t\tfor _, g in { { -F.side, lz0 + 0.9 }, { -1, lz0 + llen * 0.7 }, { 1, lz0 + llen * 0.7 } } do\n-- NEW:\n\t\t-- short cab-only liner (Solati, < 2.5): one handle above each door (two on the same side would overlap)\n\t\tlocal grabs = if llen < 2.5 then { { -1, lz0 + llen * 0.55 }, { 1, lz0 + llen * 0.55 } } else { { -F.side, lz0 + 0.9 }, { -1, lz0 + llen * 0.7 }, { 1, lz0 + llen * 0.7 } }\n\t\tfor _, g in grabs do\n-- (rest of the loop body unchanged; Fit.luau CabHeader block as proposed)"
  },
  {
   "rank": 8,
   "ok": true,
   "problem": "",
   "correctedCode": ""
  },
  {
   "rank": 9,
   "ok": false,
   "problem": "First, the fix keeps RadioMic as an rbox at (cx+toC*0.95, mid-0.38, face+0.16), which is z -6.35..-6.23. Nothing is behind it: the Fascia ends at x 0.72, the glovebox starts at 1.02 and the DashLower face is at face-0.08 = -6.53. So the handset floats 0.18 in mid-air in front of the lower dash. Second, the widened SirenBox (x -0.38..0.72) ends exactly at the Fascia side edge, but the Fascia's bottom corners are rounded (r 0.16). At the box bottom (y about 1.96) the fascia only reaches x 0.67, so the box's lower-right corner overhangs the lower dash with a gap of about 0.12 behind it. Third, its left end at -0.38 nearly touches the gear pod. Fix: make the box 1.0 wide (x -0.33..0.67), set the switch pitch to 0.13 and put the dial at 0.38. Hang the handset on a clip on the lower dash face at x 0.86 (clear of the glovebox from 1.02), with a cord to the box. The part count stays about the same (-1 versus the old block).",
   "correctedCode": "-- Dash.luau: replace the `if ex.siren then ... end` block\n\tif ex.siren then\n\t\t-- 119: siren/beacon control head (2 rows of switches + LEDs + mode dial), x -0.33..0.67: clear of the gear pod (-0.40), right end inside the stack's rounded lower corner.\n\t\t-- Radio handset on a clip on the lower dash face (face - 0.08), right of the stack, cord to the head (not a block floating in the air)\n\t\tlocal sc = CFrame.new(cx + toC * 0.17, mid - 0.42, face + 0.14) * CFrame.Angles(math.rad(-12), 0, 0)\n\t\tK:rbox(\"SirenBox\", Vector3.new(1.0, 0.28, 0.2), 0.05, sc, P.hardDark)\n\t\tlocal cols = { P.hazard, P.lampBlue, P.lampAmber, P.button, P.button, P.button }\n\t\tfor r = 0, 1 do\n\t\t\tfor i = 1, 6 do\n\t\t\t\tlocal x = -0.42 + (i - 1) * 0.13\n\t\t\t\tK:box(\"SirenSwitch\", Vector3.new(0.09, 0.07, 0.04), sc * CFrame.new(x, 0.05 - r * 0.1, 0.11), if r == 0 then cols[i] else P.button)\n\t\t\t\tif r == 0 then\n\t\t\t\t\tK:box(\"SirenLed\", Vector3.new(0.025, 0.012, 0.01), sc * CFrame.new(x, 0.105, 0.105), if i <= 3 then P.ledRed else P.ledGreen)\n\t\t\t\tend\n\t\t\tend\n\t\tend\n\t\tK:cyl(\"SirenDialRing\", 0.02, 0.18, sc * CFrame.new(0.38, 0, 0.105) * ROT_X_TO_Z, P.satin)\n\t\tK:cyl(\"SirenDial\", 0.06, 0.145, sc * CFrame.new(0.38, 0, 0.13) * ROT_X_TO_Z, P.hardDark)\n\t\tK:box(\"SirenDialMark\", Vector3.new(0.012, 0.045, 0.006), sc * CFrame.new(0.38, 0.035, 0.162), P.markWhite)\n\t\tlocal mx, lf = cx + toC * 0.86, face - 0.08 -- lower dash face\n\t\tK:box(\"MicClip\", Vector3.new(0.05, 0.04, 0.03), CFrame.new(mx, mid - 0.25, lf + 0.015), P.satin)\n\t\tK:panel(\"RadioMic\", 0.12, 0.22, 0.07, 0.05, CFrame.new(mx, mid - 0.38, lf + 0.04), P.hardDark)\n\t\tlocal m0 = Vector3.new(mx, mid - 0.48, lf + 0.04)\n\t\tlocal m1 = Vector3.new((mx + cx + toC * 0.66) / 2, mid - 0.6, lf + 0.09)\n\t\tK:seg(\"MicCord\", m0, m1, 0.025, P.hardDark)\n\t\tK:seg(\"MicCord\", m1, Vector3.new(cx + toC * 0.64, mid - 0.5, face + 0.1), 0.025, P.hardDark)\n\tend"
  },
  {
   "rank": 10,
   "ok": true,
   "problem": "",
   "correctedCode": ""
  },
  {
   "rank": 11,
   "ok": false,
   "problem": "As written, the fix conflicts with the current code. Cockpit.live now remaps the gear itself for manual cars (ck.manual): 'D' becomes a speed-picked gear and anything that is not 'R' becomes 'N'. If init.client.luau already sent '1'..'6' for shifter 'manual', Cockpit.live would turn every digit into 'N', so the Porter would show N while driving. Also, the init line is now about line 695, not 678. Leave init.client.luau unchanged and do it in Cockpit instead: 5 gears for the Porter and 6 for the Solati. This is how commit ac9ae56 implements it.",
   "correctedCode": "-- Cockpit.luau Cockpit.build (after out.screens = ...):\n\tout.manual = if S.shifter == \"manual\" then 5 elseif S.shifter == \"dash_pod\" then 6 else nil\n-- Cockpit.luau Cockpit.live  OLD:  Gauges.show(c.gear, state.gear)\n-- NEW:\n\tlocal gear: string = state.gear\n\tif ck.manual then\n\t\tif gear == \"D\" then\n\t\t\tlocal v = math.abs(state.kmh)\n\t\t\tlocal n = if v < 15 then 1 elseif v < 30 then 2 elseif v < 50 then 3 elseif v < 70 then 4 elseif v < 90 then 5 else 6\n\t\t\tgear = tostring(math.min(n, ck.manual))\n\t\telseif gear ~= \"R\" then\n\t\t\tgear = \"N\"\n\t\tend\n\tend\n\tGauges.show(c.gear, gear)\n-- init.client.luau: unchanged"
  }
 ]
}
```

## verify:porter

```json
{
 "car": "porter",
 "checked": [
  {
   "rank": 1,
   "ok": false,
   "problem": "HEAD ac9ae56 already has this fix as proposed. The riser itself is correct: rbox (4.78, 0.64, 1.725) at y 0.85..1.49 and z -5.395..-3.67. The CushionPan bottom sits flush on it, the roll overhangs by 0.11, and it is gated to porter. The offline sim builds without errors. Three placement defects remain. (a) The riser collides with the existing Trim door MapPocket. The pocket is a zbox 0.13 wide at x = ±(halfIn+0.02-0.07) = ±2.40, so it spans x 2.335..2.465, y 0.94..1.16 and z -5.79..-4.23. The riser side face is at |x| = 2.39, so the pocket sinks 0.055 into the riser over z -5.395..-4.23. Its front end visibly dives into the riser's front corner. The DoorReflector at (±2.41, 0.91, -3.95) is now trapped in the 0.03 slit between the riser and the door card, so it is a wasted part. (b) The ReclineLever floats. It sits at x = x+out*(w/2+0.03) = -2.13 (inner surface -2.105), but the cushion pan side is at x+out*(w-0.14)/2 = -2.03. That leaves a 0.075 air gap and nothing holds the lever. (c) With no SeatBase and no console, both front buckles (y 1.69..1.90 at x -0.44 and 1.09) now hang 0.2 above the visible riser top (1.49). Corrections were tested in the offline sim (car_14415): porter goes from 713 to 714 parts, and all other 7 fixtures produce identical part hashes.",
   "correctedCode": "-- Relative to HEAD ac9ae56.\n-- Seats.luau frontSeat. OLD:\n\t\tif not s.inner and (x < 0) == (F.side < 0) then\n\t\t\tlocal lx = x + out * (w / 2 + 0.03)\n\t\t\tK:capsule(\"ReclineLever\", Vector3.new(lx, cushTop - 0.13, zR - 0.5), Vector3.new(lx, cushTop - 0.07, zR - 0.22), 0.05, P.hardDark)\n\t\tend\n-- NEW:\n\t\tif not s.inner and (x < 0) == (F.side < 0) then\n\t\t\t-- 쿠션 옆면(반폭 (w - 0.14) / 2)에 붙인 레버 + 뒤 끝 회전축 원판 (공중에 뜨지 않게)\n\t\t\tlocal sideX = x + out * ((w - 0.14) / 2)\n\t\t\tlocal lx = sideX + out * 0.03\n\t\t\tK:capsule(\"ReclineLever\", Vector3.new(lx, cushTop - 0.13, zR - 0.5), Vector3.new(lx, cushTop - 0.07, zR - 0.22), 0.05, P.hardDark)\n\t\t\tK:cyl(\"ReclinePivot\", 0.03, 0.09, CFrame.new(sideX + out * 0.015, cushTop - 0.07, zR - 0.22), P.hardDark)\n\t\tend\n\n-- Seats.luau frontSeat (buckle). OLD:\n\tlocal buckle = CFrame.new(bkx, bky, bkz) * CFrame.Angles(math.rad(-20), 0, 0)\n\tK:box(\"Buckle\", Vector3.new(0.09, 0.22, 0.06), buckle, P.hardDark)\n-- NEW:\n\tlocal buckle = CFrame.new(bkx, bky, bkz) * CFrame.Angles(math.rad(-20), 0, 0)\n\tK:box(\"Buckle\", Vector3.new(0.09, 0.22, 0.06), buckle, P.hardDark)\n\tif riser then\n\t\t-- 포터: 버클이 받침 상자 윗면(cushTop - 0.26)에서 올라온 벨트 끈에 달림 (받침 위에 떠 있지 않게)\n\t\tlocal L = (bky - (cushTop - 0.26)) / math.cos(math.rad(20)) - 0.11 + 0.02\n\t\tK:box(\"BuckleStalk\", Vector3.new(0.05, L, 0.02), buckle * CFrame.new(0, -0.11 - L / 2, 0), P.belt)\n\tend\n\n-- Trim.luau doorCard. OLD:\n\tK:zbox(\"MapPocket\", Vector3.new(0.13, 0.22, len * 0.45), 0.05, CFrame.new(x + inward * 0.07, y0 + 0.2, zc + len * 0.12), P.hardDark)\n\t-- 바닥 쪽 반사등\n\tK:box(\"DoorReflector\", Vector3.new(0.03, 0.05, 0.2), CFrame.new(x + inward * 0.06, y0 + 0.06, z1 - 0.25), P.reflector)\n-- NEW:\n\tlocal pz0, pz1 = zc + len * 0.12 - len * 0.225, zc + len * 0.12 + len * 0.225\n\tlocal s0 = F.front[1]\n\tif S.key == \"porter\" and s0 then\n\t\t-- 포터: 문 아래 뒤쪽은 전폭 좌석 받침 상자(앞 끝 s0.z - cushZ / 2 + 0.08, 옆면 반폭 halfIn - 0.06) 옆이라\n\t\t-- 맵포켓을 받침 앞 발 공간으로 (스피커 링 뒤)\n\t\tpz1 = math.min(pz1, s0.z - s0.cushSize.Z / 2 + 0.08 - 0.04)\n\t\tpz0 = math.max(z0 + 0.75, pz1 - len * 0.45)\n\tend\n\tif pz1 - pz0 > 0.3 then\n\t\tK:zbox(\"MapPocket\", Vector3.new(0.13, 0.22, pz1 - pz0), 0.05, CFrame.new(x + inward * 0.07, y0 + 0.2, (pz0 + pz1) / 2), P.hardDark)\n\tend\n\t-- 바닥 쪽 반사등 (포터: 문 뒤 아래 끝이 좌석 받침 상자 옆면에 가려 안 보임 -> 생략)\n\tif S.key ~= \"porter\" then\n\t\tK:box(\"DoorReflector\", Vector3.new(0.03, 0.05, 0.2), CFrame.new(x + inward * 0.06, y0 + 0.06, z1 - 0.25), P.reflector)\n\tend\n-- Result for porter: door pocket z -6.40..-5.435, clear of the speaker ring (-6.825..-6.475 at y 1.16) and of the riser front (-5.395).\n-- Lever inner surface at -2.035 against the pan side (-2.03). Buckle stalk runs from y 1.47 (riser top 1.49) to the buckle bottom (1.697).\n-- For non-porter cars the pocket keeps the same centre and length (len >= 0.8, so len*0.45 > 0.3)."
  },
  {
   "rank": 2,
   "ok": true,
   "problem": "",
   "correctedCode": ""
  },
  {
   "rank": 3,
   "ok": true,
   "problem": "",
   "correctedCode": ""
  },
  {
   "rank": 4,
   "ok": true,
   "problem": "",
   "correctedCode": ""
  },
  {
   "rank": 5,
   "ok": true,
   "problem": "",
   "correctedCode": ""
  },
  {
   "rank": 6,
   "ok": true,
   "problem": "",
   "correctedCode": ""
  },
  {
   "rank": 7,
   "ok": true,
   "problem": "",
   "correctedCode": ""
  },
  {
   "rank": 8,
   "ok": true,
   "problem": "",
   "correctedCode": ""
  },
  {
   "rank": 9,
   "ok": true,
   "problem": "",
   "correctedCode": ""
  },
  {
   "rank": 10,
   "ok": true,
   "problem": "",
   "correctedCode": ""
  },
  {
   "rank": 11,
   "ok": true,
   "problem": "",
   "correctedCode": ""
  },
  {
   "rank": 12,
   "ok": false,
   "problem": "This is already in HEAD as proposed. The vertical FoldSeams sit at ±w*0.25 = ±0.30. That is 0.01 from the existing fabric BackStitch lines at ±(w*0.25+0.01) = ±0.31, so they duplicate them. They are also buried in the BackBolster ellipsoids. On the inner seat (w 1.2, bol 0.5) the bolster is 0.34 x 1.64 x 0.37 at local (±0.40, -0.06, -0.085). At x 0.30, y -0.06, z -0.185 the ellipsoid test gives (0.1/0.17)²+((-0.1)/0.185)² = 0.638 < 1, so the point is inside. The seams only show where |y+0.06| > 0.49, i.e. as two 0.13-long stubs at the top and bottom. The horizontal seam is w*0.5 wide (±0.30) at H*0.25. Its ends run over the bolster surface (bolster at z -0.165) and float about 0.015 in front of it. Fix: move the outline onto the visible insert, inside the bolster inner reach of ±(w/2-0.37) = ±0.23. Use vertical seams at ±w*0.17 = ±0.204, running from y -0.66 up to the crossbar at H*0.22, and a crossbar w*0.34 wide. FoldPull is fine: its back face touches the shoulder roll surface at z -0.15. Verified in the sim: seams at world x 0.346 / 0.754 and crossbar y 3.133, all at z ≈ -3.97, in front of the insert face.",
   "correctedCode": "-- Seats.luau frontSeat (HEAD). OLD:\n\t\tfor _, sx in { -1, 1 } do\n\t\t\tK:box(\"FoldSeam\", Vector3.new(0.012, H * 0.62, 0.01), backC * CFrame.new(sx * w * 0.25, -0.06, -0.185), P.hardDark)\n\t\tend\n\t\tK:box(\"FoldSeam\", Vector3.new(w * 0.5, 0.012, 0.01), backC * CFrame.new(0, H * 0.25, -0.185), P.hardDark)\n-- NEW:\n\t\t-- 세로 경계는 볼스터(안쪽 끝 ±(w / 2 - 0.37))와 기존 스티치(±(w * 0.25 + 0.01)) 안쪽, 보이는 인서트 위에\n\t\tfor _, sx in { -1, 1 } do\n\t\t\tK:box(\"FoldSeam\", Vector3.new(0.012, H * 0.55, 0.01), backC * CFrame.new(sx * w * 0.17, -H * 0.055, -0.185), P.hardDark)\n\t\tend\n\t\tK:box(\"FoldSeam\", Vector3.new(w * 0.34 + 0.012, 0.012, 0.01), backC * CFrame.new(0, H * 0.22, -0.185), P.hardDark)\n-- The FoldPull line stays unchanged."
  }
 ]
}
```
