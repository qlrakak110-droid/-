# car-interior-critique (wf_744ba2b8-08c)

- status: completed
- failed agents (never finished, usually the usage limit): none

## critique:sonata

```json
{
 "car": "Hyundai Sonata DN8 (2019-2023), style key \"sonata\" (the taxi style picks up the same shared dash, screen and wheel fixes)",
 "summary": "The render has the right DN8 parts: the slim-hood digital cluster, the 4-spoke inverted-V wheel, the satin line with ambient strip, twin centre vents with hazard, knurled climate dials, and the P/R/N/D button column with Bose door speakers. It still misses the signature look. The 10.25\" screen sits on a neck well above the cluster and the S-curve is a thin black pipe. Legacy parts still show (a white 6-o'clock spoke bar and dark leftover knobs). The centre stack reads as a boxy piano-black 2-DIN radio. The door line and ambient strip drop 0.2 below the dash line, and the door armrests sit at seat-cushion height.",
 "issues": [
  {
   "rank": 1,
   "severity": "high",
   "area": "center screen",
   "observed": "sonata_1_driver / sonata_2_wheel / sonata_4_dash: the 10.25in screen stands on a CenterNeck high above the dash top. Its centre is y=top+ch/2+0.05=2.75 (top edge 2.95), about 0.28 higher than the cluster centre (yS=2.467). It also sits 0.21 further forward (z=-2.01 vs the cluster at zS=-1.80), so it looks like a tablet on a stalk. The S-curve is five 0.07-diameter cylinders that read as a black antenna or pipe from the hood corner to the screen's top-left (diagonal stick in sonata_3_center and sonata_4_dash, knob end visible in sonata_2_wheel).",
   "real": "On the DN8 the 10.25in screen sits right next to the 12.3in cluster, at about the same height and in the same plane, with its base half sunk into the dash and no neck. The right end of the slim cluster hood sweeps down between the two panes and runs into the screen's gloss-black surround (the S-curve). The screen's top edge is roughly level with the hood.",
   "fix": "Cockpit.luau displays(), kind==\"float\" (lines 307-324): when S.sCurve, place the screen at the cluster's height and plane: ccf = (x, yS+(h-ch)/2+0.08, zS-0.02) with the cluster's -9 degree tilt. Numbers used: yS=2.467, zS=-1.80, h=0.44, ch=0.40, x=max(nav.X -0.01, minX 0.01)=0.01, giving (0.01, 2.567, -1.82). The screen then spans y 2.37-2.77 (hood top about 2.81) and stands 0.13 in front of the dash face (-1.95), clear of the new DashRoll (front -1.95). Remove CenterNeck and the 5 SCurve segments. Add SCurveDrop, a soft ellipsoid 0.13x0.56x0.24 at gx=cl.X+toC*(w/2+0.07)=-0.57, which fills the 0.14 gap between the cluster glass edge (-0.64) and the screen edge (-0.50); it spans y 2.22-2.78 with its front at z=-1.80. Add SCurveChin, a gloss ellipsoid 1.18x0.08x0.24 along the screen's bottom edge (y 2.30-2.38). Skip the screen-side ClusterCheek, since SCurveDrop replaces it. A float screen without sCurve keeps the old code (no other style uses float).",
   "code": "-- Cockpit.luau displays(): REPLACE lines 309-324 (from `ccf = CFrame.new(x, top + ch / 2 + 0.05, face - 0.06)` through the `end` of `if S.sCurve then ... end`) WITH:\n\t\tif S.sCurve then\n\t\t\t-- 쏘나타 DN8: 화면을 계기판과 같은 면 · 같은 높이에 (아래쪽이 대시에 묻힌 반통합 받침, 목 없음)\n\t\t\tccf = CFrame.new(x, yS + (h - ch) / 2 + 0.08, zS - 0.02) * CFrame.Angles(0, F.side * math.rad(6), 0) * tilt\n\t\t\tK:panel(\"CenterBack\", cw - 0.1, ch - 0.08, 0.14, 0.1, ccf * CFrame.new(0, 0, -0.09), P.hard)\n\t\t\t-- S자 테두리: 차양 오른쪽 끝이 두 화면 사이로 흘러내리고(드롭) 화면 아래 광택 턱으로 이어짐\n\t\t\tlocal gx = cl.X + toC * (w / 2 + 0.07)\n\t\t\tK:ell(\"SCurveDrop\", Vector3.new(0.13, h + 0.12, 0.24), CFrame.new(gx, yS + 0.03, zS - 0.12) * tilt, P.soft)\n\t\t\tK:ell(\"SCurveChin\", Vector3.new(cw + 0.16, 0.08, 0.24), ccf * CFrame.new(-toC * 0.04, -ch / 2 - 0.03, -0.08), P.gloss)\n\t\telse\n\t\t\tccf = CFrame.new(x, top + ch / 2 + 0.05, face - 0.06) * CFrame.Angles(0, F.side * math.rad(6), 0) * CFrame.Angles(math.rad(-6), 0, 0)\n\t\t\tK:panel(\"CenterBack\", cw - 0.1, ch - 0.08, 0.14, 0.1, ccf * CFrame.new(0, 0, -0.09), P.hard)\n\t\t\tK:panel(\"CenterNeck\", cw * 0.55, 0.14, 0.18, 0.06, ccf * CFrame.new(0, -ch / 2 - 0.02, -0.1), P.hard)\n\t\tend\n\n-- and the cheek loop (lines 295-297):\n\t\tfor _, s in { -1, 1 } do\n\t\t\tif not (S.sCurve and s == toC) then -- 쏘나타: 화면 쪽 볼은 SCurveDrop 이 대신\n\t\t\t\tK:ell(\"ClusterCheek\", Vector3.new(0.1, h * (if deep then 1.15 else 0.8), hd * 0.7), clCF * CFrame.new(s * (hw / 2 - 0.05), h * (if deep then 0.05 else 0.15), -hd * 0.3), P.soft)\n\t\t\tend\n\t\tend",
   "partsDelta": -10
  },
  {
   "rank": 2,
   "severity": "high",
   "area": "wheel",
   "observed": "sonata_1_driver and sonata_3_center: a bright light-grey vertical bar runs from the hub down to the rim at 6 o'clock, between our two V lower spokes. Cockpit vee4 builds nothing there. sonata_2_wheel and sonata_3_center: two dark legacy knobs flank the old '22.0' plate at y about 1.62, under our climate strip. A white plate shows behind the right edge of the screen, where the legacy nav sits (nav=(-0.01,2.60,-2.14), navW=1.30). These are old Interior parts whose names are not in REPLACES. The place's string table lists car-ish names such as Spoke, Column, Knob, Dial, Tablet, KneePad, HazardBand, VentCap and ScreenHousing, so a name list will keep missing some.",
   "real": "The DN8 wheel has an open gap at 6 o'clock between the two lower spokes. The stack has only the small AVN volume and tune knobs and the two knurled temperature dials.",
   "fix": "init.client.luau: hide legacy parts by volume as well as by name. Any old BasePart (not Seat or VehicleSeat; names containing Taxi, Meter or Police are kept, so taxi meters and police gear survive) is hidden if it sits in either volume. Volume 1 is the steering-wheel disc: |local Z|<0.3 and radius < R+0.06 (0.73). Volume 2 is the dash-front slab the cabin fully rebuilds. For Sonata that is |x|<halfIn 2.56, y between dashBottom-0.15 and dashTop+0.5 (1.34-3.00), and z between dashFront+0.1 and dashFace+0.35 (-3.03 to -1.60). Pedals (y about 0.7), mirror and visors (y>3.0) and seats fall outside it. SurfaceGuis on those parts are parked in the same way. This is a generic change: every style rebuilds the whole dash and wheel.",
   "code": "-- init.client.luau: INSERT above `local function hideOld` (line 282):\n-- 이름이 달라 REPLACES 에 없는 옛 실내 파트도, 새 핸들 원판 · 대시 앞면 부피 안에 있으면 숨김 (택시 미터 · 경찰 장비는 유지)\nlocal function insideNew(cab: any, p: Instance): boolean\n\tif not p:IsA(\"BasePart\") or string.find(p.Name, \"Taxi\") or string.find(p.Name, \"Meter\") or string.find(p.Name, \"Police\") then\n\t\treturn false\n\tend\n\tlocal F = cab.fit\n\tlocal lp = cab.base.CFrame:PointToObjectSpace((p :: BasePart).Position)\n\tlocal w = F.wheel.cf:PointToObjectSpace(lp)\n\tif math.abs(w.Z) < 0.3 and Vector2.new(w.X, w.Y).Magnitude < F.wheel.R + 0.06 then\n\t\treturn true\n\tend\n\treturn math.abs(lp.X) < F.halfIn and lp.Y > F.dashBottom - 0.15 and lp.Y < F.dashTop + 0.5 and lp.Z > F.dashFront + 0.1 and lp.Z < F.dashFace + 0.35\nend\n\n-- in hideOld: old -> new\n-- if d:IsA(\"BasePart\") and REPLACES[d.Name] and not d:IsA(\"Seat\") ...\n-- ->\n\tif d:IsA(\"BasePart\") and (REPLACES[d.Name] or insideNew(cab, d)) and not d:IsA(\"Seat\") and not d:IsA(\"VehicleSeat\") then\n-- elseif d:IsA(\"SurfaceGui\") and d.Parent and REPLACES[d.Parent.Name] and cab.guis[d] == nil then\n-- ->\n\telseif d:IsA(\"SurfaceGui\") and d.Parent and (REPLACES[d.Parent.Name] or insideNew(cab, d.Parent)) and cab.guis[d] == nil then",
   "partsDelta": 0
  },
  {
   "rank": 3,
   "severity": "high",
   "area": "center screen",
   "observed": "sonata_3_center and sonata_4_dash: the centre stack is a 1.28-wide piano-black slab (StackBack, P.gloss) running from the console top (1.53) to 2.18. It stands 0.04 proud of the dash and has knobs at all four corners, so it reads as an aftermarket 2-DIN radio box, which is exactly the boxy look the user dislikes. The two centre vents above it (y 2.26) were half-buried and only their lower chrome arcs show.",
   "real": "The DN8 stack is narrow and belongs to the soft dash. Right under the screen are two slim horizontal vents with the hazard switch between them. Below them is a slim gloss AVN key strip with satin trim and small volume and tune knobs at its ends, then the gloss climate strip with diamond-knurled dials at each end. The surround is soft-touch dash material that narrows into the console, with the wireless-charging tray at its foot.",
   "fix": "Dash.luau Dash.build, g==\"line\" branch. Set vy = min(top-0.24, scrY-ch/2-0.19); with the issue-1 screen (scrY 2.567) that gives 2.177, so the vents are not hidden under the SCurveChin (bottom 2.297). Without issue 1 it stays 2.26. Move the vents to cx±0.28 with width 0.44 so they span ±0.50, matching the screen width and clearing SCurveDrop at x=-0.57. StackBack becomes P.soft, 1.3 wide, and covers only the AVN and climate rows (y 1.677-2.097). Add StackLower, P.soft, width con.w+0.06=0.96, from conTop 1.53 to 1.737, so the stack narrows into the console. Add a satin AvnTrim under the key strip. Climate moves to cyc=ky-0.2=1.807 (strip 1.70-1.92). The chrome line (y 2.05) and ambient strip end inside the stack.",
   "code": "-- Dash.luau, g == \"line\": REPLACE lines 233-236 WITH:\n\t\tlocal vy = math.min(top - 0.24, scrY - ch / 2 - 0.19) -- 내려온 화면 턱 아래 (가리지 않게)\n\t\tfor _, s in { -1, 1 } do\n\t\t\tvent(K, P, \"CentreVent\", CFrame.new(cx + s * 0.28, vy, face + 0.01), 0.44, 0.1)\n\t\tend\n-- REPLACE lines 243-246 (sy0/sy1, StackBack, ky, AvnKeys) WITH:\n\t\t-- 스택 둘레는 대시와 같은 소프트 패드: 위(AVN · 공조 폭 1.3) -> 아래는 콘솔 폭으로 좁아짐. 광택은 키 · 공조 띠만\n\t\tlocal ky = vy - 0.17\n\t\tlocal cyc = ky - 0.2\n\t\tlocal sTop, sMid = vy - 0.08, cyc - 0.13\n\t\tK:panel(\"StackBack\", 1.3, sTop - sMid, 0.06, 0.1, CFrame.new(cx, (sTop + sMid) / 2, face), P.soft)\n\t\tlocal lw = (if con then math.min(con.w, 1.15) else 0.9) + 0.06\n\t\tK:panel(\"StackLower\", lw, sMid - conTop + 0.06, 0.06, 0.08, CFrame.new(cx, (sMid + conTop) / 2 + 0.03, face - 0.005), P.soft)\n\t\tK:panel(\"AvnKeys\", 1.0, 0.1, 0.04, 0.045, CFrame.new(cx, ky, face + 0.05), P.gloss)\n\t\tK:cyl(\"AvnTrim\", 1.04, 0.016, CFrame.new(cx, ky - 0.062, face + 0.05), P.satin)\n-- line 251: climate(K, F, P, S, cx, ky - 0.2, face + 0.07)  ->\n\t\tclimate(K, F, P, S, cx, cyc, face + 0.07)",
   "partsDelta": 7
  },
  {
   "rank": 4,
   "severity": "medium",
   "area": "doors",
   "observed": "sonata_4_dash and sonata_3_center (passenger door): the dash's satin line (y=mid+0.1=2.05) and ambient strip (2.005) reach the door, but the door band sits at upY0+0.1=1.846 and the door ambient at 1.776. That is 0.2 lower, so the 'door-to-door' line visibly steps down at the A-pillar.",
   "real": "The DN8's thin satin-chrome line, with the mood-light strip just under it, runs continuously from the dash into both doors at one height. This is a signature feature.",
   "fix": "Trim.luau doorCard, gated by g==\"line\": lineY = clamp(dashMidY+0.1, upY0+0.06, y1-0.08) = 2.05, which falls inside the door's upper pad (1.746-2.575). The door ambient goes to lineY-0.045 = 2.005. The door band at x=±2.52 comes out of the dash end roll (front z -1.92) at the same height where the dash line ends (x=±2.48). Other garnishes keep upY0-based heights.",
   "code": "-- Trim.luau doorCard: line 41-42 old -> new\n\t-- 쏘나타: 대시의 새틴 라인 · 앰비언트와 같은 높이로 문까지 끊김 없이\n\tlocal lineY = if g == \"line\" then math.clamp((F.dashMidY :: number) + 0.1, upY0 + 0.06, y1 - 0.08) else upY0 + 0.1\n\tif g == \"line\" then\n\t\tK:cyl(\"DoorTrimBand\", len - 0.4, 0.03, CFrame.new(x + inward * 0.06, lineY, zc) * AZ, P.trim)\n-- line 55 old -> new\n\t\tK:cyl(\"DoorAmbient\", len - 0.6, 0.02, CFrame.new(x + inward * 0.07, if g == \"line\" then lineY - 0.045 else upY0 + 0.03, zc) * AZ, P.ambient)",
   "partsDelta": 0
  },
  {
   "rank": 5,
   "severity": "medium",
   "area": "doors",
   "observed": "sonata_1_driver (left door): the door armrest and gloss window-switch pad sit at armY=y0+lowH+0.02=1.30, level with the seat cushion top (0.99+0.24=1.23). Above them is a 0.83-tall flat, empty upper door wall (DoorUpper 1.746-2.575), so the door looks like a slab with the armrest on the floor.",
   "real": "The DN8 front door armrest sits about 15 cm (0.5 stud) above the cushion and carries the gloss window-switch panel. The chrome pull handle is in a recessed cup above it near the satin line, with the driver's IMS 1/2/SET buttons next to the handle.",
   "fix": "Trim.luau doorCard, generic: take armY from the cushion of the seat on that door's side, clamped inside the door. Sonata front: 1.23+0.5=1.73; rear bench: 1.28+0.5=1.78; clamp range [1.296, 1.955]. G80 gets 1.79. The handle moves to hy=armY+0.45=2.18 (cup 2.09-2.27, clear of the line at 2.035-2.065). IMS moves to hy-0.24=1.94, between the armrest top (1.795) and the ambient strip (1.995). Armrest inner edge 2.20 vs seat outer edge 2.10, so there is no seat clash.",
   "code": "-- Trim.luau doorCard: line 58\n-- local armY = y0 + lowH + 0.02  ->\n\t-- 팔걸이: 그 문 쪽 좌석 쿠션 위 0.5 (팔꿈치 높이). 이전엔 쿠션과 같은 높이였음\n\tlocal cushTop = y0 + lowH\n\tfor _, s in (if front then F.front else F.rear) do\n\t\tif s.w >= 2.6 or (s.x < 0) == (side < 0) then\n\t\t\tcushTop = s.cush.Y + s.cushSize.Y / 2\n\t\tend\n\tend\n\tlocal armY = math.clamp(cushTop + 0.5, y0 + lowH + 0.02, y1 - 0.62)\n-- line 68: local hy = armY + 0.42  ->\n\tlocal hy = armY + 0.45\n-- line 75 (ImsButton): CFrame.new(x + inward * 0.08, hy - 0.14, hz - 0.1 + i * 0.09)  ->  CFrame.new(x + inward * 0.08, hy - 0.24, hz - 0.1 + i * 0.09)",
   "partsDelta": 0
  },
  {
   "rank": 6,
   "severity": "medium",
   "area": "cluster",
   "observed": "sonata_3_center and sonata_4_dash: the cluster housing is a flat-sided 1.34x0.54x0.42 box (ClusterBack panel) with a separate dome hood on top. From the passenger side you see its square back corners and a lit flat side face, so the cluster looks like a small TV set on the dash.",
   "real": "On the DN8 the 12.3in cluster sits under a slim, low, rounded hood that blends smoothly into the dash pad. There is no visible box behind it.",
   "fix": "Cockpit.luau displays(), line 283: when hood==\"slim\" (Sonata and taxi only), replace the box with one ellipsoid pod (w+0.14) x (h+0.14) x 0.7 at clCF*(0,0.02,-0.37). Its tip is at -0.02, just behind the bezel (bezel back -0.027), and its back half is buried in the dash (world z down to about -2.5). Above the dash top (2.5) it shows as a smooth dome that merges with the hood ellipsoid. Saves 5 parts.",
   "code": "-- Cockpit.luau line 283: old -> new\n\t\tif hoodKind == \"slim\" then\n\t\t\t-- 쏘나타: 각진 상자 대신 둥근 포드 (앞 끝은 베젤 바로 뒤, 뒤쪽 절반은 대시 속)\n\t\t\tK:ell(\"ClusterBack\", Vector3.new(w + 0.14, h + 0.14, 0.7), clCF * CFrame.new(0, 0.02, -0.37), P.soft)\n\t\telse\n\t\t\tK:panel(\"ClusterBack\", w + 0.12, h + 0.1, 0.42, 0.12, clCF * CFrame.new(0, 0.02, -0.22), P.hard)\n\t\tend",
   "partsDelta": -5
  },
  {
   "rank": 7,
   "severity": "medium",
   "area": "wheel",
   "observed": "sonata_2_wheel: the airbag is a deep ellipsoid dome (hub 0.5x0.4x0.18 on a 0.56x0.45 shell), so the centre reads as a round black ball with the H badge floating on it.",
   "real": "The DN8 hub is a medium rounded-rectangle (soft trapezoid) pad with a nearly flat face and the chrome slanted-H badge in the middle.",
   "fix": "Cockpit.luau wheel(), line 94-98, kind==\"vee4\" only: a rounded-rect panel hub.X x hub.Y (0.5x0.4), depth 0.08, r 0.13, at W*(0,hy,0.07) (front 0.11), plus a shallow dome 0.46x0.36x0.12 at z 0.085 (front 0.145). The emblem stays at z 0.152, just in front of the dome. The side spokes (start x=0.2) and lower spokes (start y=-0.198) still begin inside the pad.",
   "code": "-- Cockpit.luau wheel(): old\n\t\tif kind == \"three\" then\n\t\t\tK:rbox(\"Airbag\", Vector3.new(hub.Z, hub.Y, hub.X), 0.1, W * CFrame.new(0, hy, 0.06) * ROT_X_TO_Z, P.wheelHub)\n\t\telse\n-- new\n\t\tif kind == \"three\" then\n\t\t\tK:rbox(\"Airbag\", Vector3.new(hub.Z, hub.Y, hub.X), 0.1, W * CFrame.new(0, hy, 0.06) * ROT_X_TO_Z, P.wheelHub)\n\t\telseif kind == \"vee4\" then\n\t\t\t-- 쏘나타: 둥근 사각 패드 (평평한 앞면 + 얕은 돔, 엠블럼은 돔 바로 앞)\n\t\t\tK:panel(\"Airbag\", hub.X, hub.Y, 0.08, 0.13, W * CFrame.new(0, hy, 0.07), P.wheelHub)\n\t\t\tK:ell(\"AirbagDome\", Vector3.new(hub.X - 0.04, hub.Y - 0.04, 0.12), W * CFrame.new(0, hy, 0.085), P.wheelHub)\n\t\telse",
   "partsDelta": 6
  },
  {
   "rank": 8,
   "severity": "medium",
   "area": "dash",
   "observed": "sonata_2_wheel and sonata_3_center: a red disc pokes out between the AVN key row and the climate strip on the left side of the stack. StartRing/StartButton is at x = W.X+(R+0.32) = -0.26, y = mid+0.05 = 2.0, which is inside the 1.28-wide stack (x ±0.64). Away from the stack it would also float 0.11 in front of the lower dash, because the lower dash is recessed 0.08 behind dashFace.",
   "real": "The DN8 ENGINE START/STOP button is a separate chrome-ringed round button. It is not buried in, or clipping through, the AVN and climate panels.",
   "fix": "Cockpit.build, generic: keep the button outside the stack: offset = min(R+0.32, |cx-W.X|-0.86), giving x=-0.86 (stack half-width 0.65 + ring 0.1 + margin). Set y = dashMidY-0.12 = 1.83 (below the chrome line and ambient strip at 1.995-2.065, above the knee panel at about 1.58). Set z = dashFace-0.06 = -2.01 so the ring sits on the recessed DashLower face (-2.03). This also clears the Tucson stack (half-width 0.75) and the Ray pod.",
   "code": "-- Cockpit.luau line 357: old\n-- local sb = CFrame.new(W.Position.X - F.side * (F.wheel.R + 0.32), F.dashMidY + 0.05, F.dashFace + 0.03)\n-- new\n\t\t-- 센터 스택(반폭 ~0.65 + 테두리) 바깥, 크롬 라인 아래 대시 아랫면(대시 면보다 0.08 안쪽)에 붙임\n\t\tlocal scx = if F.console then F.console.x else 0\n\t\tlocal off = math.min(F.wheel.R + 0.32, math.abs(scx - W.Position.X) - 0.86)\n\t\tlocal sb = CFrame.new(W.Position.X - F.side * off, F.dashMidY - 0.12, F.dashFace - 0.06)",
   "partsDelta": 0
  },
  {
   "rank": 9,
   "severity": "medium",
   "area": "console",
   "observed": "sonata_1_driver and sonata_3_center: the two cupholders and the palm rest read as three raised black hockey pucks. Each cup's 0.27 dark disc has its top at deck+0.0125, higher than its chrome ring (deck+0.005). That hides the ring and exposes the disc's lit side wall.",
   "real": "The DN8 has two round, recessed cupholders with a thin bright rim beside the P/R/N/D column, and a low padded rest. They read as holes, not discs.",
   "fix": "Console.luau cupholders(), generic for every console that uses it: draw the cup as concentric bands, outermost to innermost: a satin rim (d 0.31, top deck+0.017), a dash-colour inner wall band (d 0.28), and a black bottom (d 0.20). Each band is stepped up only 0.002 to avoid z-fighting, so no side walls show and the colour gradient reads as a recess. Optional: make PalmRest a lower, longer pad so it stops reading as a third puck. At the new size it ends at gz+0.87 = -0.25, before the armrest.",
   "code": "-- Console.luau cupholders(): lines 35-36 old -> new\n\t\t-- 오목해 보이게: 새틴 테두리(바깥) -> 대시색 안쪽 벽 띠 -> 검은 바닥 (0.002 씩만 위로: z-fighting 방지, 옆면이 안 보임)\n\t\tK:cyl(\"CupholderRing\", 0.03, 0.31, c * CFrame.new(0, 0.012, 0) * ROT_X_TO_Y, P.satin)\n\t\tK:cyl(\"CupholderWall\", 0.03, 0.28, c * CFrame.new(0, 0.014, 0) * ROT_X_TO_Y, P.hard)\n\t\tK:cyl(\"Cupholder\", 0.03, 0.2, c * CFrame.new(0, 0.016, 0) * ROT_X_TO_Y, P.duct)\n-- optional, line 130 (buttons_col):\n\t\tK:ell(\"PalmRest\", Vector3.new(0.3, 0.08, 0.5), CFrame.new(gx, top + 0.03, gz + 0.62), P.leather)",
   "partsDelta": 2
  },
  {
   "rank": 10,
   "severity": "low",
   "area": "wheel",
   "observed": "sonata_1_driver and sonata_3_center: the two lower V spokes are thin round dark rods (seg d=0.08) with a thinner satin rod floating 0.04 in front. From the driver's seat they look like wire struts.",
   "real": "The DN8's lower spokes are flat, narrow blades with a satin-chrome face, splayed to about 5 and 7 o'clock.",
   "fix": "Cockpit.luau wheel(), vee4 only: use the same endpoints a and b. Replace the rod with a flat box blade (length |b-a| about 0.45, width 0.1, thickness 0.045), oriented with X along the spoke and Z toward the driver (W.ZVector), plus a 0.055-wide satin face 0.026 in front. Other spoke kinds keep the seg and trim. Part count is unchanged.",
   "code": "-- Cockpit.luau wheel(), lines 136-141: old\n--\tK:seg(\"LowerSpoke\", a, b, 0.08, P.hard)\n--\tif ws.lowerTrim then\n-- new\n\t\t\t\tif kind == \"vee4\" then\n\t\t\t\t\t-- 쏘나타: 둥근 막대 대신 납작한 블레이드 + 운전자 쪽 새틴 면\n\t\t\t\t\tlocal dir = (b - a).Unit\n\t\t\t\t\tlocal bcf = CFrame.fromMatrix((a + b) / 2, dir, W.ZVector:Cross(dir).Unit)\n\t\t\t\t\tK:box(\"LowerSpoke\", Vector3.new((b - a).Magnitude, 0.1, 0.045), bcf, P.hard)\n\t\t\t\t\tK:box(\"LowerSpokeTrim\", Vector3.new((b - a).Magnitude - 0.08, 0.055, 0.012), bcf * CFrame.new(0, 0, 0.026), P.satin)\n\t\t\t\telse\n\t\t\t\t\tK:seg(\"LowerSpoke\", a, b, 0.08, P.hard)\n\t\t\t\tend\n\t\t\t\tif ws.lowerTrim and kind ~= \"vee4\" then",
   "partsDelta": 0
  },
  {
   "rank": 11,
   "severity": "low",
   "area": "shifter",
   "observed": "sonata_1_driver and sonata_3_center: the selected 'P' button is a whole 0.11 white Neon disc (buttonLit), the brightest object on the console. It reads as a glowing blob rather than a shift button.",
   "real": "The DN8 P/R/N/D buttons are dark buttons with chrome rings. The selected gear shows only a small indicator light (plus the lit letter).",
   "fix": "Console.luau ringButton(), generic (also affects Tucson's buttons_row): the cap is always P.button, and a lit gear adds a 0.03x0.018 Neon LED at the front edge of the cap top (y +0.033, z -(d/2-0.035)).",
   "code": "-- Console.luau ringButton(), line 29: old -> new\n\tK:cyl(\"ShiftButton\", 0.04, d - 0.03, cf * CFrame.new(0, 0.012, 0) * ROT_X_TO_Y, P.button)\n\tif lit then\n\t\t-- 선택된 단: 버튼 전체가 아니라 앞쪽 작은 표시등만\n\t\tK:box(\"ShiftLed\", Vector3.new(0.03, 0.006, 0.018), cf * CFrame.new(0, 0.033, -(d / 2 - 0.035)), P.buttonLit)\n\tend",
   "partsDelta": 1
  }
 ]
}
```

## critique:sonata_taxi

```json
{
 "car": "Hyundai Sonata DN8 LPi taxi (Korean 개인택시), style key \"sonata_taxi\"",
 "summary": "The render has the right DN8 base: a low wing dash with the satin line, a 4-spoke wheel, a twin analog dial cluster with an LCD between the dials, and a lever console. It still reads as a slightly retro generic Sonata rather than a Busan 개인택시, because none of the taxi equipment exists (mirror meter, 빈차 sign, driver ID card, card terminal). The biggest visual gaps are: the centre vents, hazard switch and side vents are half-buried in the dash roll; the wheel has a dome-shaped hub and rod-like lower spokes; the lever looks like a joystick; the S-curve reads as a black hose; and a white map line runs past the edge of the screen.",
 "issues": [
  {
   "rank": 1,
   "severity": "high",
   "area": "vents",
   "observed": "taxi_3_center, taxi_1_driver, taxi_4_dash: under the screen, only the lower chrome lips of the two centre vents show, as white 'brackets'. The red hazard switch is a thin sliver, and both wing-tip side vents are cut off at the top. The upper halves are inside the DashRoll cylinder.",
   "real": "Two slim horizontal vents sit fully visible directly under the screen, with the hazard switch between them. Slim rectangular side vents sit in the wing tips just above the satin line.",
   "fix": "File: Dash.luau, function Dash.build, branch `g == \"line\"` (applies to sonata and sonata_taxi). DashRoll is a cylinder of diameter 0.26 centred at (y = top-0.13, z = face), so it fills y 2.25..2.51 at the dash face (taxi top = 2.51). Today's positions: CentreVent rim at vy±0.085 = 2.185..2.355, Hazard at 2.225..2.315, SideVent rim at (ly+0.17)±0.095 = 2.125..2.315. All three sit inside the roll. Fix: set rollBot = top-0.26 (2.25) and vy = rollBot-0.095 = 2.155, which puts the rim at 2.07..2.24. Centre each side vent between the top of the chrome line (ly+0.015 = 2.065) and rollBot, with h = min(0.12, 2.25-2.065-0.075) = 0.11, giving a rim of 2.068..2.248. Everything below moves down 0.12: StackBack top = vy-0.09 = 2.065, AVN row ky = 1.985, climate strip y = 1.785 (spans 1.675..1.895, still above conTop 1.54). Sonata (top 2.50) gives the same result.",
   "code": "-- Dash.luau, Dash.build, inside `if g == \"line\" then`\n-- OLD:\n\t\tlocal vy = top - 0.24\n\t\tfor _, s in { -1, 1 } do\n\t\t\tvent(K, P, \"CentreVent\", CFrame.new(cx + s * 0.31, vy, face + 0.01), 0.48, 0.1)\n\t\tend\n\t\tK:box(\"Hazard\", Vector3.new(0.09, 0.09, 0.04), CFrame.new(cx, vy, face + 0.03), P.hazard)\n\t\t-- 끝 송풍구 (날개 끝, 크롬 라인 위)\n\t\tfor _, s in { -1, 1 } do\n\t\t\tvent(K, P, \"SideVent\", CFrame.new(s * (half - 0.38), ly + 0.17, face + 0.01), 0.46, 0.12)\n\t\tend\n\t\t-- 좁은 스택: AVN 단축키 + 작은 노브 2 -> 공조 띠\n\t\tlocal sy0, sy1 = conTop, vy - 0.08\n-- NEW:\n\t\t-- DashRoll(지름 0.26, 중심 y = top - 0.13)이 대시 앞면 y = top-0.26 .. top 을 차지 -> 송풍구 · 비상등은 그 아래\n\t\tlocal rollBot = top - 0.26\n\t\tlocal vy = rollBot - 0.095 -- 테두리 높이 0.1 + 2*0.035 의 절반 + 여유\n\t\tfor _, s in { -1, 1 } do\n\t\t\tvent(K, P, \"CentreVent\", CFrame.new(cx + s * 0.31, vy, face + 0.01), 0.48, 0.1)\n\t\tend\n\t\tK:box(\"Hazard\", Vector3.new(0.09, 0.07, 0.04), CFrame.new(cx, vy, face + 0.03), P.hazard)\n\t\t-- 끝 송풍구: 크롬 라인 윗면(ly + 0.015)과 DashRoll 사이에 꼭 맞게\n\t\tlocal svh = math.min(0.12, rollBot - (ly + 0.015) - 0.075)\n\t\tfor _, s in { -1, 1 } do\n\t\t\tvent(K, P, \"SideVent\", CFrame.new(s * (half - 0.38), (rollBot + ly + 0.015) / 2, face + 0.01), 0.46, svh)\n\t\tend\n\t\t-- 좁은 스택: AVN 단축키 + 작은 노브 2 -> 공조 띠\n\t\tlocal sy0, sy1 = conTop, vy - 0.09",
   "partsDelta": 0
  },
  {
   "rank": 2,
   "severity": "high",
   "area": "other",
   "observed": "taxi_1_driver, taxi_5_night: the rear-view mirror is a plain dark glass. No fare meter appears on the mirror, dash or console, so nothing in the cabin says 개인택시.",
   "real": "Korean personal taxis usually carry a mirror-type meter (룸미러 일체형 미터기). The mirror glass shows the fare in red LED digits (Busan base fare 4,800 won) with a status lamp, and a row of 빈차/주행/할증/지불 keys runs along the mirror's lower edge.",
   "fix": "File: Trim.luau. Add `local Gauges = require(...)` at the top. In Trim.build, right after MirrorGlass, add a block gated by `F.style.key == \"sonata_taxi\" and F.kind ~= \"police\"` so the police car shares the style without the meter. Coordinates are local to mcf (mirror body 0.86×0.25×0.1; glass 0.78×0.18 at z 0.055, front face at 0.060). Meter window 0.32×0.10 on the passenger half at x = -F.side*0.17, y -0.025, z 0.062. Four 7-segment digits 0.06 high (pitch 0.048, about ±0.089 wide) centred 0.03 inboard. A green status LED sits 0.12 to the other side. Four keys 0.07×0.025 at y -0.13 (just under the rounded body bottom at -0.125) and x -0.27..0.27. Uses the existing P.ledRed, P.ledGreen and P.button.",
   "code": "-- Trim.luau, top (after `local Trim = {}`):\nlocal Gauges = require(script.Parent:WaitForChild(\"Gauges\"))\n\n-- Trim.build, right after K:box(\"MirrorGlass\", ...):\n\t-- 개인택시 룸미러 일체형 미터기 (순찰차 제외): 거울 조수석 쪽 절반에 빨간 LED 요금 + 초록 상태등,\n\t-- 거울 아래 가장자리에 빈차 · 주행 · 할증 · 지불 버튼\n\tif F.style.key == \"sonata_taxi\" and F.kind ~= \"police\" then\n\t\tlocal mm = mcf * CFrame.new(-F.side * 0.17, -0.025, 0.062)\n\t\tK:box(\"MeterWindow\", Vector3.new(0.32, 0.1, 0.004), mm, { c = Color3.fromRGB(16, 5, 5) })\n\t\tGauges.digits(K, mm * CFrame.new(-F.side * 0.03, 0, 0.004), 4, 0.06, P.ledRed, \"4800\")\n\t\tK:box(\"MeterLed\", Vector3.new(0.03, 0.03, 0.006), mm * CFrame.new(F.side * 0.12, 0, 0.004), P.ledGreen)\n\t\tfor i = 0, 3 do\n\t\t\tK:box(\"MeterKey\", Vector3.new(0.07, 0.025, 0.05), mcf * CFrame.new(-0.27 + i * 0.18, -0.13, 0.02), P.button)\n\t\tend\n\tend",
   "partsDelta": 29
  },
  {
   "rank": 3,
   "severity": "high",
   "area": "wheel",
   "observed": "taxi_2_wheel and taxi_1_driver: the airbag is a deep ellipsoid dome (0.5×0.4×0.18) that reads as a black ball. The two lower spokes are thin 0.08 rods with rod-shaped satin trim on top, so the wheel looks like a 1980s rod-spoke wheel.",
   "real": "The DN8 has a flat, soft rounded-rectangle airbag pad with the chrome slanted-H badge. The two lower spokes are flat blades about 3-4 cm wide in a narrow inverted V meeting the rim at about 5 and 7 o'clock, with a satin strip running down each.",
   "fix": "File: Cockpit.luau, function wheel(), gated by `kind == \"vee4\"` (sonata and sonata_taxi only; u4/two/three/bus2 are unchanged). Hub: replace the ellipsoid with an rbox of depth 0.1, size hub.Y×hub.X (0.4×0.5), corner radius 0.13 seen from the front, at W z 0.05. Add a shallow crown ellipsoid 0.46×0.36×0.09 at z 0.105, so the front stays at 0.15 and the emblem at z 0.152 still sits proud. Lower spokes: keep the same a/b endpoints (a = W(±0.075, -0.198), b at R-0.03 = 0.64 and ±58°, length about 0.434). Build each as a flat rbox (len+0.02, width 0.12, thickness 0.06, long edges rounded r 0.028) in a frame with X along a→b and Z = W.ZVector. Add a 0.024-wide satin strip (len-0.12) on its face at z 0.032, offset 0.03 toward the rim.",
   "code": "-- Cockpit.luau, wheel(). OLD:\n\t\tif kind == \"three\" then\n\t\t\tK:rbox(\"Airbag\", Vector3.new(hub.Z, hub.Y, hub.X), 0.1, W * CFrame.new(0, hy, 0.06) * ROT_X_TO_Z, P.wheelHub)\n\t\telse\n\t\t\tK:ell(\"Airbag\", hub, W * CFrame.new(0, hy, 0.06), P.wheelHub)\n\t\tend\n-- NEW:\n\t\tif kind == \"three\" then\n\t\t\tK:rbox(\"Airbag\", Vector3.new(hub.Z, hub.Y, hub.X), 0.1, W * CFrame.new(0, hy, 0.06) * ROT_X_TO_Z, P.wheelHub)\n\t\telseif kind == \"vee4\" then\n\t\t\t-- 쏘나타 DN8: 공 모양 돔이 아니라 납작한 둥근 사각 패드 (앞에서 본 모서리 r 0.13) + 얕은 크라운\n\t\t\tK:rbox(\"Airbag\", Vector3.new(0.1, hub.Y, hub.X), 0.13, W * CFrame.new(0, hy, 0.05) * ROT_X_TO_Z, P.wheelHub)\n\t\t\tK:ell(\"AirbagCrown\", Vector3.new(hub.X - 0.04, hub.Y - 0.04, 0.09), W * CFrame.new(0, hy, 0.105), P.wheelHub)\n\t\telse\n\t\t\tK:ell(\"Airbag\", hub, W * CFrame.new(0, hy, 0.06), P.wheelHub)\n\t\tend\n\n-- Same function, lower spokes. OLD:\n\t\t\t\tK:seg(\"LowerSpoke\", a, b, 0.08, P.hard)\n\t\t\t\tif ws.lowerTrim then\n\t\t\t\t\tlocal a2 = (W * CFrame.new(s * 0.075, hy - hub.Y * 0.42, 0.04)).Position\n\t\t\t\t\tlocal b2 = (W * CFrame.new(math.cos(t) * (R - 0.08), math.sin(t) * (R - 0.08), 0.03)).Position\n\t\t\t\t\tK:seg(\"LowerSpokeTrim\", a2, b2, 0.032, if ws.lowerTrim == \"gloss\" then P.gloss else P.satin)\n\t\t\t\tend\n-- NEW:\n\t\t\t\tif kind == \"vee4\" then\n\t\t\t\t\t-- 쏘나타: 막대가 아니라 납작한 판 스포크 (폭 0.12 · 두께 0.06, 긴 모서리 둥글게) + 가운데 새틴 띠\n\t\t\t\t\tlocal zA = W.ZVector\n\t\t\t\t\tlocal yv = zA:Cross(b - a).Unit\n\t\t\t\t\tlocal spf = CFrame.fromMatrix((a + b) / 2, yv:Cross(zA), yv, zA)\n\t\t\t\t\tlocal sl = (b - a).Magnitude\n\t\t\t\t\tK:rbox(\"LowerSpoke\", Vector3.new(sl + 0.02, 0.12, 0.06), 0.028, spf, P.hard)\n\t\t\t\t\tK:box(\"LowerSpokeTrim\", Vector3.new(sl - 0.12, 0.024, 0.01), spf * CFrame.new(0.03, 0, 0.032), P.satin)\n\t\t\t\telse\n\t\t\t\t\tK:seg(\"LowerSpoke\", a, b, 0.08, P.hard)\n\t\t\t\t\tif ws.lowerTrim then\n\t\t\t\t\t\tlocal a2 = (W * CFrame.new(s * 0.075, hy - hub.Y * 0.42, 0.04)).Position\n\t\t\t\t\t\tlocal b2 = (W * CFrame.new(math.cos(t) * (R - 0.08), math.sin(t) * (R - 0.08), 0.03)).Position\n\t\t\t\t\t\tK:seg(\"LowerSpokeTrim\", a2, b2, 0.032, if ws.lowerTrim == \"gloss\" then P.gloss else P.satin)\n\t\t\t\t\tend\n\t\t\t\tend",
   "partsDelta": 16
  },
  {
   "rank": 4,
   "severity": "high",
   "area": "shifter",
   "observed": "taxi_1_driver, taxi_3_center, taxi_4_dash: a thin black 0.06 stick rises about 0.3 out of a small puck boot to a ball knob with a glowing white chrome band, so it reads as an arcade joystick. Four identical white LED squares sit beside it.",
   "real": "The DN8 LPi taxi uses a conventional 6AT floor lever. A tall leather knob with a satin strip and a side release button sits directly on a tapered leather boot gathered by a satin collar, so no stem is visible. A P-R-N-D indicator beside the gate has only the current gear lit.",
   "fix": "File: Console.luau, Console.build, branch `kind == \"lever\"` (used only by sonata_taxi). Taxi numbers: top = 1.58, gz = zU + L*0.42 = -1.115. Remove ShiftStick and the chrome ShiftKnobBand. Add: a satin collar disc (d 0.32) on the gate plate at y top+0.022; a lower boot ellipsoid 0.26×0.22×0.3 at y +0.07 (1.54..1.76); a boot neck 0.13×0.28×0.15 at y +0.20 (1.64..1.92); and a taller knob 0.15×0.27×0.20 at y +0.40 (1.85..2.11, same top as before), tilted 8° toward the driver. Add a satin spine on the knob's rear face (0.035×0.12, flush at z 0.095) and the release button on the driver-side flank (side*0.072). Move the gate marks to side*0.18 so they clear the collar; only P is lit (P.markWhite) and R/N/D use P.button.",
   "code": "-- Console.luau, Console.build. Replace the whole `elseif kind == \"lever\" then` body:\n\telseif kind == \"lever\" then\n\t\t-- 택시 · 순찰차: 6단 레버. 가죽 부츠가 노브 밑까지 감싸 막대가 안 보이고(조이스틱 X), 세로로 긴 가죽 노브 +\n\t\t-- 뒤쪽 새틴 띠 + 운전석 쪽 시프트 락 버튼, 부츠 밑 새틴 칼라, 운전석 쪽 P R N D 표시 (주차 중 P 만 켜짐)\n\t\tlocal gz = zU + L * 0.42\n\t\tlocal b = CFrame.new(x, top, gz)\n\t\tK:slab(\"GatePlate\", 0.42, 0.6, 0.03, 0.12, b, P.gloss)\n\t\tfor i = 0, 3 do\n\t\t\tK:box(\"GateMark\", Vector3.new(0.04, 0.006, 0.03), b * CFrame.new(side * 0.18, 0.02, -0.19 + i * 0.12), if i == 0 then P.markWhite else P.button)\n\t\tend\n\t\tK:cyl(\"BootCollar\", 0.016, 0.32, b * CFrame.new(0.02, 0.022, 0.01) * ROT_X_TO_Y, P.satin)\n\t\tK:ell(\"ShiftBoot\", Vector3.new(0.26, 0.22, 0.3), b * CFrame.new(0.02, 0.07, 0.01), P.leather)\n\t\tK:ell(\"ShiftBootNeck\", Vector3.new(0.13, 0.28, 0.15), b * CFrame.new(0.02, 0.2, 0.03), P.leather)\n\t\tlocal kn = b * CFrame.new(0.02, 0.4, 0.05) * CFrame.Angles(math.rad(8), 0, 0)\n\t\tK:ell(\"ShiftKnob\", Vector3.new(0.15, 0.27, 0.2), kn, P.leather)\n\t\tK:box(\"ShiftKnobSpine\", Vector3.new(0.035, 0.12, 0.016), kn * CFrame.new(0, 0.02, 0.095), P.satin)\n\t\tK:box(\"ShiftLock\", Vector3.new(0.03, 0.06, 0.06), kn * CFrame.new(side * 0.072, 0.02, 0), P.satin)\n\t\tcupholders(K, P, x, top - 0.01, gz + 0.5, false)\n\t\tK:slab(\"EPB\", 0.12, 0.17, 0.04, 0.03, CFrame.new(x + side * 0.2, top + 0.01, gz - 0.4), P.button)\n\t\tK:slab(\"AutoHold\", 0.12, 0.1, 0.04, 0.03, CFrame.new(x - side * 0.2, top + 0.01, gz - 0.4), P.button)",
   "partsDelta": 1
  },
  {
   "rank": 5,
   "severity": "medium",
   "area": "center screen",
   "observed": "taxi_1_driver, taxi_2_wheel, taxi_3_center: a glowing white diagonal map line runs past the right edge of the nav bezel. A grey road bar also pokes out of the left edge.",
   "real": "All map content stays inside the glass.",
   "fix": "File: Screens.luau, function Screens.nav. This is a generic change that applies to every model. Bars are sized in w/h units but rotated in studs. MapBridge (x 0.12, width 0.9, rotated -9°) ends at 0.12+0.45·cos9° = 0.564w, which is 0.055 studs past the 0.86-wide taxi glass. MapRoad 1 (x -0.05, width 0.98) and MapRoad 2 (x -0.2, width 0.7, -14°) both start at -0.54w. New values: bridge x 0.10, width 0.74, -6° gives -0.27..0.47w, and its vertical extent stays inside the sea band (-0.37..-0.17h) for 2.4:1 and 1.7:1 screens. Road 1 becomes x -0.01, width 0.96 (-0.49..0.47). Road 2 becomes x -0.14, width 0.62 (-0.44..0.16). Road 5 becomes x 0.04, width 0.86 (-0.39..0.47).",
   "code": "-- Screens.luau, Screens.nav. OLD:\n\tbar(\"MapBridge\", 0.12, -0.26, 0.9, 0.022, -9, P.mapBridge, 0.002)\n\tfor _, r in { { -0.05, -0.1, 0.98, 0.03, 0 }, { -0.2, 0.12, 0.7, 0.022, -14 }, { 0.26, 0.06, 0.022, 0.42, 6 }, { -0.33, 0.04, 0.018, 0.42, -4 }, { 0.05, 0.26, 0.9, 0.018, 3 } } do\n-- NEW (회전한 막대도 유리 안에: 오른쪽 끝 <= 0.47w, 왼쪽 끝 >= -0.49w):\n\tbar(\"MapBridge\", 0.1, -0.26, 0.74, 0.022, -6, P.mapBridge, 0.002)\n\tfor _, r in { { -0.01, -0.1, 0.96, 0.03, 0 }, { -0.14, 0.12, 0.62, 0.022, -14 }, { 0.26, 0.06, 0.022, 0.42, 6 }, { -0.33, 0.04, 0.018, 0.42, -4 }, { 0.04, 0.26, 0.86, 0.018, 3 } } do",
   "partsDelta": 0
  },
  {
   "rank": 6,
   "severity": "medium",
   "area": "center screen",
   "observed": "taxi_2_wheel, taxi_3_center: the S-curve is five 0.07 cylinder segments that read as a black hose or pipe, running from the cluster hood's top-right corner and ending in a round stub beside the screen. The screen itself is a wide 0.86×0.36 (2.4:1) panel that looks like the 10.25-inch unit.",
   "real": "The LPi taxi pairs the 4.2-inch analog cluster with an 8-inch display audio, roughly 5:3 and about 17.5×10.5 cm of glass, which is about 0.62×0.37 studs at this cabin's scale (1 stud ≈ 0.29 m from the 5.12-stud interior width). That screen stands on its own; the S-curve surround linking hood and screen belongs to the 12.3-inch plus 10.25-inch package.",
   "fix": "File: Styles.luau, entry LIST.sonata_taxi only. Set center w = 0.64, h = 0.37 and sCurve = false. The screen stays at x = max(nav.X -0.01, minX -1.25+0.61+0.32+0.14 = -0.18) = -0.01, y = top+0.185+0.05 = 2.745, so the glass spans x -0.33..0.31 and y 2.56..2.93. That leaves a 0.2-stud gap to the hood edge (about -0.54). The nav map and text use relative coordinates and rescale automatically.",
   "code": "-- Styles.luau, LIST.sonata_taxi. OLD:\n\tcenter = { kind = \"float\", w = 0.86, h = 0.36 },\n\tsCurve = true,\n-- NEW:\n\tcenter = { kind = \"float\", w = 0.64, h = 0.37 }, -- 8\" 디스플레이 오디오 (약 5:3, 단독 플로팅)\n\tsCurve = false, -- S자 연결은 12.3\" 디지털 계기판 + 10.25\" 패키지 전용",
   "partsDelta": -5
  },
  {
   "rank": 7,
   "severity": "medium",
   "area": "dash",
   "observed": "taxi_1_driver, taxi_4_dash: the passenger half of the dash (top deck and face) is empty. No vacancy sign sits at the windshield base and no driver ID card is displayed.",
   "real": "A 개인택시 has a red LED 빈차표시등 standing on the passenger-side dash right under the windshield. It faces outward, and from inside you see its black back and its red glow. It also has the mandatory 운수종사자 자격증명 (driver qualification card) displayed on the passenger-side dash facing the passengers.",
   "fix": "File: Dash.luau, end of Dash.build (before `return {}`), gated by `S.key == \"sonata_taxi\" and F.kind ~= \"police\"`. Vacancy sign: an rbox 0.64×0.17×0.09 (r 0.035) at x = toC*1.45, sitting on the deck (y top+0.087 = 2.597). z comes from the windshield line: slope = (wsHigh.Y-wsLow.Y)/(wsHigh.Z-wsLow.Z) = 1.47/3.0 = 0.49, so zs = min(face-0.3, wsLow.Z + (top+0.34-wsLow.Y)/slope) = -2.515. The windshield at its top-front corner is then 0.15 above, clear of the A-pillar trim at x 2.375 and the defrost slots at z -2.9. A Neon red face sits on -Z with a '빈차' plate rotated 180° so it reads from outside. ID card: a gloss frame 0.38×0.17 at (toC*1.3, mid+0.2 = 2.15, face+0.006), filling exactly the gap between the chrome line top (2.065) and the DashRoll bottom (2.25) and clear of the side vent (x 1.915..2.445). Add a light card, a photo at its left and a text plate.",
   "code": "-- Dash.luau, end of Dash.build, just before `return {}`:\n\t-- 개인택시 (순찰차 제외): 빈차표시등 + 운수종사자 자격증명\n\tif S.key == \"sonata_taxi\" and F.kind ~= \"police\" then\n\t\tlocal wsL: Vector3, wsH: Vector3 = F.wsLow, F.wsHigh\n\t\tlocal slope = (wsH.Y - wsL.Y) / math.max(0.01, wsH.Z - wsL.Z)\n\t\t-- 빈차등: 조수석 쪽 앞유리 바로 아래 대시 위, 빨간 LED \"빈차\" 면이 밖(-Z)을 봄 (안에서는 검은 뒷면 + 빨간 빛)\n\t\tlocal zs = math.min(face - 0.3, wsL.Z + (top + 0.34 - wsL.Y) / math.max(0.05, slope))\n\t\tlocal vc = CFrame.new(toC * 1.45, top + 0.087, zs)\n\t\tK:rbox(\"VacancySign\", Vector3.new(0.64, 0.17, 0.09), 0.035, vc, P.hardDark)\n\t\tK:box(\"VacancyLed\", Vector3.new(0.56, 0.11, 0.01), vc * CFrame.new(0, 0, -0.047), P.ledRed)\n\t\tScreens.plate(K, \"VacancyText\", vc * CFrame.new(0, 0, -0.058) * CFrame.Angles(0, math.pi, 0), 0.5, 0.1, { \"빈차\" }, Color3.fromRGB(255, 236, 230), true)\n\t\t-- 운수종사자 자격증명: 조수석 대시 앞면, 크롬 라인 바로 위 (뒷자리 승객 쪽을 봄)\n\t\tlocal idc = CFrame.new(toC * 1.3, mid + 0.2, face + 0.006)\n\t\tK:panel(\"DriverIdFrame\", 0.38, 0.17, 0.012, 0.025, idc, P.gloss)\n\t\tK:box(\"DriverIdCard\", Vector3.new(0.34, 0.13, 0.004), idc * CFrame.new(0, 0, 0.007), { c = Color3.fromRGB(222, 226, 232) })\n\t\tK:box(\"DriverIdPhoto\", Vector3.new(0.075, 0.095, 0.003), idc * CFrame.new(-0.11, 0, 0.0095), { c = Color3.fromRGB(96, 104, 118) })\n\t\tScreens.plate(K, \"DriverIdText\", idc * CFrame.new(0.045, 0, 0.012), 0.22, 0.1, { \"운수종사자 자격증명\", \"개인택시\" }, Color3.fromRGB(28, 36, 52), true)\n\tend",
   "partsDelta": 17
  },
  {
   "rank": 8,
   "severity": "medium",
   "area": "console",
   "observed": "taxi_1_driver, taxi_4_dash: the two cupholders read as hotplates. Each is a thick bright-white chrome disc ring with a flat grey disc sitting 0.0075 above it, like a raised puck rather than an opening.",
   "real": "The cupholders are recessed openings in the dark console, with a gloss-black surround and a thin satin lip.",
   "fix": "File: Console.luau, local function cupholders(). This is generic for every model that uses it (sonata, taxi, tucson, carnival, ray lowTray). Change the outer ring from P.chrome to P.hardDark (no glare). Add a thin satin lip disc (d 0.287, top at y+0.0185), leaving a visible annulus about 0.011 wide. Shrink the black well to d 0.265 (top at y+0.0225), so from above you see a dark rim, a hairline satin lip and a black hole.",
   "code": "-- Console.luau. OLD:\nlocal function cupholders(K: any, P: any, x: number, y: number, z: number, along: boolean)\n\tfor _, s in { -1, 1 } do\n\t\tlocal c = if along then CFrame.new(x, y, z + s * 0.17) else CFrame.new(x + s * 0.19, y, z)\n\t\tK:cyl(\"CupholderRing\", 0.03, 0.31, c * ROT_X_TO_Y, P.chrome)\n\t\tK:cyl(\"Cupholder\", 0.035, 0.27, c * CFrame.new(0, 0.005, 0) * ROT_X_TO_Y, P.duct)\n\tend\nend\n-- NEW:\nlocal function cupholders(K: any, P: any, x: number, y: number, z: number, along: boolean)\n\tfor _, s in { -1, 1 } do\n\t\tlocal c = if along then CFrame.new(x, y, z + s * 0.17) else CFrame.new(x + s * 0.19, y, z)\n\t\t-- 어두운 테두리 + 얇은 새틴 립 + 검은 안쪽 (밝은 크롬 원판은 위에서 보면 하얀 핫플레이트처럼 보임)\n\t\tK:cyl(\"CupholderRing\", 0.03, 0.31, c * ROT_X_TO_Y, P.hardDark)\n\t\tK:cyl(\"CupholderLip\", 0.033, 0.287, c * CFrame.new(0, 0.002, 0) * ROT_X_TO_Y, P.satin)\n\t\tK:cyl(\"Cupholder\", 0.035, 0.265, c * CFrame.new(0, 0.005, 0) * ROT_X_TO_Y, P.duct)\n\tend\nend",
   "partsDelta": 2
  },
  {
   "rank": 9,
   "severity": "medium",
   "area": "console",
   "observed": "taxi_1_driver, taxi_3_center: the front of the console shows a rubber wireless-charging pad with a glowing white icon. Nothing marks it as a taxi's payment area.",
   "real": "Korean taxis carry a small black card terminal (교통카드/신용카드 단말기) with a mono LCD, keypad and RF tap mark, usually propped in the front console tray under the climate panel. The base LPi taxi has no wireless charger.",
   "fix": "File: Console.luau, Console.build, the charge-pad block (pz = zU+0.26 = -1.65 for the taxi), gated by `S.key == \"sonata_taxi\" and F.kind ~= \"police\"`; all other models keep the pad. The terminal is a panel 0.26×0.36×0.08 (r 0.05) tilted 70° back (face normal 0, 0.94, 0.34, facing up and toward the occupants), centred at (x, topY+0.075 = 1.615, pz+0.04 = -1.61). Its top end (y 1.715, z -1.765) stays 0.09 behind the climate strip face (z -1.855). Its rear end dips into the deck (1.58) before the gate plate (z ≥ -1.415). At x ±0.13 it clears EPB/AutoHold (|x| ≥ 0.14). A 0.16×0.07×0.12 stand at z pz-0.07 fills the gap under the raised end. Add an LCD, three key rows and a tap mark on the face.",
   "code": "-- Console.luau, Console.build. OLD:\n\t-- 무선 충전 패드\n\tlocal pz = zU + 0.26\n\tK:slab(\"ChargePad\", 0.6, 0.32, 0.025, 0.07, CFrame.new(x, topY + 0.045, pz), P.rubber)\n\tK:box(\"ChargeIcon\", Vector3.new(0.05, 0.01, 0.07), CFrame.new(x, topY + 0.06, pz), P.markWhite)\n-- NEW:\n\t-- 무선 충전 패드 (개인택시: 그 자리에 카드결제기)\n\tlocal pz = zU + 0.26\n\tif S.key == \"sonata_taxi\" and F.kind ~= \"police\" then\n\t\t-- 카드결제기: 20° 세운 작은 검은 단말기 (위 LCD · 키패드 3줄 · 카드 태그 표시) + 앞쪽 받침\n\t\tlocal tc = CFrame.new(x, topY + 0.075, pz + 0.04) * CFrame.Angles(math.rad(-70), 0, 0)\n\t\tK:box(\"TerminalStand\", Vector3.new(0.16, 0.07, 0.12), CFrame.new(x, topY + 0.06, pz - 0.07), P.hardDark)\n\t\tK:panel(\"CardTerminal\", 0.26, 0.36, 0.08, 0.05, tc, P.hardDark)\n\t\tK:box(\"TerminalLcd\", Vector3.new(0.19, 0.1, 0.006), tc * CFrame.new(0, 0.1, 0.042), P.lcd)\n\t\tfor i = 0, 2 do\n\t\t\tK:box(\"TerminalKeys\", Vector3.new(0.18, 0.035, 0.01), tc * CFrame.new(0, -0.01 - i * 0.05, 0.042), P.button)\n\t\tend\n\t\tK:box(\"TerminalTap\", Vector3.new(0.07, 0.012, 0.004), tc * CFrame.new(0, -0.15, 0.043), P.markWhite)\n\telse\n\t\tK:slab(\"ChargePad\", 0.6, 0.32, 0.025, 0.07, CFrame.new(x, topY + 0.045, pz), P.rubber)\n\t\tK:box(\"ChargeIcon\", Vector3.new(0.05, 0.01, 0.07), CFrame.new(x, topY + 0.06, pz), P.markWhite)\n\tend",
   "partsDelta": 5
  },
  {
   "rank": 10,
   "severity": "low",
   "area": "center screen",
   "observed": "taxi_3_center: a red sliver pokes out of the gloss stack between the AVN key row and the climate strip, left of the first '22'. It is the start button: Cockpit.build places it at x = W.X + (R+0.32) = -0.26, y = mid+0.05 = 2.0, z = face+0.03, which is inside the 1.28-wide StackBack (x ±0.64, z -1.99..-1.91), sandwiched between the keys and the climate strip.",
   "real": "The ENGINE START/STOP button sits on the dash just right of the steering column, beside the left edge of the centre stack, not inside the AVN/climate panel.",
   "fix": "File: Cockpit.luau, Cockpit.build, gated by `S.garnish == \"line\"` (sonata and sonata_taxi; other models keep their current position). Move the button outside the stack's driver-side edge, at x = cx + F.side*0.78 = -0.78 (ring spans -0.88..-0.68, clear of the stack edge -0.64 and the AVN knob at -0.6). Set y = mid-0.08 = 1.87 (ring 1.77..1.97, below the chrome line at 2.035). Set z = face-0.06 = -2.01, flush with the DashLower face, which is recessed to face-0.08 = -2.03 below upperY0 2.07.",
   "code": "-- Cockpit.luau, Cockpit.build. OLD:\n\tif S.startButton then\n\t\tlocal sb = CFrame.new(W.Position.X - F.side * (F.wheel.R + 0.32), F.dashMidY + 0.05, F.dashFace + 0.03)\n-- NEW:\n\tif S.startButton then\n\t\tlocal sb = CFrame.new(W.Position.X - F.side * (F.wheel.R + 0.32), F.dashMidY + 0.05, F.dashFace + 0.03)\n\t\tif S.garnish == \"line\" then\n\t\t\t-- 쏘나타: 1.28 폭 센터 스택 운전석 쪽 바깥, 크롬 라인 아래 하단 대시 면(face - 0.08)에 (스택 안에 묻히지 않게)\n\t\t\tlocal cx = if F.console then F.console.x else 0\n\t\t\tsb = CFrame.new(cx + F.side * 0.78, F.dashMidY - 0.08, F.dashFace - 0.06)\n\t\tend",
   "partsDelta": 0
  },
  {
   "rank": 11,
   "severity": "low",
   "area": "climate",
   "observed": "taxi_3_center: the AVN volume and tune knobs at the ends of the key row look like two grey bolts. They are bare alloy cylinders (d 0.08) centred at face+0.09, so their back sits 0.025 in front of the StackBack face (face+0.04) and they float.",
   "real": "The DN8 has a small black power/volume knob on the left and a tune knob on the right of the AVN key row, each with a satin ring and a white index mark, seated on the gloss panel.",
   "fix": "File: Dash.luau, Dash.build, branch `g == \"line\"`, AvnKnob loop (ky = vy-0.17). Seat each knob on the StackBack face (kc z = face+0.04): a satin ring (d 0.11, depth 0.03), a black knob (d 0.085, depth 0.06, front at face+0.115) and a white index mark.",
   "code": "-- Dash.luau, Dash.build, `g == \"line\"` branch. OLD:\n\t\tfor _, s in { -1, 1 } do\n\t\t\tK:cyl(\"AvnKnob\", 0.05, 0.08, CFrame.new(cx + s * 0.56, ky, face + 0.09) * ROT_X_TO_Z, P.alloy)\n\t\tend\n-- NEW:\n\t\tfor _, s in { -1, 1 } do\n\t\t\t-- 전원 · 볼륨(왼쪽) / 튜닝(오른쪽): 스택 면에 붙은 검은 노브 + 새틴 링 + 흰 표시선\n\t\t\tlocal kc = CFrame.new(cx + s * 0.56, ky, face + 0.04)\n\t\t\tK:cyl(\"AvnKnobRing\", 0.03, 0.11, kc * CFrame.new(0, 0, 0.015) * ROT_X_TO_Z, P.satin)\n\t\t\tK:cyl(\"AvnKnob\", 0.06, 0.085, kc * CFrame.new(0, 0, 0.045) * ROT_X_TO_Z, P.hardDark)\n\t\t\tK:box(\"AvnKnobMark\", Vector3.new(0.01, 0.026, 0.006), kc * CFrame.new(0, 0.022, 0.077), P.markWhite)\n\t\tend",
   "partsDelta": 4
  },
  {
   "rank": 12,
   "severity": "low",
   "area": "cluster",
   "observed": "taxi_2_wheel: each analog dial has a thick, bright white chrome ring (d 0.03, 20 segments) that dominates the cluster and gives it a retro sports-car look.",
   "real": "The DN8 base/LPi analog cluster has two dials with thin satin-silver rims around black faces, with the 4.2-inch LCD between them.",
   "fix": "Files: Gauges.luau (Gauges.dial, analog branch) and Cockpit.luau (gaugeLook). This is generic for all analog clusters (taxi, ray, porter, solati). Set ring cross-section to 0.018 (from 0.03), radius to r+0.018 (inner edge r+0.009, still covering the DialFace edge at r+0.015 and outside the tick ends at r-0.014), segments to 14 (sagitta 0.005, well under the 0.018 tube) and look to P.satin. This saves 6 parts per dial and offsets part of the part-count increase from the issues above.",
   "code": "-- Gauges.luau, Gauges.dial. OLD:\n\t\tK:ring(\"GaugeBezel\", frame * CFrame.new(0, 0, 0.012), r + 0.022, 0.03, 20, L.bezel)\n-- NEW:\n\t\tK:ring(\"GaugeBezel\", frame * CFrame.new(0, 0, 0.012), r + 0.018, 0.018, 14, L.bezel)\n\n-- Cockpit.luau, gaugeLook. OLD:\n\treturn { mark = P.gaugeMark, red = P.gaugeRed, ring = P.gaugeRing, needle = P.needle, cap = P.needleCap, bezel = P.chrome }\n-- NEW:\n\treturn { mark = P.gaugeMark, red = P.gaugeRed, ring = P.gaugeRing, needle = P.needle, cap = P.needleCap, bezel = P.satin }",
   "partsDelta": -12
  }
 ]
}
```

## critique:tucson

```json
{
 "car": "Hyundai Tucson NX4 (2021-2023), style key \"tucson\"",
 "summary": "The cabin already reads as an NX4. It has the hoodless floating 10.25-inch cluster, a piano-black stack with vertical vents and a knobless touch climate strip, the P/R/N/D row, the twin satin lines and a 4-spoke wheel with the H logo. The biggest gaps are four: the broken \"waterfall\" (a 1.5-wide stack hangs over the 0.92-wide console and the satin lines drop into mid-air instead of flowing onto the console), pipe-thin round A-pillar trims, an egg-shaped airbag pad, and the missing angled wireless-charging tray, followed by a drawer-like glovebox and a few boxy or cheap details.",
 "issues": [
  {
   "rank": 1,
   "severity": "high",
   "area": "garnish",
   "observed": "tucson_3_center.png, tucson_1_driver.png: the stack is a single 1.5-wide rounded tablet (CentreStack, sw = cw + 0.5) running from y 1.88 to 2.91. Its lower corners hang 0.29 past each side of the 0.92-wide console. The twin satin lines turn 90 degrees at a ball and drop straight down at x=+-0.79 and +-0.85 to y=1.90, ending in mid-air 0.33 outside the console. The console's own satin lines are separate, running at x=+-0.425 and starting at z=-1.46. Together with the glovebox outline, the lines frame a rectangle, so the waterfall is lost and the stack looks stuck on.",
   "real": "NX4 'Interspace' dash: the twin satin-silver lines cross the dash, sweep down both sides of the piano-black stack in a smooth curve and flow onto the edges of the high console. The stack narrows into the console, so it reads as one continuous waterfall from the dash to the armrest.",
   "fix": "Dash.luau, Dash.build, branch g == \"waterfall\" (only tucson uses it). (1) Split the stack in two. The upper part stays sw = 1.5 wide and runs from yJ = mid + 0.1 = 2.21 to top + 0.04 = 2.91; it holds the screen, the vents (x=+-0.63, y 2.50..2.88) and the climate strip (y 2.22..2.42). The lower part is conW - 0.13 = 0.79 wide and runs from conTop - 0.02 = 1.88 to 2.31; its front face is at face + 0.09 = -1.46. (2) Keep each horizontal line and its corner ball. Replace the vertical drop with a 5-segment smoothstep S-curve from (xin, ly, face + 0.014) down to the console top edge at (+-(conW/2 - 0.035) = +-0.425, conTop + 0.04 = 1.94, face - 0.067 = -1.617), which tucks onto the DashLower face at face - 0.08. Both lines converge on that point without crossing: the upper/inner line starts at (+-0.79, 2.24) and the lower/outer line at (+-0.85, 2.16). (3) Console.luau, buttons_row branch: start the console Garnish at the same z, F.dashFace - 0.067, and end it at zA - 0.05 = -0.005, at x = +-0.425, y = topY + 0.04, so the waterfall runs on unbroken to the armrest. Checked clearances: P/R/N/D (+-0.35), EPB row (+-0.265) and cupholders (+-0.345) all stay inside +-0.41.",
   "code": "-- Dash.luau  Dash.build, branch `elseif g == \"waterfall\" then`: replace old lines 274-291 (from `local sw = cw + 0.5` through the end of the garnish `for i, ly` loop) with:\nlocal sw = cw + 0.5\nlocal conW: number = if con then math.min(con.w, 1.15) else 0.9\nlocal yJ = mid + 0.1 -- the stack narrows here (just under the upper satin line)\nlocal sy0, sy1 = conTop - 0.02, top + 0.04\nK:panel(\"CentreStack\", sw, sy1 - yJ, 0.12, 0.14, CFrame.new(cx, (yJ + sy1) / 2, face + 0.04), P.gloss)\nK:panel(\"CentreStackLow\", conW - 0.13, yJ + 0.1 - sy0, 0.11, 0.06, CFrame.new(cx, (yJ + 0.1 + sy0) / 2, face + 0.035), P.gloss)\nfor _, s in { -1, 1 } do\n\tvent(K, P, \"StackVent\", CFrame.new(cx + s * (cw / 2 + 0.13), scrY, face + 0.11), 0.13, ch * 0.95, true, { frame = P.gloss, duct = P.duct, slat = P.hard, knob = P.satin })\nend\nclimate(K, F, P, S, cx, scrY - ch / 2 - 0.17, face + 0.115)\n-- twin satin lines: door -> dash -> S-curve inward/down past the stack -> merge on the console top edge (waterfall)\nlocal zf, ze = face + 0.014, face - 0.067 -- upper-layer face / lower-layer face (DashLower front = face - 0.08)\nfor i, ly in { mid + 0.13, mid + 0.05 } do\n\tfor _, s in { -1, 1 } do\n\t\tlocal xin = cx + s * (sw / 2 + 0.04 + (i - 1) * 0.06)\n\t\tlocal xout = s * (half - 0.06)\n\t\tK:cyl(\"Garnish\", math.abs(xout - xin), 0.026, CFrame.new((xin + xout) / 2, ly, zf), P.trim)\n\t\tK:ball(\"Garnish\", 0.026, CFrame.new(xin, ly, zf), P.trim)\n\t\tlocal xe, ye = cx + s * (conW / 2 - 0.035), conTop + 0.04\n\t\tlocal prev = Vector3.new(xin, ly, zf)\n\t\tfor k = 1, 5 do\n\t\t\tlocal t = k / 5\n\t\t\tlocal st = t * t * (3 - 2 * t)\n\t\t\tlocal p = Vector3.new(xin + (xe - xin) * st, ly + (ye - ly) * t, zf + (ze - zf) * st)\n\t\t\tK:seg(\"Garnish\", prev, p, 0.026, P.trim, 0.02)\n\t\t\tprev = p\n\t\tend\n\tend\nend\n\n-- Console.luau  Console.build, branch `elseif kind == \"buttons_row\" then`: replace the console Garnish loop (old lines 180-182) with:\nlocal g0, g1 = F.dashFace - 0.067, zA - 0.05 -- from where the dash lines land to the armrest\nfor _, s in { -1, 1 } do\n\tK:cyl(\"Garnish\", g1 - g0, 0.026, CFrame.new(x + s * (w / 2 - 0.035), topY + 0.04, (g0 + g1) / 2) * CFrame.Angles(0, math.pi / 2, 0), P.trim)\nend",
   "partsDelta": 22
  },
  {
   "rank": 2,
   "severity": "high",
   "area": "other",
   "observed": "tucson_1_driver.png, tucson_4_dash.png: both A-pillar trims are 0.15-diameter round rods (Dash.body, K:seg \"APillarTrim\"). They look like roll-cage tubes floating inside the windshield edge, with the outside world visible on both sides. This affects every model.",
   "real": "NX4 A-pillar trims are wide, flattened and fabric-wrapped, about 10 cm (about 0.34 stud at this scale, where 5.14-stud cabin width is roughly 1.45 m). They fill the corner between the windshield and the front door glass and face the cabin at an angle.",
   "fix": "Dash.luau, body(). This is a generic fix and is safe for all models: it changes only the cross-section and the 0.05 inward offset. Replace the seg with a zbox, 0.34 wide by 0.09 thick, with long edges rounded (r 0.044). Lay it parallel to the windshield plane (width along X projected off the pillar axis) and fold the outer edge 30 degrees inward toward the door glass. Offset changes from nOut*0.12 to nOut*0.17 so the inner edge clears the 0.08-thick glass. Tucson numbers: nOut=(0,0.873,-0.489); a=(+-2.435, 2.712, -2.617); b=(+-2.295, 4.112, -0.117); length 2.87 + 0.1. The outer edge reaches x of about 2.58 at the bottom, which is the door-glass plane (2.54) and halfIn (2.57). The bottom end is still below dashTop 2.87, as before.",
   "code": "-- Dash.luau  body(): replace the A-pillar loop (old lines 133-137) with:\nfor _, s in { -1, 1 } do\n\tlocal a = Vector3.new(s * (wsHalf - 0.1), ws.Y, ws.Z) - nOut * 0.17\n\tlocal b = Vector3.new(s * (wsHalf - 0.24), hiW.Y, hiW.Z) - nOut * 0.17\n\t-- wide, flat trim (not a round rod): parallel to the windshield, outer edge folded 30 deg back toward the door glass\n\tlocal along = (b - a).Unit\n\tlocal wx = (Vector3.xAxis - along * along.X).Unit\n\tlocal cf = CFrame.fromMatrix((a + b) / 2, wx, along:Cross(wx), along) * CFrame.Angles(0, 0, -s * math.rad(30))\n\tK:zbox(\"APillarTrim\", Vector3.new(0.34, 0.09, (b - a).Magnitude + 0.1), 0.044, cf, P.pillar)\nend",
   "partsDelta": 10
  },
  {
   "rank": 3,
   "severity": "medium",
   "area": "wheel",
   "observed": "tucson_2_wheel.png: the airbag cover is a large egg-shaped ellipsoid (K:ell \"Airbag\", 0.6 x 0.38) on an egg-shaped HubShell. It is the most prominent object in the driver view and looks generic and bulbous.",
   "real": "The pre-facelift NX4 wheel has a horizontally wide, flat-faced, rounded-trapezoid pad: wider at the top, with a narrower chin that runs into the two lower spokes. The chrome Hyundai H oval sits in the centre.",
   "fix": "Cockpit.luau, wheel(), gated on S.key == \"tucson\" (carnival also uses u4, so it is not gated on kind). Build the pad from two rounded panels in the wheel frame W (+Z toward the driver). Top panel: 0.552 x 0.236 x 0.126, centred at y = hy + 0.053 = 0.023. Chin: 0.372 x 0.19, centred at y = -0.106 and set back 0.004 to avoid z-fighting. The pad spans y -0.201 to 0.141, so the lower spokes still start at hy - hub.Y*0.42 = -0.19. Front faces sit at z = 0.15, flush with the existing emblem at 0.06 + hub.Z/2 + 0.002 = 0.152. The top width of 0.92 x hub.X keeps the pad clear of the spoke button panels, whose inner edge is at x = 0.27.",
   "code": "-- Cockpit.luau  wheel(): replace the Airbag if/else (old lines 94-98) with:\nif kind == \"three\" then\n\tK:rbox(\"Airbag\", Vector3.new(hub.Z, hub.Y, hub.X), 0.1, W * CFrame.new(0, hy, 0.06) * ROT_X_TO_Z, P.wheelHub)\nelseif S.key == \"tucson\" then\n\t-- NX4: wide flat-faced rounded-trapezoid pad (wide top, narrower chin); front face flush with the emblem plane\n\tlocal pz = 0.06 + hub.Z / 2 - hub.Z * 0.35\n\tK:panel(\"Airbag\", hub.X * 0.92, hub.Y * 0.62, hub.Z * 0.7, 0.1, W * CFrame.new(0, hy + hub.Y * 0.14, pz), P.wheelHub)\n\tK:panel(\"AirbagChin\", hub.X * 0.62, hub.Y * 0.5, hub.Z * 0.7, 0.08, W * CFrame.new(0, hy - hub.Y * 0.2, pz - 0.004), P.wheelHub)\nelse\n\tK:ell(\"Airbag\", hub, W * CFrame.new(0, hy, 0.06), P.wheelHub)\nend",
   "partsDelta": 11
  },
  {
   "rank": 4,
   "severity": "medium",
   "area": "console",
   "observed": "tucson_3_center.png: the charger is a flat 0.6 x 0.32 rubber slab lying on the console top at z = zU + 0.26 = -1.25. It shows only as a dark recess at the foot of the stack, and nothing bridges the stack to the console. The leather-textured cube on the P/R/N/D row in the renders sits exactly where the old model's ShiftBoot is (a 0.32 cube at (0, 2.06, -0.80)). That is studio car-skin geometry covered by the known skin fix; ShiftBoot and GearLever are already in Console.REPLACES.",
   "real": "NX4: an angled wireless-charging tray sits directly under the climate touch panel. It leans against the base of the stack and flows into the console, with the P/R/N/D buttons behind it.",
   "fix": "Console.luau, Console.build, gated on S.shifter == \"buttons_row\" (tucson only). Add a piano-black wedge, 0.64 x 0.21 x 0.30, rotated 180 degrees about Y so its high side faces the stack. It is centred at (x, topY + 0.145 = 2.045, F.dashFace + 0.09 + 0.15 = -1.31) and spans z -1.46 to -1.16 and y 1.94 to 2.15, a 35-degree slope. Its front touches the lower stack face (face + 0.09) from issue 1, and its top stays under the climate strip, whose bottom is at 2.22. Put a 0.54 x 0.30 rubber pad on the slope with CFrame.Angles(35 deg), offset 0.012 along the slope normal, plus the charge icon. The P/R/N/D panel at gz = -0.857 (z -0.99 to -0.73) stays clear.",
   "code": "-- Console.luau  Console.build: replace the ChargePad/ChargeIcon lines (old 113-115) with:\nlocal pz = zU + 0.26\nif S.shifter == \"buttons_row\" then\n\t-- Tucson NX4: wireless-charging tray leaning on the stack base under the climate panel (35 deg)\n\tlocal tz = F.dashFace + 0.09 -- lower stack front face\n\tlocal tc = CFrame.new(x, topY + 0.145, tz + 0.15)\n\tK:wedge(\"ChargeTray\", Vector3.new(0.64, 0.21, 0.3), tc * CFrame.Angles(0, math.pi, 0), P.gloss) -- high side against the stack\n\tlocal pc = tc * CFrame.Angles(math.rad(35), 0, 0) * CFrame.new(0, 0.012, 0)\n\tK:slab(\"ChargePad\", 0.54, 0.3, 0.02, 0.06, pc, P.rubber)\n\tK:box(\"ChargeIcon\", Vector3.new(0.05, 0.008, 0.07), pc * CFrame.new(0, 0.012, 0), P.markWhite)\nelse\n\tK:slab(\"ChargePad\", 0.6, 0.32, 0.025, 0.07, CFrame.new(x, topY + 0.045, pz), P.rubber)\n\tK:box(\"ChargeIcon\", Vector3.new(0.05, 0.01, 0.07), CFrame.new(x, topY + 0.06, pz), P.markWhite)\nend",
   "partsDelta": 1
  },
  {
   "rank": 5,
   "severity": "medium",
   "area": "dash",
   "observed": "tucson_3_center.png, tucson_1_driver.png: the glovebox is a sharp-cornered rectangle of four dark GloveGap boxes, 1.25 x 0.40 at x 1.02 to 2.27 and y 1.61 to 2.01, with a centred satin bar handle. Framed by the satin lines and the ambient strip above, it reads as a kitchen drawer.",
   "real": "NX4: the passenger side is a smooth, padded lower-layer panel under the satin lines and the long slot vent. The glovebox lid is a soft-cornered panel with a small dark pull tucked under the line, and there is no chrome drawer bar.",
   "fix": "Dash.luau, body(), gated on S.garnish == \"waterfall\" (tucson only). Replace the four gap boxes and the satin handle with two parts. (1) A GloveLid panel in P.lower, gw x gh = 1.25 x 0.40, corner radius 0.07, 0.03 thick, at (gx = 1.645, gy = 1.81, face - 0.065). It stands 0.03 proud of the DashLower face (face - 0.08 = -1.63), so only its rounded edge shading shows the lid. (2) A dark 0.3 x 0.04 GlovePull at y = gTop - 0.05 = 1.96, z = face - 0.04. All other models keep the old code.",
   "code": "-- Dash.luau  body(): replace the GloveGap loop + GloveHandle (old lines 123-126) with:\nif S.garnish == \"waterfall\" then\n\t-- NX4: smooth lid in the lower layer (rounded corners, no drawer frame) + dark finger pull under the satin lines\n\tK:panel(\"GloveLid\", gw, gh, 0.03, 0.07, CFrame.new(gx, gy, face - 0.065), P.lower)\n\tK:box(\"GlovePull\", Vector3.new(0.3, 0.04, 0.02), CFrame.new(gx, gTop - 0.05, face - 0.04), P.hardDark)\nelse\n\tfor _, e in { { 0, gh / 2, gw, 0.012 }, { 0, -gh / 2, gw, 0.012 }, { gw / 2, 0, 0.012, gh }, { -gw / 2, 0, 0.012, gh } } do\n\t\tK:box(\"GloveGap\", Vector3.new(e[3], e[4], 0.01), CFrame.new(gx + e[1], gy + e[2], face - 0.075), P.hardDark)\n\tend\n\tK:box(\"GloveHandle\", Vector3.new(0.3, 0.035, 0.03), CFrame.new(gx, gy + gh / 2 - 0.08, face - 0.07), P.satin)\nend",
   "partsDelta": 2
  },
  {
   "rank": 6,
   "severity": "low",
   "area": "wheel",
   "observed": "tucson_2_wheel.png: the lower spokes are two 0.08-diameter round rods, each with a 0.032 satin rod on top, running nearly parallel to 6 o'clock. They look spindly, like a tuning fork.",
   "real": "NX4: two slim, flat lower spokes set close together, joining the round rim at 6 o'clock, with satin-silver garnish on their driver-facing faces.",
   "fix": "Cockpit.luau, wheel(), inside the vee4/u4 branch, gated on S.key == \"tucson\". Keep the same endpoints: a = W(+-0.075, hy - hub.Y*0.42 = -0.19, 0) and b at -90 +- 10 degrees on R - 0.03 = 0.64, which is (+-0.111, -0.63, -0.01). Replace each seg with a flat box 0.09 wide, 0.05 thick and len + 0.04 (about 0.48) long, oriented with CFrame.lookAt(mid, b, W.ZVector) so the flat face points at the driver. Add a 0.05-wide satin face strip offset 0.027 toward the driver. Part count is unchanged.",
   "code": "-- Cockpit.luau  wheel(), inside `if kind == \"vee4\" or kind == \"u4\" then` after `local b = ...`: replace the LowerSpoke seg + lowerTrim block (old lines 136-141) with:\nif S.key == \"tucson\" then\n\t-- NX4: two flat close-set lower spokes, satin strip on the driver-facing side\n\tlocal cfL = CFrame.lookAt((a + b) / 2, b, W.ZVector)\n\tlocal lenL = (b - a).Magnitude\n\tK:box(\"LowerSpoke\", Vector3.new(0.09, 0.05, lenL + 0.04), cfL, P.hard)\n\tK:box(\"LowerSpokeTrim\", Vector3.new(0.05, 0.012, lenL - 0.1), cfL * CFrame.new(0, 0.027, 0.03), P.satin)\nelse\n\tK:seg(\"LowerSpoke\", a, b, 0.08, P.hard)\n\tif ws.lowerTrim then\n\t\tlocal a2 = (W * CFrame.new(s * 0.075, hy - hub.Y * 0.42, 0.04)).Position\n\t\tlocal b2 = (W * CFrame.new(math.cos(t) * (R - 0.08), math.sin(t) * (R - 0.08), 0.03)).Position\n\t\tK:seg(\"LowerSpokeTrim\", a2, b2, 0.032, if ws.lowerTrim == \"gloss\" then P.gloss else P.satin)\n\tend\nend",
   "partsDelta": 0
  },
  {
   "rank": 7,
   "severity": "low",
   "area": "doors",
   "observed": "tucson_1_driver.png, tucson_3_center.png: the front door speaker is placed at z0 + 0.5 = -1.90, which is 0.35 ahead of the dash face (-1.55). It therefore appears inside the passenger footwell under the glovebox, as a chrome ring in a dark box.",
   "real": "NX4: a round Bose grille low on the front of the door card, behind the dash line, below the armrest and ahead of the map pocket.",
   "fix": "Trim.luau, doorCard(). This is generic for front doors of non-plastic (passenger-car) styles; porter, solati and ray are untouched. Set spz = max(z0 + 0.5, F.dashFace + 0.38) and y = y0 + lowH*0.6. Tucson: z -1.17, y 1.04, ring spanning y 0.74 to 1.34 and z -1.47 to -0.87. This clears the armrest bottom (1.42) and the map pocket top (0.71). Checked the others as well: sonata z -1.57 (top 1.20 vs armrest 1.23), g80 -0.97 (1.23 vs 1.28), carnival -1.92 (1.34 vs 1.39).",
   "code": "-- Trim.luau  doorCard(): replace `local sp = CFrame.new(x + inward * 0.06, y0 + lowH * 0.55, z0 + 0.5)` with:\nlocal spz = if front and not plastic then math.max(z0 + 0.5, (F.dashFace :: number) + 0.38) else z0 + 0.5\nlocal sp = CFrame.new(x + inward * 0.06, y0 + lowH * 0.6, spz)",
   "partsDelta": 0
  },
  {
   "rank": 8,
   "severity": "low",
   "area": "headliner",
   "observed": "tucson_4_dash.png: the overhead console is a flat-bottomed slab with square corners seen from below (rbox rounds only the X edges), carrying flat white lamp tiles. The sun visor has a black dash-plastic VanityCover slab on light fabric, which looks like a cutting board.",
   "real": "NX4: the overhead console is a sculpted, rounded unit holding the LED map lamps, the SOS/Bluelink keys and the sunroof switch. The visor vanity covers are in a plastic close to the headliner tone.",
   "fix": "Trim.luau, Trim.build (generic). Build OverheadConsole as a slab (0.78 x 0.5 x 0.08, plan radius 0.16) at oc + (0, 0.02, 0), so its top stays at roofY. Add a flat ellipsoid belly, 0.74 x 0.06 x 0.46, at oc + (0, -0.03, 0); its bottom at -0.06 sits just above the existing map lamps, SOS key and roof switch at -0.065. Change the VanityCover look from P.hard to P.pillar (headliner colour darkened 38%).",
   "code": "-- Trim.luau  Trim.build: replace `K:rbox(\"OverheadConsole\", Vector3.new(0.78, 0.12, 0.5), 0.05, oc, P.hard)` with:\nK:slab(\"OverheadConsole\", 0.78, 0.5, 0.08, 0.16, oc * CFrame.new(0, 0.02, 0), P.hard)\nK:ell(\"OverheadBelly\", Vector3.new(0.74, 0.06, 0.46), oc * CFrame.new(0, -0.03, 0), P.hard)\n-- and in the visor loop replace the VanityCover line with:\nK:box(\"VanityCover\", Vector3.new(0.5, 0.012, 0.26), v * CFrame.new(-s * 0.1, -0.035, 0.04), P.pillar)",
   "partsDelta": 1
  },
  {
   "rank": 9,
   "severity": "low",
   "area": "climate",
   "observed": "tucson_3_center.png: under the 22 / 22 readouts, the touch climate strip shows seven identical 0.045 x 0.03 glowing white blocks spaced 0.1 apart. They read as a row of LEDs, not touch icons.",
   "real": "NX4 full-touch climate: a gloss-black panel with small white icon glyphs for temperature, AUTO, fan, A/C, defrost and recirculation, and a hairline separating the readouts from the keys.",
   "fix": "Dash.luau, climate(), branch kind == \"touch\" (tucson only). Shrink the icons to thin 0.04 x 0.012 glyphs, with the centre AUTO glyph 0.08 wide, at x = i*0.11 (max +-0.35 on the 1.02-wide strip) and y = -0.06. Add a 0.86 x 0.004 hairline divider at y = -0.032 in P.button.",
   "code": "-- Dash.luau  climate(), branch `elseif kind == \"touch\" then`: replace the TouchIcon loop (old lines 178-180) with:\nfor i = -3, 3 do\n\tK:box(\"TouchIcon\", Vector3.new(if i == 0 then 0.08 else 0.04, 0.012, 0.004), cf * CFrame.new(i * 0.11, -0.06, 0.014), P.markWhite)\nend\nK:box(\"TouchDivider\", Vector3.new(0.86, 0.004, 0.004), cf * CFrame.new(0, -0.032, 0.014), P.button)",
   "partsDelta": 1
  }
 ]
}
```

## critique:g80

```json
{
 "car": "Genesis G80 RG3 (2020-2023), style key \"g80\"",
 "summary": "The render already has the G80's design language: the 2-spoke wheel with the winged crest, the short-hood cluster, a hairline vent over a wood band, the hanging climate panel with knurled dials, two knurled dials on a wood console, Lexicon door speakers and quilted two-tone seats. The biggest gaps are these: the 14.5\" screen sits like a tablet at the base of the windshield (on a box cowl, and it cuts through the windshield) instead of sitting flush above the vent line; the quilting stitches run off the seat inserts into the air; daylight neon tubes (dash and console) hide the hairline vent; and the wood band does not carry into the doors at the dash's height.",
 "issues": [
  {
   "rank": 1,
   "severity": "high",
   "area": "center screen",
   "observed": "g80_1_driver.png / g80_3_center.png / g80_4_dash.png: the 14.5\" screen looks like a separate tablet at the base of the windshield, with a dark box (CenterCowl) under it. It is far ahead of the cluster and reads like a soundbar. Geometry: ccf = (0.12, top+ch/2-0.06 = 2.82, face-0.28 = -1.63), tilted -8 deg, so the glass top edge is at about (y 3.07, z -1.665). At that z the windshield inner plane is at about y 2.94 (ws (2.62,-2.45)->(4.02,0.60), slope 0.459, glass half-thickness 0.04), so the screen cuts about 0.13 through the windshield.",
   "real": "The ultra-wide screen (about 2.6:1) is set low and nearly flush into the top centre of the dash. Its lower edge sits just above the full-width hairline vent and its top stands only a little above the dash top, with a thin dark bezel and a leather surround. It is level with the short cluster hood, not perched on the dash deck.",
   "fix": "Cockpit.luau, displays(), branch kind == \"flush\" (only G80 uses it). Put the glass on the dash face (face + 0.05) with its bottom at top - 0.12. Replace CenterCowl and CenterBack with one shallow leather housing whose corners are rounded when seen from the front. Numbers (dims: top 2.63, face -1.35, cw 1.42, ch 0.5, toC +1, cx 0): glass centre (0.16, 2.76, -1.30), spanning x -0.55..0.87 and y 2.51..3.01. Bezel bottom is 2.48, just above the vent's upper lip (top-0.165 = 2.465 +/- 0.008, see issue 5). The housing's top-back edge is at about (3.02, -1.43); the windshield inner plane there is at about 3.04, so it clears the glass. Housing left edge -0.60 sits clear of the ClusterBack right edge (-1.30 + 0.66 = -0.64).",
   "code": "-- Cockpit.luau, displays()\n-- old:\n\telseif kind == \"flush\" then\n\t\t-- G80: 대시 위쪽 가운데에 낮고 넓게 박힌 화면 (가죽 둔덕이 감쌈)\n\t\tccf = CFrame.new(cx + toC * 0.12, top + ch / 2 - 0.06, face - 0.28) * CFrame.Angles(math.rad(-8), 0, 0)\n\t\tK:rbox(\"CenterCowl\", Vector3.new(cw + 0.22, ch * 0.62, 0.44), 0.12, ccf * CFrame.new(0, -ch * 0.2, -0.26), P.soft)\n\t\tK:panel(\"CenterBack\", cw - 0.06, ch - 0.06, 0.1, 0.08, ccf * CFrame.new(0, 0, -0.07), P.hard)\n-- new:\n\telseif kind == \"flush\" then\n\t\t-- G80 RG3: 대시 면(face)과 거의 같은 면에 박힌 초광폭 화면. 유리 아래 끝(top - 0.12)은 헤어라인 송풍구 위 립\n\t\t-- (top - 0.165) 바로 위, 뒤는 얕은 가죽 하우징(앞에서 본 모서리 둥긂)만. 앞유리 밑에 얹힌 태블릿 X (예전 윗끝은 앞유리를 뚫었음)\n\t\tccf = CFrame.new(cx + toC * 0.16, top - 0.12 + ch / 2, face + 0.05) * CFrame.Angles(math.rad(-3), 0, 0)\n\t\tK:panel(\"CenterHousing\", cw + 0.1, ch + 0.04, 0.1, 0.1, ccf * CFrame.new(0, 0, -0.07), P.soft)",
   "partsDelta": -6
  },
  {
   "rank": 2,
   "severity": "high",
   "area": "seats",
   "observed": "g80_3_center.png (bottom-left) and g80_4_dash.png (driver seat): the diamond quilting appears as long thin sticks lying across the seat. They cross the bolsters, and on the cushion they stick out past the seat edges into the air. Cause: Seats.quilt draws unclipped lines 1.2*h long. On the cushion (insert w = 1.75*0.5 = 0.875, h = 1.80*0.6 = 1.08), each 1.30-long line at 35 deg spans +/-0.37 sideways around offsets up to +/-0.66, so it reaches x = +/-1.03. That is beyond the insert half-width (0.44) and the seat half-width (0.875).",
   "real": "G-Matrix diamond quilting on the Nappa centre panels of the cushion and backrest, a fine diamond lattice that stays inside the insert and never crosses the bolsters.",
   "fix": "Seats.luau, quilt() (used only by insert == \"quilt\", so only G80). Clip each diagonal to the insert rectangle, |x| <= w/2 and |y| <= h/2, then place a box of the clipped length at the clipped midpoint. Pitch is w/3.5 (0.25 on the cushion), which gives diamonds about 0.25 x 0.36. Same convention as before: lines in the frame's XY plane, 0.006 thick along frame Z, so the cushion and backrest callers are unchanged. The part count stays about the same (about 14 lines per panel; corner stubs shorter than 0.05 are dropped).",
   "code": "-- Seats.luau: replace the whole quilt()\nlocal function quilt(K: any, frame: CFrame, w: number, h: number, look: any)\n\t-- 다이아몬드 퀼팅: 두 방향 대각선 스티치를 인서트 사각형(w × h) 안으로 잘라서 (볼스터 · 좌석 밖으로 삐져나오지 않게)\n\tlocal ang = math.rad(35)\n\tlocal ux, uy = math.sin(ang), math.cos(ang)\n\tlocal pitch = w / 3.5\n\tlocal n = math.ceil((w / 2 + (h / 2) * ux / uy) / pitch)\n\tfor i = -n, n do\n\t\tlocal off = i * pitch\n\t\tfor _, s in { -1, 1 } do\n\t\t\tlocal dx = s * ux\n\t\t\t-- 선 (off, 0) + t·(dx, uy) 를 |x| ≤ w/2, |y| ≤ h/2 로 자름\n\t\t\tlocal ta, tb = (-w / 2 - off) / dx, (w / 2 - off) / dx\n\t\t\tlocal t0 = math.max(-(h / 2) / uy, math.min(ta, tb))\n\t\t\tlocal t1 = math.min((h / 2) / uy, math.max(ta, tb))\n\t\t\tif t1 - t0 > 0.05 then\n\t\t\t\tlocal tm = (t0 + t1) / 2\n\t\t\t\tK:box(\"Quilt\", Vector3.new(0.008, t1 - t0, 0.006), frame * CFrame.new(off + tm * dx, tm * uy, 0) * CFrame.Angles(0, 0, -s * ang), look)\n\t\t\tend\n\t\tend\n\tend\nend",
   "partsDelta": 0
  },
  {
   "rank": 3,
   "severity": "high",
   "area": "lights",
   "observed": "g80_3_center.png: a bright vertical neon bar (ConsoleAmbient, 1.8 long, on the passenger edge of the console) runs through the middle of the image. g80_3_center.png / g80_4_dash.png / g80_1_driver.png: DashAmbient (d 0.018 at wy+0.13 = 2.36) glows as a white fluorescent tube right under the hairline-vent lip and washes it out. Both are in daylight. init only changes Transparency to 0.55 in the day, and Neon still glows at that value.",
   "real": "G80 mood lighting is a subtle warm (#ffd7a0) indirect glow that shows at night. In daylight it is not visible as a lit line; what you see is the trim (wood, satin lip).",
   "fix": "init.client.luau, RenderStepped ambient block: in the day, switch ambient parts to SmoothPlastic in a darkened accent colour (60% toward black, which gives bronze rgb(102,86,64) on the G80). At night use Neon with the full accent. This is generic and helps every model with ambient (sonata, tucson, carnival). cab.fit is F and colors.ambient exists in every style.",
   "code": "-- init.client.luau (RenderStepped)\n-- old:\n\t\t-- 앰비언트: 밤에 밝게\n\t\tif cab.night ~= night then\n\t\t\tcab.night = night\n\t\t\tfor _, p in cab.ambient do\n\t\t\t\tp.Transparency = if night then 0.1 else 0.55\n\t\t\tend\n\t\tend\n-- new:\n\t\t-- 앰비언트: 밤에만 빛남. 낮에는 Neon 이 아닌 어두운 같은 색 선 (낮에 형광등 막대처럼 보이지 않게)\n\t\tif cab.night ~= night then\n\t\t\tcab.night = night\n\t\t\tlocal acc: Color3 = cab.fit.style.colors.ambient\n\t\t\tfor _, p in cab.ambient do\n\t\t\t\tp.Material = if night then Enum.Material.Neon else Enum.Material.SmoothPlastic\n\t\t\t\tp.Color = if night then acc else acc:Lerp(Color3.new(0, 0, 0), 0.6)\n\t\t\t\tp.Transparency = if night then 0.1 else 0\n\t\t\tend\n\t\tend",
   "partsDelta": 0
  },
  {
   "rank": 4,
   "severity": "medium",
   "area": "doors",
   "observed": "g80_4_dash.png (right edge) and g80_1_driver.png (left door): the door wood strip sits at upY0+0.1 = 1.90 (1.82..1.98), about 0.33 below the dash wood band (wy = top-0.4 = 2.23, 2.11..2.35). The door chrome is at 1.80, not at the vent-lip height (2.395). The band therefore steps down at each dash end instead of wrapping around the cabin.",
   "real": "A signature of the G80: the open-pore wood band and the hairline chrome/ambient line run from the dash straight across the upper door at the same height, door to door, front and rear.",
   "fix": "Trim.luau doorCard(): add woodY = clamp(dashTop - 0.4, upY0 + 0.12, y1 - 0.3), which is the same formula as Dash (sy = top-0.2, wy = sy-0.2). For G80: 2.63-0.4 = 2.23, inside the clamp [1.92, 2.395]. Use the dash band height 0.24, put DoorChrome at woodY+0.165 = 2.395 (the dash's lower vent lip), and put DoorAmbient at woodY+0.13 (same as DashAmbient). No collision with the sill (2.605+) or the IMS keys (hy-0.24 = 2.0). The pull cup (hy = armY+0.45 = 2.24) now sits inside the band as a recessed pull. Only the wood garnish (G80) is affected.",
   "code": "-- Trim.luau doorCard()\n-- old:\n\tlocal lineY = if g == \"line\" then math.clamp((F.dashMidY :: number) + 0.1, upY0 + 0.06, y1 - 0.08) else upY0 + 0.1\n\tif g == \"line\" then\n\t\tK:cyl(\"DoorTrimBand\", len - 0.4, 0.03, CFrame.new(x + inward * 0.06, lineY, zc) * AZ, P.trim)\n\telseif g == \"wood\" then\n\t\tK:zbox(\"DoorTrimBand\", Vector3.new(0.05, 0.16, len - 0.4), 0.024, CFrame.new(x + inward * 0.05, upY0 + 0.1, zc), P.trim)\n\t\tK:cyl(\"DoorChrome\", len - 0.42, 0.016, CFrame.new(x + inward * 0.07, upY0 + 0.0, zc) * AZ, P.chrome)\n-- new:\n\tlocal lineY = if g == \"line\" then math.clamp((F.dashMidY :: number) + 0.1, upY0 + 0.06, y1 - 0.08) else upY0 + 0.1\n\t-- G80: 대시 우드 띠 가운데 높이 (Dash: sy = top - 0.2, wy = sy - 0.2)\n\tlocal woodY = math.clamp((F.dashTop :: number) - 0.4, upY0 + 0.12, y1 - 0.3)\n\tif g == \"line\" then\n\t\tK:cyl(\"DoorTrimBand\", len - 0.4, 0.03, CFrame.new(x + inward * 0.06, lineY, zc) * AZ, P.trim)\n\telseif g == \"wood\" then\n\t\t-- 우드 띠(0.24) + 위 크롬 립(송풍구 아래 립 높이)이 대시에서 문으로 끊김 없이\n\t\tK:zbox(\"DoorTrimBand\", Vector3.new(0.05, 0.24, len - 0.4), 0.024, CFrame.new(x + inward * 0.05, woodY, zc), P.trim)\n\t\tK:cyl(\"DoorChrome\", len - 0.42, 0.016, CFrame.new(x + inward * 0.07, woodY + 0.165, zc) * AZ, P.chrome)\n\n-- and the DoorAmbient line:\n-- old:\n\t\tK:cyl(\"DoorAmbient\", len - 0.6, 0.02, CFrame.new(x + inward * 0.07, if g == \"line\" then lineY - 0.045 else upY0 + 0.03, zc) * AZ, P.ambient)\n-- new:\n\t\tK:cyl(\"DoorAmbient\", len - 0.6, 0.02, CFrame.new(x + inward * 0.07, if g == \"line\" then lineY - 0.045 elseif g == \"wood\" then woodY + 0.13 else upY0 + 0.03, zc) * AZ, P.ambient)",
   "partsDelta": 0
  },
  {
   "rank": 5,
   "severity": "medium",
   "area": "vents",
   "observed": "g80_3_center.png / g80_4_dash.png: the full-width hairline vent cannot be seen. HairlineVent is a P.duct black slab on black leather that stands 0.03 proud, with only one chrome lip under it, and that lip is swamped by the ambient tube. The upper zone and lower zone run together.",
   "real": "One ultra-thin slot runs across the whole dash under the screen: a dark recessed gap framed by bright metal edges, with small adjustment tabs. It splits the cabin into the upper panoramic zone and the lower control zone.",
   "fix": "Dash.luau, wood branch: move the slot back so its front is flush with the dash face (centre face-0.028, depth 0.06, front at face+0.002). Add a matching upper lip, giving two chrome lips at sy +/- 0.035 (2.465 / 2.395, on the flat DashUpper face, which runs up to top-rr = 2.50) and face+0.012. The existing VentTabs (face+0.025) now stand out in front of the dark gap. The upper lip top (2.473) stays below the moved screen bezel (2.48, issue 1).",
   "code": "-- Dash.luau, Dash.build, g == \"wood\"\n-- old:\n\t\tlocal sy = top - 0.2\n\t\tK:panel(\"HairlineVent\", width - 0.3, 0.05, 0.06, 0.024, CFrame.new(0, sy, face + 0.0), P.duct)\n\t\tK:cyl(\"HairlineLip\", width - 0.32, 0.016, CFrame.new(0, sy - 0.035, face + 0.02), P.chrome)\n-- new:\n\t\tlocal sy = top - 0.2\n\t\t-- 슬롯 앞면을 대시 면에 맞춰 안으로 들어간 검은 틈 + 위 · 아래 크롬 립 2줄 = 한 줄 헤어라인 송풍구\n\t\tK:panel(\"HairlineVent\", width - 0.3, 0.05, 0.06, 0.024, CFrame.new(0, sy, face - 0.028), P.duct)\n\t\tfor _, ly in { sy + 0.035, sy - 0.035 } do\n\t\t\tK:cyl(\"HairlineLip\", width - 0.32, 0.016, CFrame.new(0, ly, face + 0.012), P.chrome)\n\t\tend",
   "partsDelta": 1
  },
  {
   "rank": 6,
   "severity": "medium",
   "area": "wheel",
   "observed": "g80_2_wheel.png / g80_1_driver.png: the airbag is a tall egg-shaped ellipsoid dome (ell 0.62 x 0.4 x 0.2) with a lumpy HubShell around it, so the hub reads as a black egg. Sonata (vee4) and Carnival (trap) already have flat pad branches; \"two\" still falls through to the dome.",
   "real": "G80 RG3 hub: a wide, horizontal, pill-shaped (stadium) leather pad with a fairly flat face and the winged crest in the centre, bulging a little below centre (HubChin, already there). The two broad spokes join at its ends.",
   "fix": "Cockpit.luau wheel(): add a kind == \"two\" branch before the final else. It builds a stadium panel (w hub.X 0.62, h 0.40, depth hub.Z*0.55 = 0.11, end radius h/2-0.004 = 0.196, centred z 0.03, front at 0.085) and a shallow crown ell (0.53 x 0.31 x 0.07 at z 0.085, front at 0.12). Move the emblem onto the crown at z = 0.03 + 0.055 + 0.037 = 0.122 (it was 0.162). HubChin stays (front 0.125 at y -0.174), so the small lower bulge remains.",
   "code": "-- Cockpit.luau wheel(): insert before the final `else K:ell(\"Airbag\", hub, ...)`\n\t\telseif kind == \"two\" then\n\t\t\t-- G80 RG3: 가로로 넓은 알약(스타디움)형 납작한 패드 + 얕은 크라운 (달걀형 돔 X)\n\t\t\tK:panel(\"Airbag\", hub.X, hub.Y, hub.Z * 0.55, hub.Y / 2 - 0.004, W * CFrame.new(0, hy, 0.03), P.wheelHub)\n\t\t\tK:ell(\"AirbagCrown\", Vector3.new(hub.X * 0.86, hub.Y * 0.78, 0.07), W * CFrame.new(0, hy, 0.03 + hub.Z * 0.275), P.wheelHub)\n\n-- emblem line\n-- old:\n\t\temblem(K, P, S.brand, W * CFrame.new(0, hy + 0.005, 0.06 + hub.Z / 2 + 0.002))\n-- new:\n\t\temblem(K, P, S.brand, W * CFrame.new(0, hy + 0.005, if kind == \"two\" then 0.03 + hub.Z * 0.275 + 0.037 else 0.06 + hub.Z / 2 + 0.002))",
   "partsDelta": 6
  },
  {
   "rank": 7,
   "severity": "medium",
   "area": "shifter",
   "observed": "g80_1_driver.png / g80_3_center.png: the six AluKey are hard-edged boxes (0.12 x 0.03 x 0.07) standing 0.02 proud of the wood in light P.alloy metal, so they render as pastel blue-white candy tiles. Both dials look like coarse cogs: 14 and 12 ribs, each 0.016 deep and centred on the surface, so they stick out 0.008.",
   "real": "Shift-by-wire dial in front, touch-top jog dial behind, both with fine satin-silver knurling, set in open-pore wood. The surrounding aluminium keys are low-profile and nearly flush, a darker satin metal, not bright raised tiles.",
   "fix": "Console.luau. (a) vknurl: make the ribs shallower and finer. Radial size 0.01 at r = d/2-0.001 (protrudes 0.004); tangential width min(0.014, pi*d/n*0.45). This is generic; Carnival keeps its 14-rib count. (b) In dial_wood, raise the counts to 24 ribs on the shift dial and 20 on the jog dial. (c) Make each key a single flat lens: an ell 0.11 x 0.022 x 0.062 centred on the wood top (top+0.005), so it rises only 0.011, in darker metal rgb(104,106,110). Positions are unchanged: gz = zU + L*0.4 = -1.31 + 2.01*0.4 = -0.51, so all keys fall inside ConsoleWood (z -1.03..0.22, x +/-0.43).",
   "code": "-- Console.luau vknurl()\n-- old:\n\tfor i = 1, n do\n\t\tlocal a = (i / n) * math.pi * 2\n\t\tK:box(\"Knurl\", Vector3.new(0.016, h * 0.84, 0.014), cf * CFrame.new(math.cos(a) * d / 2, h / 2, math.sin(a) * d / 2) * CFrame.Angles(0, -a, 0), P.chrome)\n\tend\n-- new:\n\tlocal tw = math.min(0.014, math.pi * d / n * 0.45)\n\tlocal rr = d / 2 - 0.001\n\tfor i = 1, n do\n\t\tlocal a = (i / n) * math.pi * 2\n\t\tK:box(\"Knurl\", Vector3.new(0.01, h * 0.84, tw), cf * CFrame.new(math.cos(a) * rr, h / 2, math.sin(a) * rr) * CFrame.Angles(0, -a, 0), P.chrome)\n\tend\n\n-- Console.luau, kind == \"dial_wood\"\n-- old:\n\t\tvknurl(K, P, CFrame.new(x, top, gz), 0.27, 0.13, 14, P.gloss)\n-- new:\n\t\tvknurl(K, P, CFrame.new(x, top, gz), 0.27, 0.13, 24, P.gloss)\n-- old:\n\t\tvknurl(K, P, CFrame.new(x, top, gz + 0.42), 0.23, 0.08, 12, P.screen)\n\t\tfor _, k in { { -0.24, -0.08 }, { 0.24, -0.08 }, { -0.24, 0.16 }, { 0.24, 0.16 }, { -0.22, 0.42 }, { 0.22, 0.42 } } do\n\t\t\tK:box(\"AluKey\", Vector3.new(0.12, 0.03, 0.07), CFrame.new(x + k[1], top + 0.01, gz + k[2]), P.alloy)\n\t\tend\n-- new:\n\t\tvknurl(K, P, CFrame.new(x, top, gz + 0.42), 0.23, 0.08, 20, P.screen)\n\t\tlocal keyLook = { c = Color3.fromRGB(104, 106, 110), m = Enum.Material.Metal }\n\t\tfor _, k in { { -0.24, -0.08 }, { 0.24, -0.08 }, { -0.24, 0.16 }, { 0.24, 0.16 }, { -0.22, 0.42 }, { 0.22, 0.42 } } do\n\t\t\t-- 우드 면(top + 0.005)에서 0.011 만 솟은 납작한 렌즈형 알루미늄 키 (1파트, 모서리 없음)\n\t\t\tK:ell(\"AluKey\", Vector3.new(0.11, 0.022, 0.062), CFrame.new(x + k[1], top + 0.005, gz + k[2]), keyLook)\n\t\tend",
   "partsDelta": 18
  },
  {
   "rank": 8,
   "severity": "low",
   "area": "garnish",
   "observed": "g80_1_driver.png / g80_3_center.png: on the vertical dash face, which is in shadow, the WoodBand (#6b5440 Wood) reads as an almost black strip. The signature wood plinth is not recognisable as wood; only the top-lit console wood looks brown.",
   "real": "Open-pore olive ash on the RG3: a medium grey-brown wood with clear grain, plainly lighter than the black leather above and below it.",
   "fix": "Styles.luau LIST.g80.colors.trim: lighten it one step. This is used by WoodBand, DoorTrimBand, ConsoleWood and CupLid, so the dash, doors and console stay one material.",
   "code": "-- Styles.luau, LIST.g80.colors\n-- old:\n\t\ttrim = hex(\"#6b5440\"),\n-- new:\n\t\ttrim = hex(\"#7d6650\"),",
   "partsDelta": 0
  },
  {
   "rank": 9,
   "severity": "low",
   "area": "headliner",
   "observed": "g80_4_dash.png (top): the overhead console is a black brick with sharp corners when seen from below. Raised white map-lamp tiles and a red SOS block sit on it like stickers, which looks toy-like.",
   "real": "A slim, rounded overhead console with flush lens map lamps and a small round SOS button.",
   "fix": "Trim.luau Trim.build (generic, all cars). Use a slab with corners rounded when seen from below. Keep the same 0.78 x 0.5 footprint and 0.12 height so the bottom stays at oc-0.06, which keeps Carnival's SlideDoorSwitch/TailgateSwitch (at oc-0.065) seated. Map lamps become flush ell lenses; Lights still finds them by the name \"MapLamp\" and the Bottom-face SpotLight still works. SOS becomes a small round cylinder. G80 numbers: roofY 3.82, lz0 0.62, so oc = (0, 3.76, 1.07).",
   "code": "-- Trim.luau Trim.build\n-- old:\n\t\tK:rbox(\"OverheadConsole\", Vector3.new(0.78, 0.12, 0.5), 0.05, oc, P.hard)\n\t\tfor _, s in { -1, 1 } do\n\t\t\tK:box(\"MapLamp\", Vector3.new(0.2, 0.02, 0.12), oc * CFrame.new(s * 0.22, -0.065, 0.02), P.lampLens)\n\t\tend\n\t\tK:box(\"SOS\", Vector3.new(0.08, 0.02, 0.05), oc * CFrame.new(0, -0.065, 0.15), P.hazard)\n-- new:\n\t\t-- 아래에서 보면 네 모서리가 둥근 판 + 면에 묻힌 타원 렌즈 · 둥근 SOS (튀어나온 흰 타일 X)\n\t\tK:slab(\"OverheadConsole\", 0.78, 0.5, 0.12, 0.16, oc, P.hard)\n\t\tfor _, s in { -1, 1 } do\n\t\t\tK:ell(\"MapLamp\", Vector3.new(0.2, 0.024, 0.13), oc * CFrame.new(s * 0.22, -0.06, 0.02), P.lampLens)\n\t\tend\n\t\tK:cyl(\"SOS\", 0.016, 0.065, oc * CFrame.new(0, -0.064, 0.15) * CFrame.Angles(0, 0, math.pi / 2), P.hazard)",
   "partsDelta": 0
  },
  {
   "rank": 10,
   "severity": "low",
   "area": "dash",
   "observed": "g80_1_driver.png: the start button (now at x = -1.30 + min(1.01, 1.30 - 0.86) = -0.86, y = mid - 0.12 = 1.83, clear of the hanging climate panel at +/-0.68) uses P.startBtn, the red face shared with the Hyundai/Kia styles.",
   "real": "The Genesis start/stop button is a chrome-ringed button with a dark face and white ENGINE START STOP lettering. It is not red.",
   "fix": "Cockpit.luau Cockpit.build: choose the button face by brand. Genesis gets P.gloss; the other brands keep P.startBtn.",
   "code": "-- Cockpit.luau Cockpit.build\n-- old:\n\t\tK:cyl(\"StartButton\", 0.05, 0.15, sb * CFrame.new(0, 0, 0.012) * ROT_X_TO_Z, P.startBtn)\n-- new:\n\t\tK:cyl(\"StartButton\", 0.05, 0.15, sb * CFrame.new(0, 0, 0.012) * ROT_X_TO_Z, if S.brand == \"genesis\" then P.gloss else P.startBtn)",
   "partsDelta": 0
  }
 ]
}
```

## critique:ray

```json
{
 "car": "Kia Ray TAM (2022 The New Kia Ray), style key \"ray\"",
 "summary": "The Ray cabin already has the right layout: an 8\" screen with tall vents at the top of a satin-framed pod, then the hazard switch, the dash-mounted lever and the three-dial climate panel, plus the small hooded two-dial cluster with its LCD, the 3-spoke wheel and the walk-through floor. The biggest gaps are geometry bugs, not missing features: the top half of the nav screen is buried inside the pod face, the pod stops 0.7 studs above the floor so the cupholder box floats on its own, the screen is too wide (ribbon-shaped) with the vent rims overlapping it, the gear lever reads as a tiny black ball, the binnacle has ear-like cheeks, and the rear has a 3-seat bench although the Ray is a 4-seater.",
 "issues": [
  {
   "rank": 1,
   "severity": "high",
   "area": "center screen",
   "observed": "ray_2_wheel.png and ray_3_center.png: only the lower ~55% of the nav map shows. The upper band is black with stray light streaks where the top bar and route parts poke through the pod face. Math with the current code: the glass is at face+0.17 and tilted -8 deg, so the front of its top edge is at face+0.155. The pod face front is at face+0.175, so every point above y=+0.035 on the glass is inside the pod.",
   "real": "On the Ray the 8\" screen sits flush and upright at the top of the near-vertical centre fascia, with all of it visible under the dash top.",
   "fix": "Cockpit.luau, displays(), kind == \"pod\" branch: drop the -8 deg tilt (the pod face is vertical) and move the glass 0.025 in front of the pod face. Numbers: top=2.46, ch=0.36 gives y=2.22 (unchanged), z = face+0.19 = -1.86. Glass front is then at face+0.20 and the NavBezel spans face+0.15..0.19, both in front of the StackPodFace front at face+0.175. Dash reads only ccf.Position.Y, so nothing else moves.",
   "code": "-- Cockpit.luau displays()\n-- old:\n\telseif kind == \"pod\" then\n\t\tccf = CFrame.new(cx, top - ch / 2 - 0.06, face + 0.17) * CFrame.Angles(math.rad(-8), 0, 0)\n-- new:\n\telseif kind == \"pod\" then\n\t\t-- 레이: 포드 면(face + 0.175)이 수직이라 화면도 수직, 면보다 0.025 앞 (기울이면 위쪽 절반이 포드 속에 묻힘)\n\t\tccf = CFrame.new(cx, top - ch / 2 - 0.06, face + 0.19)",
   "partsDelta": 0
  },
  {
   "rank": 2,
   "severity": "high",
   "area": "console",
   "observed": "ray_1_driver.png and ray_3_center.png: the satin pod ends in mid-air at y=1.03 (py0 = floorY+0.7). The cupholder box (LowTray at z = con.z0+0.32 = -1.43, top y 0.76) sits on the floor 0.46 studs behind and 0.27 below the pod, with bare dark floor between them, so it reads as a loose box.",
   "real": "The Ray's centre fascia runs down to the floor and ends in a small low tray with two cupholders at its foot. The floor between the seats stays flat and open.",
   "fix": "Dash.luau, pod_v branch: after the climate() call, add a lower-fascia foot from the floor to the pod bottom. Numbers: floorY=0.33 to py0+0.06=1.09 gives h=0.76 and centre y=0.71; width pw-0.34=0.92 (x within ±0.46, clear of the gas pedal at about x=-0.65); z = face ± 0.17 (-2.22..-1.88), which tucks 0.005 behind the pod face front (face+0.175). Console.luau lowTray(): for the ray, butt the tray against the foot's rear face. z = dashFace+0.42 = -1.63, so the tray spans -1.88..-1.38.",
   "code": "-- Dash.luau, pod_v branch, after: climate(K, F, P, S, cx, py0 + 0.24, face + 0.17)\n\t\t\t-- 포드 아래 → 바닥: 하단 페시아가 발치 트레이까지 이어짐 (포드가 공중에 떠 보이지 않게)\n\t\t\tlocal fy0, fy1 = F.floorY, py0 + 0.06\n\t\t\tK:zbox(\"StackFoot\", Vector3.new(pw - 0.34, fy1 - fy0, 0.34), 0.08, CFrame.new(cx, (fy0 + fy1) / 2, face), P.hard)\n\n-- Console.luau lowTray()\n-- old:\n\tlocal z = if con then math.max(con.z0, F.dashFace) + 0.32 else F.dashFace + 0.32\n-- new:\n\t-- 레이: 트레이 앞 끝을 StackFoot 뒤 면(dashFace + 0.17)에 붙임\n\tlocal z = if F.style.key == \"ray\" then F.dashFace + 0.42 elseif con then math.max(con.z0, F.dashFace) + 0.32 else F.dashFace + 0.32",
   "partsDelta": 6
  },
  {
   "rank": 3,
   "severity": "medium",
   "area": "vents",
   "observed": "ray_3_center.png and ray_2_wheel.png: the nav screen is a wide ribbon (0.84 x 0.36, 2.3:1, about a 12\" panel at the 1 stud = 0.29 m scale given by R=0.63 for the real 37 cm wheel). The chrome rims of the narrow pod vents (w 0.13) overlap both ends of the screen. Vent rim inner edge = 0.54-0.065-0.035 = 0.44, but the NavBezel half-width is 0.45.",
   "real": "An 8\" 16:9 unit is about 17.7 x 10 cm, which is 0.62-0.64 x 0.35 studs. It is flanked by two clearly separate tall vertical vents of roughly screen height, all inside the metal-look pod bezel.",
   "fix": "Styles.luau ray: center.w 0.84 -> 0.64. Dash.luau pod_v: pw = cw + 0.62 (pod 1.26 wide, face half-width 0.595). Vents become w 0.15 x h ch*0.95 = 0.342, at x = ±(cw/2+0.155) = ±0.475 and z = face+0.18. The rim then spans 0.365..0.585: a 0.015 gap to the bezel (half-width 0.35) and inside the pod face. Rim front is at face+0.195, in front of the pod face (0.175). The 1.16-wide climate plate still fits the 1.19-wide face.",
   "code": "-- Styles.luau LIST.ray\n-- old: center = { kind = \"pod\", w = 0.84, h = 0.36 },\n-- new:\n\tcenter = { kind = \"pod\", w = 0.64, h = 0.36 }, -- 8\" 16:9 (약 17.7 x 10 cm)\n\n-- Dash.luau pod_v branch\n-- old:\n\t\t\tlocal pw = cw + 0.46\n-- new:\n\t\t\tlocal pw = cw + 0.62 -- 8\" 화면 + 양옆 세로 송풍구 0.15 → 포드 폭 1.26\n-- old:\n\t\t\t\tvent(K, P, \"PodVent\", CFrame.new(cx + s * (cw / 2 + 0.12), scrY, face + 0.17), 0.13, ch * 0.92)\n-- new:\n\t\t\t\t-- 화면 베젤(반폭 cw/2 + 0.03)과 0.015 띄우고 포드 면(반폭 pw/2 - 0.035) 안에\n\t\t\t\tvent(K, P, \"PodVent\", CFrame.new(cx + s * (cw / 2 + 0.155), scrY, face + 0.18), 0.15, ch * 0.95)",
   "partsDelta": 0
  },
  {
   "rank": 4,
   "severity": "medium",
   "area": "shifter",
   "observed": "ray_3_center.png and ray_1_driver.png: the dash-mounted lever reads as a small black ball floating at the lower-left of its gate. The knob is 0.13 x 0.15 x 0.13 in dark-grey P.leather on a 0.04 alloy stem only 0.215 long, with no satin accents and no P/R/N/D marks. The 0.035-wide GearSlot is a full 6-part rbox.",
   "real": "The Ray's signature high lever sticks out about 12-15 cm from the fascia, below the hazard switch. It runs in a straight gate with a silver surround and P R N D marks beside the slot, and the revised 2022 knob is black with a satin accent and a release button.",
   "fix": "Dash.luau pod_v branch: replace the stem, knob and button, and turn GearSlot into a single box. Numbers: the gate is at y = hz-0.27 = 1.69 and a = gate(0, 0.1, 0.02), which is (0, 1.79, face+0.19). b = a + (0, 0.05, 0.28). Knob centre (0, 1.89, -1.54), size 0.17 x 0.20 x 0.19, so it spans y 1.79..1.99. Sight check from the driver's eye (3.59, z 0.95): at the knob's z the line to the hazard (y 1.96) passes at y 2.15 and the line to the screen bottom (2.04) at 2.22, so neither is hidden. Letters go on the driver's side of the slot (x = ds*0.085, inside the plate's ±0.125).",
   "code": "-- Dash.luau pod_v branch\n-- old:\n\t\t\tK:panel(\"GearSlot\", 0.035, 0.32, 0.01, 0.016, gate * CFrame.new(0, 0, 0.015), P.duct)\n\t\t\tlocal a = (gate * CFrame.new(0, 0.1, 0.02)).Position\n\t\t\tlocal b = a + Vector3.new(0, 0.08, 0.2)\n\t\t\tK:seg(\"GearStem\", a, b, 0.04, P.alloy)\n\t\t\tK:ell(\"GearKnob\", Vector3.new(0.13, 0.15, 0.13), CFrame.new(b + Vector3.new(0, 0.04, 0.02)), P.leather)\n\t\t\tK:box(\"GearButton\", Vector3.new(0.04, 0.03, 0.03), CFrame.new(b + Vector3.new(0, 0.06, 0.085)), P.satin)\n-- new:\n\t\t\tK:box(\"GearSlot\", Vector3.new(0.035, 0.32, 0.01), gate * CFrame.new(0, 0, 0.015), P.duct)\n\t\t\t-- 레버: P 자리에서 승객 쪽으로 0.28 나온 검은 막대 + 새틴 칼라, 큰 검은 노브 + 새틴 띠 + 운전석 쪽 해제 버튼\n\t\t\tlocal a = (gate * CFrame.new(0, 0.1, 0.02)).Position\n\t\t\tlocal b = a + Vector3.new(0, 0.05, 0.28)\n\t\t\tK:ell(\"GearBoot\", Vector3.new(0.1, 0.07, 0.08), CFrame.new(a + Vector3.new(0, 0, 0.02)), P.rubber)\n\t\t\tK:seg(\"GearStem\", a, b, 0.05, P.hardDark)\n\t\t\tK:seg(\"GearCollar\", a:Lerp(b, 0.55), a:Lerp(b, 0.7), 0.066, P.satin)\n\t\t\tlocal kc = CFrame.new(b + Vector3.new(0, 0.05, 0.04))\n\t\t\tK:ell(\"GearKnob\", Vector3.new(0.17, 0.2, 0.19), kc, P.hardDark)\n\t\t\tK:ell(\"GearKnobBand\", Vector3.new(0.176, 0.045, 0.196), kc * CFrame.new(0, -0.035, 0), P.satin)\n\t\t\tK:box(\"GearButton\", Vector3.new(0.03, 0.05, 0.06), kc * CFrame.new(ds * 0.086, 0.02, 0), P.satin)\n\t\t\t-- 슬롯 운전석 쪽 P R N D 표시 (글자판 1 파트)\n\t\t\tScreens.plate(K, \"GearLetters\", gate * CFrame.new(ds * 0.085, -0.005, 0.021), 0.045, 0.3, { \"P\", \"R\", \"N\", \"D\" }, Color3.fromRGB(225, 232, 242), true)",
   "partsDelta": -1
  },
  {
   "rank": 5,
   "severity": "medium",
   "area": "cluster",
   "observed": "ray_3_center.png (and the right edge of the binnacle in ray_1_driver.png): a tall thin ellipsoid 'ClusterCheek' (0.1 x 0.48 x 0.43 at x = ±0.63) sticks up past the ends of the hood like an ear. A squared ClusterBack box (1.18 x 0.52 x 0.42 panel) shows between the dial and the ear.",
   "real": "The 2022 Ray's binnacle is one small rounded visor that falls smoothly to the dash on both sides, with no separate ears and no boxy housing.",
   "fix": "Gate it with a new style field cluster.cowl = true (ray only; porter and solati keep 'deep' as is). For cowl: use the ellipsoid ClusterBack (same as 'slim') instead of the 6-part panel, skip both cheeks, and add one ClusterCowl ellipsoid of hood width. Numbers: w=1.06, h=0.42, hw=1.36, hd=0.62, cowl size (1.36, 0.62, 0.62) at clCF(0, 0.06, -0.34). Its front is at z -0.03, behind the bezel's back face (-0.027), so it never covers the glass. Its top is at +0.37, under the hood top (+0.374 at that z).",
   "code": "-- Styles.luau LIST.ray\n-- old: cluster = { kind = \"analog\", hood = \"deep\", w = 1.06, h = 0.42, speedMax = 200, rpmMax = 8 },\n-- new:\n\tcluster = { kind = \"analog\", hood = \"deep\", w = 1.06, h = 0.42, speedMax = 200, rpmMax = 8, cowl = true },\n\n-- Cockpit.luau displays()\n-- old:\n\t\tif hoodKind == \"slim\" then\n-- new:\n\t\tif hoodKind == \"slim\" or C.cowl then\n-- old:\n\t\tfor _, s in { -1, 1 } do\n\t\t\tif not (S.sCurve and s == toC) then -- 쏘나타: 화면 쪽 볼은 S자 드롭이 대신\n-- new:\n\t\tif C.cowl then\n\t\t\t-- 레이: 귀처럼 튀는 볼 2개 대신 차양 폭의 둥근 비너클 껍데기 하나 (앞 끝 = 유리 면 0.03 뒤, 위 끝 < 차양 위)\n\t\t\tK:ell(\"ClusterCowl\", Vector3.new(hw, h + 0.2, hd), clCF * CFrame.new(0, 0.06, -0.34), P.soft)\n\t\tend\n\t\tfor _, s in { -1, 1 } do\n\t\t\tif not (S.sCurve and s == toC) and not C.cowl then -- 쏘나타: 화면 쪽 볼은 S자 드롭이 대신",
   "partsDelta": -6
  },
  {
   "rank": 6,
   "severity": "medium",
   "area": "seats",
   "observed": "The rear (fit: rear x=0 z=3.00 w=3.95) goes through rearBench(): 3 cushions, 3 back sections, a centre armrest seam and 3 headrests including the small centre one. This is a 5-seat layout (not covered by the 4 front-focused shots, but visible from any rear or door view).",
   "real": "The Kia Ray is a 4-seater (경차 정원 4명). The rear is a 2-seat bench split 50:50 with two headrests, no centre seat and no armrest (spec rear: bench2).",
   "fix": "Add a style field seat.rear2 = true for ray. In Seats.luau rearBench, use n = 2 or 3 seats with index i = k-(n+1)/2: seatW = 3.95/2 = 1.975, seat centres at x = ±0.99, outer bolsters only. Draw the armrest seams only when n == 3. Default headrests at ±seatW*(n-1)/2 (±0.99 for n=2, ±seatW for n=3, so 3-seat cars are unchanged), and add the centre small headrest only when n == 3. This saves 8 cushion, 8 back, 2 seam and 8 headrest parts.",
   "code": "-- Styles.luau LIST.ray\n-- old: seat = { insert = \"plain\", bolster = 0.6 },\n-- new:\n\tseat = { insert = \"plain\", bolster = 0.6, rear2 = true, manual = true }, -- 4인승 (뒤 2자리) · 수동 시트\n\n-- Seats.luau rearBench(): replace from \"-- 3 자리 쿠션\" through the headrest loop header\n\t-- 자리 쿠션 (3인 벤치 / 레이: 4인승이라 뒤 2자리 5:5)\n\tlocal n = if F.style.seat.rear2 then 2 else 3\n\tlocal seatW = W / n\n\tfor k = 1, n do\n\t\tlocal i = k - (n + 1) / 2\n\t\tlocal cx = s.x + i * seatW\n\t\tlocal pan = CFrame.new(cx, cushTop - 0.13, s.z)\n\t\tK:rbox(\"BenchPan\", Vector3.new(seatW - 0.04, 0.24, cs.Z - 0.05), 0.1, pan, seatLook)\n\t\tK:box(\"BenchInsert\", Vector3.new(seatW * 0.62, 0.04, cs.Z * 0.7), pan * CFrame.new(0, 0.12, 0.05), insertLook)\n\t\tif i ~= 0 then\n\t\t\tlocal o = if i < 0 then -1 else 1\n\t\t\tK:ell(\"BenchBolster\", Vector3.new(0.3, 0.24, cs.Z * 0.92), pan * CFrame.new(o * (seatW / 2 - 0.12), 0.07, 0.02), seatLook)\n\t\tend\n\t\tK:cyl(\"BenchRoll\", seatW - 0.12, 0.24, pan * CFrame.new(0, 0, -cs.Z / 2 + 0.1), seatLook)\n\tend\n\t-- 등받이 (18°)\n\tlocal bs: Vector3 = s.backSize or Vector3.new(W, 1.8, 0.45)\n\tlocal H = math.max(1.5, bs.Y)\n\tlocal hinge = CFrame.new(s.x, cushTop - 0.05, zR - 0.1) * CFrame.Angles(math.rad(18), 0, 0)\n\tfor k = 1, n do\n\t\tlocal bc = hinge * CFrame.new((k - (n + 1) / 2) * seatW, H / 2, 0.06)\n\t\tK:rbox(\"BenchBack\", Vector3.new(H, seatW - 0.05, 0.3), 0.11, bc * ROT_X_TO_Y, seatLook)\n\t\tK:box(\"BenchBackInsert\", Vector3.new(seatW * 0.6, H * 0.62, 0.04), bc * CFrame.new(0, -0.1, -0.16), insertLook)\n\t\tK:ell(\"BenchShoulder\", Vector3.new(seatW - 0.1, 0.26, 0.32), bc * CFrame.new(0, H / 2 - 0.1, 0), seatLook)\n\tend\n\tif n == 3 then\n\t\t-- 가운데 팔걸이 (접힌 상태: 등받이 면에 보이는 경계)\n\t\tlocal mid = hinge * CFrame.new(0, H * 0.32, 0)\n\t\tK:box(\"ArmrestSeam\", Vector3.new(0.012, H * 0.5, 0.01), mid * CFrame.new(-0.3, 0, -0.125), P.hardDark)\n\t\tK:box(\"ArmrestSeam\", Vector3.new(0.012, H * 0.5, 0.01), mid * CFrame.new(0.3, 0, -0.125), P.hardDark)\n\tend\n\t-- 헤드레스트 (양끝 2 + 3인 벤치면 가운데 작은 것)\n\tlocal heads = F.rearHeads or {}\n\tlocal xs = {}\n\tfor _, h in heads do\n\t\ttable.insert(xs, h)\n\tend\n\tlocal edge = seatW * (n - 1) / 2\n\tif #xs < 2 then\n\t\txs = { Vector3.new(s.x - edge, 0, 0), Vector3.new(s.x + edge, 0, 0) }\n\tend\n\tif n == 3 then\n\t\ttable.insert(xs, Vector3.new(s.x, 0, 0))\n\tend\n\tfor k, hp in xs do\n\t\tlocal topC = hinge * CFrame.new(hp.X - s.x, H + 0.05, 0.06)\n\t\tlocal small = n == 3 and k == #xs\n\t\t-- (rest of the headrest loop unchanged)",
   "partsDelta": -26
  },
  {
   "rank": 7,
   "severity": "low",
   "area": "wheel",
   "observed": "ray_1_driver.png and ray_2_wheel.png: the lower spoke is a narrow 0.16-wide vertical bar with a 0.11 gloss strip, so the wheel reads like a plain T. The side button pads are blank grey keypads with no icons.",
   "real": "The 2022 Ray (Morning-family) 3-spoke wheel has a broad lower spoke carrying a wide high-gloss black garnish, and gloss-black switch pads on the side spokes with white icons (audio/phone/voice on the left, cruise on the right).",
   "fix": "Cockpit.luau wheel(), kind == \"three\": widen the spoke to 0.26 (gloss 0.19). Numbers: y0 = hy - hub.Y*0.45 = -0.192, y1 = -(R-0.03) = -0.60. At x = ±0.13 the rim centre line is at y = -0.616, so the rounded bottom corners (r 0.08) stay inside the rim tube. At the top the HubShell bottom at x = ±0.13 is y = -0.205, which overlaps the spoke top by 0.013, so the spoke stays attached. Styles: wheel.icons = true reuses the existing white ButtonIcon path (+8 parts).",
   "code": "-- Styles.luau LIST.ray\n-- old: wheel = { spokes = \"three\", hub = Vector3.new(0.44, 0.36, 0.17), sideTrim = false, lowerTrim = \"gloss\", paddles = false },\n-- new:\n\twheel = { spokes = \"three\", hub = Vector3.new(0.44, 0.36, 0.17), sideTrim = false, lowerTrim = \"gloss\", paddles = false, icons = true },\n\n-- Cockpit.luau wheel(), if kind == \"three\" then\n-- old:\n\t\t\tK:panel(\"LowerSpoke\", 0.16, y0 - y1, 0.07, 0.06, W * CFrame.new(0, (y0 + y1) / 2, 0), P.hard)\n\t\t\tK:panel(\"LowerSpokeTrim\", 0.11, y0 - y1 - 0.06, 0.02, 0.04, W * CFrame.new(0, (y0 + y1) / 2, 0.04), P.gloss)\n-- new:\n\t\t\t-- 레이 2022: 넓은 아래 스포크 + 넓은 하이글로시 가니시\n\t\t\tK:panel(\"LowerSpoke\", 0.26, y0 - y1, 0.07, 0.08, W * CFrame.new(0, (y0 + y1) / 2, 0), P.hard)\n\t\t\tK:panel(\"LowerSpokeTrim\", 0.19, y0 - y1 - 0.08, 0.02, 0.05, W * CFrame.new(0, (y0 + y1) / 2 - 0.01, 0.04), P.gloss)",
   "partsDelta": 8
  },
  {
   "rank": 8,
   "severity": "low",
   "area": "other",
   "observed": "Trim.luau builds only brake, gas and a footrest. There is no parking-brake control anywhere in the Ray cabin (correctly no handbrake lever, but nothing replaces it).",
   "real": "The Ray uses a foot-operated parking brake: a small pedal high at the far left of the driver's footwell, above the footrest (spec signature).",
   "fix": "Trim.luau, after the brake/footrest block: for the ray, add a small rubber pedal pad and arm placed relative to the brake. pb = brake + (F.side*0.5, 0.42, -0.12). With the default brake (-1.05, 0.71, -1.80) that gives pb = (-1.55, 1.13, -1.92): 0.45 above the footrest at (-1.6, 0.68), 0.28 in front of the knee panel (z about -2.2), and clear of the door (x -2.14). The arm ends at (-1.55, 1.58, -2.24), inside the lower dash, so it is hidden.",
   "code": "-- Trim.luau, after the `if brake then ... end` block\n\tif F.style.key == \"ray\" and brake then\n\t\t-- 레이: 발 주차 브레이크 (핸드브레이크 없음) - 풋레스트 위, 대시 아래 왼쪽 끝\n\t\tlocal pb = brake + Vector3.new(F.side * 0.5, 0.42, -0.12)\n\t\tK:box(\"ParkBrakePedal\", Vector3.new(0.22, 0.15, 0.04), CFrame.new(pb) * CFrame.Angles(math.rad(-30), 0, 0), P.rubber)\n\t\tK:seg(\"PedalArm\", pb + Vector3.new(0, 0.06, -0.04), pb + Vector3.new(0, 0.45, -0.32), 0.045, P.metalDark)\n\tend",
   "partsDelta": 2
  },
  {
   "rank": 9,
   "severity": "low",
   "area": "seats",
   "observed": "Seats.luau frontSeat() puts satin power-seat switch capsules on the outer side shield of every front seat, the Ray's included.",
   "real": "Ray front seats are manual: a black recline lever at the rear of the side shield, plus a height-pump lever on the driver's seat. There are no power-seat switches.",
   "fix": "Gate on seat.manual (set in issue 6's Styles line). Keep the satin switches for the other cars; for manual seats draw a recline lever (and a height lever on the driver's side only, x*F.side > 0). Driver x=-1.05: shield at x = -1.05-0.795 = -1.845; levers 0.05 outboard.",
   "code": "-- Seats.luau frontSeat(), inside `if not s.inner then`\n-- old:\n\t\tK:capsule(\"SeatSwitch\", (shield * CFrame.new(out * 0.045, 0.02, -0.24)).Position, (shield * CFrame.new(out * 0.045, 0.02, 0.02)).Position, 0.045, P.satin)\n\t\tK:capsule(\"SeatSwitch\", (shield * CFrame.new(out * 0.045, -0.02, 0.16)).Position, (shield * CFrame.new(out * 0.045, 0.1, 0.16)).Position, 0.04, P.satin)\n-- new:\n\t\tif st.manual then\n\t\t\t-- 수동 시트 (레이): 뒤쪽 등받이 각도 레버 + 운전석 높이 조절 펌프 레버\n\t\t\tK:capsule(\"ReclineLever\", (shield * CFrame.new(out * 0.05, 0.06, 0.3)).Position, (shield * CFrame.new(out * 0.05, 0.1, 0.05)).Position, 0.06, P.hardDark)\n\t\t\tif x * F.side > 0 then\n\t\t\t\tK:capsule(\"HeightLever\", (shield * CFrame.new(out * 0.05, -0.02, -0.05)).Position, (shield * CFrame.new(out * 0.05, 0.0, -0.3)).Position, 0.05, P.hardDark)\n\t\t\tend\n\t\telse\n\t\t\tK:capsule(\"SeatSwitch\", (shield * CFrame.new(out * 0.045, 0.02, -0.24)).Position, (shield * CFrame.new(out * 0.045, 0.02, 0.02)).Position, 0.045, P.satin)\n\t\t\tK:capsule(\"SeatSwitch\", (shield * CFrame.new(out * 0.045, -0.02, 0.16)).Position, (shield * CFrame.new(out * 0.045, 0.1, 0.16)).Position, 0.04, P.satin)\n\t\tend",
   "partsDelta": -3
  }
 ]
}
```

## verify:sonata

```json
{
 "car": "sonata",
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
   "problem": "The volume test is correct. cab.fit and cab.base exist. F.wheel.cf, R, halfIn, dashBottom, dashTop, dashFront and dashFace all exist. Both volumes land where intended for the Sonata (wheel disc r<0.73 within 0.3 of the wheel plane; dash slab |x|<2.56, y 1.34-3.00, z -3.03 to -1.60), and pedals, mirror and seats fall outside. The weak point is the KEEP list. It only checks for Taxi, Meter and Police, using pattern-mode find. Functional or visual police and 119 gear inside the dash slab whose names lack those words (siren switches, radio or mic) gets hidden, and the police Sonata cabin does not rebuild that gear. HEAD (d3edf45) already widened KEEP and uses plain find. Use that version.",
   "correctedCode": "-- init.client.luau, above hideOld (this is what HEAD has):\nlocal KEEP = { \"Taxi\", \"Meter\", \"Police\", \"Siren\", \"Radio\" }\nlocal function insideNew(cab: any, p: Instance): boolean\n\tif not p:IsA(\"BasePart\") then\n\t\treturn false\n\tend\n\tfor _, k in KEEP do\n\t\tif string.find(p.Name, k, 1, true) then\n\t\t\treturn false\n\t\tend\n\tend\n\tlocal F = cab.fit\n\tlocal lp = cab.base.CFrame:PointToObjectSpace((p :: BasePart).Position)\n\tlocal w = F.wheel.cf:PointToObjectSpace(lp)\n\tif math.abs(w.Z) < 0.3 and Vector2.new(w.X, w.Y).Magnitude < F.wheel.R + 0.06 then\n\t\treturn true\n\tend\n\treturn math.abs(lp.X) < F.halfIn and lp.Y > F.dashBottom - 0.15 and lp.Y < F.dashTop + 0.5 and lp.Z > F.dashFront + 0.1 and lp.Z < F.dashFace + 0.35\nend\n-- hideOld: keep the proposed (REPLACES[...] or insideNew(cab, ...)) conditions for BasePart and SurfaceGui (REPLACES is checked first, so RadioPanel is still hidden)."
  },
  {
   "rank": 3,
   "ok": false,
   "problem": "Most of the layout checks out. vy=2.177 sits under the SCurveChin (bottom 2.287). Vent rims span x ±0.535, clear of SCurveDrop. Climate strip spans 1.70-1.92 inside StackBack (1.677-2.097). The StackLower guard is unneeded for sonata and taxi. The problem is that both panels still float. StackBack is depth 0.06 at face (back at face-0.03) and StackLower's back is at face-0.035. They cover y 1.53-2.07, where the dash surface is the recessed DashLower face at face-0.08 (z -2.03). So both stand 0.045-0.05 off the dash with an open gap behind them, and from the centre or passenger view they still read as a thin add-on plate (the boxy radio look). The thinner StackBack also leaves the -8 degree ClimateStrip's lower back edge 0.03 off the stack face. The chrome line (front at face+0.027) and the ambient strip end only 0.003 behind the StackBack face, which will z-fight. The 0.09 Hazard overlaps the vent rims (inner rim edge ±0.025) by 0.02. The Hazard's back also floats 0.01 off the pad.",
   "correctedCode": "-- Dash.luau g == \"line\" (replace HEAD lines 232-250):\n\t\t-- 화면 바로 아래 가로 송풍구 2 + 가운데 비상등 (화면 턱 아래로, 가리지 않게). 안쪽 테두리 끝 ±0.045 = 비상등 폭\n\t\tlocal vy = math.min(top - 0.24, scrY - ch / 2 - 0.19)\n\t\tfor _, s in { -1, 1 } do\n\t\t\tvent(K, P, \"CentreVent\", CFrame.new(cx + s * 0.29, vy, face + 0.01), 0.42, 0.1)\n\t\tend\n\t\tK:box(\"Hazard\", Vector3.new(0.09, 0.07, 0.04), CFrame.new(cx, vy, face + 0.02), P.hazard)\n\t\t-- 끝 송풍구 (날개 끝, 크롬 라인 위)\n\t\tfor _, s in { -1, 1 } do\n\t\t\tvent(K, P, \"SideVent\", CFrame.new(s * (half - 0.38), ly + 0.17, face + 0.01), 0.46, 0.12)\n\t\tend\n\t\t-- 스택 둘레는 대시와 같은 소프트 패드: 앞면 face+0.045, 뒤는 0.08 들어간 아래 대시 면(face-0.08) 속 face-0.11 까지\n\t\t-- (옆에서 봐도 떠 있는 판이 아님; 크롬 라인 · 앰비언트 끝이 0.018 묻힘, 기울어진 공조 띠 아래 끝 틈 0.015)\n\t\tlocal ky = vy - 0.17\n\t\tlocal cyc = ky - 0.2\n\t\tlocal sTop, sMid = vy - 0.09, cyc - 0.13\n\t\tK:panel(\"StackBack\", 1.3, sTop - sMid, 0.155, 0.1, CFrame.new(cx, (sTop + sMid) / 2, face - 0.0325), P.soft)\n\t\tif sMid > conTop then\n\t\t\tlocal lw = (if con then math.min(con.w, 1.15) else 0.9) + 0.06\n\t\t\tK:panel(\"StackLower\", lw, sMid - conTop + 0.06, 0.145, 0.08, CFrame.new(cx, (sMid + conTop) / 2 + 0.03, face - 0.0375), P.soft)\n\t\tend\n-- (AvnKeys / AvnTrim / buttonRow / AvnKnob* / climate(..., cyc, face + 0.07) unchanged)"
  },
  {
   "rank": 4,
   "ok": true,
   "problem": "",
   "correctedCode": ""
  },
  {
   "rank": 5,
   "ok": false,
   "problem": "The Sonata numbers check out. Front armY is 1.73 and rear 1.78. The handle cup (2.09-2.27) sits above the 2.035-2.065 satin line. IMS (1.92-1.96) fits between the armrest top (1.795) and the ambient strip (1.995). The armrest's inner x (2.20) clears the seat, bolster and switches (at most 2.19). But the change is generic and ignores the other door garnish bands. G80: armY becomes 1.79, so the armrest (1.725-1.855) swallows DoorChrome (1.796), the door ambient (1.826) and the bottom of the wood band (1.816-1.976), and the window-switch tops (1.90) sit inside the band. Tucson: armY becomes 2.10, so the armrest (2.035-2.165) swallows the upper waterfall satin line (2.077). Carnival (2.14) happens to sit above its metal band and is fine. Separately, math.clamp(x, min, y1-0.62) throws if y1-0.62 < min; HEAD guards this with math.max.",
   "correctedCode": "-- Trim.luau doorCard: replace HEAD lines 61-88 (arm/handle/IMS). g, lineY, upY0 are defined above.\n\t-- 문 가니시 띠의 아래 · 위 끝 (팔걸이 · 창문 스위치 · 손잡이 컵 · IMS 가 띠를 뚫지 않게)\n\tlocal bandLo, bandHi = math.huge, -math.huge\n\tif g == \"line\" then\n\t\tbandLo, bandHi = lineY - 0.06, lineY + 0.02 -- 새틴 라인 + 바로 아래 앰비언트\n\telseif g == \"wood\" then\n\t\tbandLo, bandHi = upY0 - 0.01, upY0 + 0.18 -- 크롬 + 우드 띠\n\telseif g == \"waterfall\" then\n\t\tbandLo, bandHi = upY0 + 0.02, upY0 + 0.155 -- 앰비언트 + 새틴 두 줄\n\telseif g == \"metal_wood\" then\n\t\tbandLo, bandHi = upY0 - 0.04, upY0 + 0.15 -- 우드 + 금속 띠\n\tend\n\t-- 팔걸이 + 창문 스위치\n\t-- 팔걸이: 그 문 쪽 좌석 쿠션 위 0.5 (팔꿈치 높이). 팔걸이 밑(-0.065) ~ 스위치 윗면(+0.11)이 띠와 겹치면 띠 바로 아래로\n\tlocal cushTop = y0 + lowH\n\tfor _, s in (if front then F.front else F.rear) do\n\t\tif s.w >= 2.6 or (s.x < 0) == (side < 0) then\n\t\t\tcushTop = s.cush.Y + s.cushSize.Y / 2\n\t\tend\n\tend\n\tlocal armMin = y0 + lowH + 0.02\n\tlocal armY = math.clamp(cushTop + 0.5, armMin, math.max(armMin, y1 - 0.62))\n\tif armY + 0.11 > bandLo and armY - 0.075 < bandHi then\n\t\tarmY = math.max(armMin, bandLo - 0.13)\n\tend\n\tlocal armZ = zc + len * 0.08\n\tK:rbox(\"DoorArmrest\", Vector3.new(len * 0.55, 0.13, armDepth), 0.06, CFrame.new(x + inward * (0.02 + armDepth / 2), armY, armZ) * CFrame.Angles(0, math.pi / 2, 0), P.leather)\n\tlocal sw = CFrame.new(x + inward * (0.02 + armDepth / 2), armY + 0.075, armZ - len * 0.14)\n\tK:slab(\"WindowSwitches\", 0.2, if driver then 0.5 else 0.22, 0.025, 0.06, sw, P.gloss)\n\tfor i = 0, (if driver then 3 else 0) do\n\t\tK:box(\"WindowSwitch\", Vector3.new(0.08, 0.03, 0.07), sw * CFrame.new(0, 0.02, (if driver then -0.16 else 0) + i * 0.105), P.button)\n\tend\n\t-- 손잡이 컵 + 크롬 핸들 (문 앞쪽): 팔걸이가 띠 아래면 컵(±0.09)과 IMS 가 띠 위에 오게\n\tlocal hz = if front then math.max(z0 + 0.42, (F.dashFace :: number) + 0.35) else z0 + 0.42\n\tlocal hy = armY + 0.45\n\tif armY < bandLo then\n\t\thy = math.max(hy, bandHi + (if g == \"line\" then 0.11 else 0.18))\n\tend\n\tK:ell(\"HandleCup\", Vector3.new(0.06, 0.18, 0.46), CFrame.new(x + inward * 0.055, hy, hz), P.duct)\n\tK:capsule(\"DoorHandle\", Vector3.new(x + inward * 0.085, hy + 0.01, hz - 0.14), Vector3.new(x + inward * 0.085, hy + 0.01, hz + 0.14), 0.05, P.chrome)\n\tK:box(\"LockTab\", Vector3.new(0.05, 0.05, 0.08), CFrame.new(x + inward * 0.09, hy, hz + 0.27), P.button)\n\t-- IMS 시트 메모리 (1 · 2 · SET, 운전석 문): 쏘나타 = 팔걸이와 앰비언트 사이, G80 = 우드 띠 위 · 손잡이 아래\n\tif driver and (S.key == \"sonata\" or S.key == \"g80\") then\n\t\tfor i = 0, 2 do\n\t\t\tK:box(\"ImsButton\", Vector3.new(0.03, 0.045, 0.07), CFrame.new(x + inward * 0.08, if g == \"line\" then hy - 0.24 else hy - 0.14, hz - 0.1 + i * 0.09), P.alloy)\n\t\tend\n\tend\n-- Results: Sonata unchanged (front 1.73 / rear 1.78, hy 2.18, IMS 1.94). G80 armY 1.656 (switch top 1.766 < chrome 1.788), hy 2.156, IMS 2.016 above the wood. Tucson armY 1.827 (switch top 1.937 < ambient 1.957). Carnival 2.14 kept (above its band). Ray/Porter/Solati unchanged."
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
   "ok": false,
   "problem": "The Sonata placement is right. The button sits at (-0.86, 1.83, -2.01) with the ring seated on the DashLower face (-2.03). It is 0.11 outside the 1.3-wide stack, below the chrome line and ambient strip (from 1.995), and above the knee panel (about 1.59). G80 (x -0.86, 0.08 clear of the 1.36 climate hang) and Ray (0.11 clear of the 1.30 pod, below the column shroud) are also fine. The generic offset breaks the Tucson. Its button (x -0.96 to -0.76, y 1.89-2.09, z face-0.06) lands right behind the two waterfall satin rods, which drop beside the stack at x -0.79 and -0.85 (z face+0.014, from y 2.24/2.16 down to conTop 1.90). The button ends up caged behind two bars. The 'clears the Tucson stack' claim only checked the stack panel.",
   "correctedCode": "-- Cockpit.luau Cockpit.build (HEAD lines 393-400):\n\tif S.startButton and S.shifter ~= \"dial\" then -- 카니발: 콘솔 충전 패드 옆 (Console)\n\t\t-- 센터 스택(반폭 ~0.65 + 테두리) 바깥, 크롬 라인 아래 대시 아랫면(대시 면보다 0.08 안쪽)에 붙임.\n\t\t-- 투싼: 스택(폭 화면 + 0.5) 옆으로 흘러내리는 새틴 두 줄(스택 반폭 + 0.04 / + 0.10)보다 바깥\n\t\tlocal scx = if F.console then F.console.x else 0\n\t\tlocal clear = if S.garnish == \"waterfall\" then ((F.centerW or 1) + 0.5) / 2 + 0.23 else 0.86\n\t\tlocal off = math.min(F.wheel.R + 0.32, math.abs(scx - W.Position.X) - clear)\n\t\tlocal sb = CFrame.new(W.Position.X - F.side * off, F.dashMidY - 0.12, F.dashFace - 0.06)\n\t\tK:cyl(\"StartRing\", 0.04, 0.2, sb * ROT_X_TO_Z, P.chrome)\n\t\tK:cyl(\"StartButton\", 0.05, 0.15, sb * CFrame.new(0, 0, 0.012) * ROT_X_TO_Z, P.startBtn)\n\tend\n-- Tucson: x = -0.98, ring -1.08..-0.88, 0.017 outside the outer rod (-0.863); the column shroud's end is 0.09 nearer the driver, so they do not intersect. Sonata/G80/Ray unchanged (-0.86)."
  },
  {
   "rank": 9,
   "ok": false,
   "problem": "Fine on the Sonata deck: the ring bottom (1.557) is under the deck top (1.57), and the bands step up by only 0.002. But cupholders() is shared. Ray's lowTray calls it at c.y = y+0.03 with the LowTray top at y+0.02. With the new +0.012 lift the ring spans y+0.027 to y+0.057, so all three discs float 0.007 above the tray as a 0.03-tall puck, which is the very defect being fixed. Before the change the ring at c was buried 0.005. Remove the extra 0.012 lift. The optional PalmRest is fine: 1.56-1.64, gz+0.37 to gz+0.87 = -0.745 to -0.245, clear of the armrest at about -0.02, and only its tip meets the end of the shift panel.",
   "correctedCode": "-- Console.luau cupholders():\n\t\t-- 오목해 보이게: 새틴 테두리(바깥) -> 대시색 안쪽 벽 띠 -> 검은 바닥. 바깥 링은 원래 높이(c)에 두어 레이 낮은 트레이\n\t\t-- (윗면 = c - 0.01)에도 묻히게, 안쪽으로 0.002 씩만 위로 (z-fighting 방지, 옆면이 거의 안 보임)\n\t\tK:cyl(\"CupholderRing\", 0.03, 0.31, c * ROT_X_TO_Y, P.satin)\n\t\tK:cyl(\"CupholderWall\", 0.03, 0.28, c * CFrame.new(0, 0.002, 0) * ROT_X_TO_Y, P.hard)\n\t\tK:cyl(\"Cupholder\", 0.03, 0.2, c * CFrame.new(0, 0.004, 0) * ROT_X_TO_Y, P.duct)\n-- optional (buttons_col):\n\t\tK:ell(\"PalmRest\", Vector3.new(0.3, 0.08, 0.5), CFrame.new(gx, top + 0.03, gz + 0.62), P.leather)"
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
  }
 ]
}
```

## verify:sonata_taxi

```json
{
 "car": "sonata_taxi (Hyundai Sonata DN8 LPi 개인택시). Checked against the current HEAD ac9ae56. Proposals 2-12 were already applied in d3edf45, identically or nearly so. I checked them with the Luau harness at /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/wf/taxi_verify (run.luau dumps every part's OBB for the taxi fixture; out_head2.txt is the HEAD dump) and with the styles3 (before) and styles4 (after) renders.",
 "checked": [
  {
   "rank": 1,
   "ok": false,
   "problem": "The diagnosis is wrong. DashRoll is a cylinder with radius 0.13 centred at z = face-0.13 (-2.08), so it reaches the face plane only at its equator, y = top-0.13 = 2.375. At the vent heights its surface is 0.03-0.07 behind the face. CentreVent rims (y 2.18..2.35), SideVent rims (y 2.125..2.315), ducts, slats and the Hazard all have their fronts at face+0.02..+0.06, in front of the roll. The harness dump and the styles3 and styles4 crops both show complete rims and a full hazard switch. The OLD snippet also no longer exists in HEAD: vy = math.min(top - 0.24, scrY - ch / 2 - 0.19), vents at cx ± 0.29 with w 0.42, Hazard at face + 0.02, and StackBack is now 0.155 deep (front at face+0.045) with sTop = vy - 0.09, so there is no `sy0, sy1` line. Moving vy down 0.12 would drag the AVN row, the climate strip and StackLower down for no gain. The only real clipping is at the outer end of each SideVent, not the top: the outer ~0.06 of the rim (|x| >= 2.385) sits up to 0.005 inside the vertical DashEndRoll (centre x ±2.42, front z face+0.03). Moving the side vents 0.07 inboard clears it (rim outer end 2.375; the roll front there is face+0.022, behind the rim front at face+0.025). This also clears the taxi ID card (x <= 1.49).",
   "correctedCode": "-- Dash.luau, Dash.build, `if g == \"line\" then`: keep vy / CentreVent / Hazard / StackBack exactly as in HEAD.\n-- Change only the side-vent x so the rim's outer end clears the vertical DashEndRoll (x ±(half-0.14), r 0.13, front face+0.03):\n\t\t-- 끝 송풍구 (날개 끝, 크롬 라인 위) - 문 쪽 세로 롤(DashEndRoll)에 바깥 끝이 묻히지 않게 0.07 안쪽으로\n\t\tfor _, s in { -1, 1 } do\n\t\t\tvent(K, P, \"SideVent\", CFrame.new(s * (half - 0.45), ly + 0.17, face + 0.01), 0.46, 0.12)\n\t\tend"
  },
  {
   "rank": 2,
   "ok": false,
   "problem": "The Trim block is correct and already in HEAD, using P.meterGlass instead of the inline look. Details: Gauges.digits(K, frame, n, h, look, static) matches. The window (0.32x0.10, mirror-local x +0.17, z 0.060..0.064) sits on the glass front at 0.060. The digits span local x 0.111..0.289, inside the 0.01..0.33 window, and read left-to-right toward the occupants. The LED sits at local x 0.05. The keys hang under the round-bottomed body (y -0.1425..-0.1175). The remaining problem: the original Car_Taxi Interior still has a `TaxiMeter` part, a 0.70x0.22x0.30 black box with a SurfaceGui at car (0.90, 2.54, -2.20) on the dash top just right of the new 8\" screen. init.client.luau's KEEP list ({\"Taxi\",\"Meter\",...}) exempts it from insideNew, so in Roblox it stays visible: two fare meters, with this box in front of the left end of the new VacancySign (x 1.13..1.77). The studio car skin hides it, which is why it is missing from the renders. Nothing references TaxiMeter except Fit's F.taxi flag, which is read at fit time. The legacy VacantSign is already hidden by insideNew.",
   "correctedCode": "-- Trim.luau: keep the HEAD mirror-meter block unchanged.\n-- init.client.luau, insideNew(): hide the legacy dash-top TaxiMeter box when the mirror meter replaces it\nlocal function insideNew(cab: any, p: Instance): boolean\n\tif not p:IsA(\"BasePart\") then\n\t\treturn false\n\tend\n\tlocal F = cab.fit\n\t-- 개인택시: 룸미러 일체형 미터기(Trim)가 요금을 보여 주므로 옛 대시 위 TaxiMeter 상자는 숨김 (순찰차는 미터 없음)\n\tif p.Name == \"TaxiMeter\" and F.style and F.style.key == \"sonata_taxi\" and F.kind ~= \"police\" then\n\t\treturn true\n\tend\n\tfor _, k in KEEP do\n\t\tif string.find(p.Name, k, 1, true) then\n\t\t\treturn false\n\t\tend\n\tend\n\tlocal lp = cab.base.CFrame:PointToObjectSpace((p :: BasePart).Position)\n\tlocal w = F.wheel.cf:PointToObjectSpace(lp)\n\tif math.abs(w.Z) < 0.3 and Vector2.new(w.X, w.Y).Magnitude < F.wheel.R + 0.06 then\n\t\treturn true\n\tend\n\treturn math.abs(lp.X) < F.halfIn and lp.Y > F.dashBottom - 0.15 and lp.Y < F.dashTop + 0.5 and lp.Z > F.dashFront + 0.1 and lp.Z < F.dashFace + 0.35\nend"
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
   "ok": false,
   "problem": "The placement is fine for the taxi in isolation, but HEAD already does this differently. Its block is `if S.startButton and S.shifter ~= \"dial\" then` with clear = 0.86, or a waterfall-specific value for Tucson, and off = math.min(R + 0.32, |scx - W.X| - clear). That puts the taxi ring at x -0.96..-0.76, y 1.73..1.93, z -2.03..-1.99: flush on the recessed DashLower face, clear of StackBack (|x| <= 0.65), ColumnShroud (x <= -1.07) and KneePanel (top 1.585), and visible through the wheel in the styles4 renders. The proposal's OLD line is gone. Rebasing its NEW block onto HEAD would drop the Carnival `S.shifter ~= \"dial\"` exclusion (Console builds the Carnival button, so it would appear twice), the Tucson waterfall-rod clearance and the Genesis gloss button. That breaks other cars.",
   "correctedCode": "-- No change: keep the current Cockpit.build start-button block (HEAD ac9ae56):\n\tif S.startButton and S.shifter ~= \"dial\" then -- 카니발: 콘솔 충전 패드 옆 (Console)\n\t\tlocal scx = if F.console then F.console.x else 0\n\t\tlocal clear = if S.garnish == \"waterfall\" then ((F.centerW or 1) + 0.5) / 2 + 0.23 else 0.86\n\t\tlocal off = math.min(F.wheel.R + 0.32, math.abs(scx - W.Position.X) - clear)\n\t\tlocal sb = CFrame.new(W.Position.X - F.side * off, F.dashMidY - 0.12, F.dashFace - 0.06)\n\t\t-- (StartRing / StartButton unchanged)"
  },
  {
   "rank": 11,
   "ok": true,
   "problem": "",
   "correctedCode": ""
  },
  {
   "rank": 12,
   "ok": true,
   "problem": "",
   "correctedCode": ""
  }
 ]
}
```

## verify:tucson

```json
{
 "car": "tucson",
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
   "ok": false,
   "problem": "The geometry is as described: lid x 1.02..2.27, y 1.61..2.01, z -1.63..-1.60, pull at y 1.96 and z -1.60..-1.58. The visual claim is wrong, though. Kit:panel rounds only the corners seen from +Z. The lid's front face has sharp 90-degree perimeter edges, so there is no rounded edge to catch the light. The result is a 0.03 step in the same P.lower colour on a P.lower face, and the glovebox outline almost disappears; only a dark bar remains. The real NX4 lid has a visible shut line. Commit ac9ae56 gave every other model a rounded dark GloveGap with an inset lid, so Tucson would now be the only car without a readable glovebox. Fix: keep the smooth lid and dark pull, and add a thin, dark, rounded shut line behind the lid. This adds 6 more parts, for +8 in total instead of +2.",
   "correctedCode": "-- Dash.luau  body(): waterfall branch of the glovebox (keep the current else-branch unchanged)\nif S.garnish == \"waterfall\" then\n\t-- NX4: smooth lid in the lower layer + thin dark rounded shut line (no drawer frame, no chrome bar) + dark finger pull under the satin lines\n\tlocal gc = CFrame.new(gx, gy, face - 0.075)\n\tK:panel(\"GloveGap\", gw, gh, 0.01, 0.07, gc, P.hardDark) -- z -1.63..-1.62 (0.01 proud of DashLower at face - 0.08)\n\tK:panel(\"GloveLid\", gw - 0.03, gh - 0.03, 0.03, 0.06, CFrame.new(gx, gy, face - 0.065), P.lower) -- z -1.63..-1.60; a 0.015 dark ring shows around it\n\tK:box(\"GlovePull\", Vector3.new(0.3, 0.04, 0.02), CFrame.new(gx, gTop - 0.06, face - 0.04), P.hardDark) -- y 1.93..1.97, inside the lid (top 1.995)\nelse\n\t-- (existing rounded GloveGap / GloveLid / GloveRecess / GloveHandle branch, unchanged)\nend"
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
   "ok": false,
   "problem": "The proposed OverheadBelly ellipsoid (0.74 x 0.06 x 0.46 at oc - 0.03) is only 0.06 deep at its centre, and its underside curves up toward the edges. The existing flat parts, kept at oc - 0.065 (top at -0.055), end up hanging below it. The outer ends of the MapLamp tiles (x 0.32, z 0.08) sit about 0.014 below the belly. Carnival's SlideDoorSwitch tiles at (+-0.24, z -0.16) are 0.005 to 0.035 below the belly or below the slab underside (oc - 0.02). That breaks another car (carnival). The belly is also unnecessary: the 0.12-thick slab already gives rounded plan corners seen from below, which was the complaint. The tree now has a better version: an unchanged flat underside at oc - 0.06, lenses half-sunk into it, a round SOS, and porter excluded. VanityCover set to P.pillar is fine.",
   "correctedCode": "-- Trim.luau  Trim.build: overhead console (no belly)\nlocal oc = CFrame.new(0, roofY - 0.06, lz0 + 0.45)\nif F.style.key ~= \"porter\" then\n\t-- rounded plan corners seen from below (slab), flat underside at oc - 0.06 so lamps / SOS / switches (incl. Carnival slide-door keys at -0.065) stay seated\n\tK:slab(\"OverheadConsole\", 0.78, 0.5, 0.12, 0.16, oc, P.hard)\n\tfor _, s in { -1, 1 } do\n\t\tK:ell(\"MapLamp\", Vector3.new(0.2, 0.024, 0.13), oc * CFrame.new(s * 0.22, -0.06, 0.02), P.lampLens) -- lens half-sunk in the underside\n\tend\n\tK:cyl(\"SOS\", 0.016, 0.065, oc * CFrame.new(0, -0.064, 0.15) * CFrame.Angles(0, 0, math.pi / 2), P.hazard)\n\tK:box(\"RoofSwitch\", Vector3.new(0.14, 0.02, 0.06), oc * CFrame.new(0, -0.065, -0.12), P.button)\nend\n-- visor loop:\nif F.style.key ~= \"porter\" then\n\tK:box(\"VanityCover\", Vector3.new(0.5, 0.012, 0.26), v * CFrame.new(-s * 0.1, -0.035, 0.04), P.pillar)\nend"
  },
  {
   "rank": 9,
   "ok": true,
   "problem": "",
   "correctedCode": ""
  }
 ]
}
```

## verify:g80

```json
{
 "car": "g80",
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
   "ok": true,
   "problem": "",
   "correctedCode": ""
  },
  {
   "rank": 4,
   "ok": false,
   "problem": "Three geometry faults in the code as proposed. (1) The handle parts collide with the new wood band. Without band-avoid logic, hy = armY + 0.45 = 2.24 (rear door 2.29), which is inside the band (2.11..2.35, inward 0.025..0.075). HandleCup (inward 0.025..0.085) is buried and shows only a 0.01 black sliver. DoorHandle (inward 0.06..0.11) and LockTab cut through the wood. The claim of no collision with the IMS keys at hy-0.24 = 2.0 is wrong: for g ~= \"line\" the IMS sits at hy-0.14 = 2.10 (2.078..2.123), across the band's lower edge at 2.11. (2) DoorChrome floats. It is at inward 0.07 with r 0.008, so it spans 0.062..0.078, while DoorUpper's inner face is at inward 0.045. The lip hangs 0.017 in the air above the band. DoorAmbient (inward 0.06..0.08) likewise floats off the face and off the band's rounded top. (3) woodY is computed for every car with an unguarded math.clamp, which errors when min > max (upY0+0.12 > y1-0.3, i.e. door span < 1.53). No current model hits this, but it is fragile; HEAD already guards it with math.max. A further fault is in HEAD's own later band-avoid rule: hy = bandHi + 0.18 = 2.59 puts the cup at 2.50..2.68, so its top third goes into the DoorSill roll (centre y1-0.02 = 2.675, r 0.07, underside about 2.62 at the cup). The fix below keeps the band height and DoorChrome at 2.395, matching the dash vent lip, which was the point of the fix.",
   "correctedCode": "-- Trim.luau doorCard()\n\tlocal lineY = if g == \"line\" then math.clamp((F.dashMidY :: number) + 0.1, upY0 + 0.06, y1 - 0.08) else upY0 + 0.1\n\t-- G80: 대시 우드 띠 가운데 높이 (Dash: sy = top - 0.2, wy = sy - 0.2). min > max 면 math.clamp 에러 -> max 보호\n\tlocal woodY = math.clamp((F.dashTop :: number) - 0.4, upY0 + 0.12, math.max(upY0 + 0.12, y1 - 0.3))\n\tif g == \"line\" then\n\t\tK:cyl(\"DoorTrimBand\", len - 0.4, 0.03, CFrame.new(x + inward * 0.06, lineY, zc) * AZ, P.trim)\n\telseif g == \"wood\" then\n\t\t-- 우드 띠(0.24) + 위 크롬 립(송풍구 아래 립 높이)이 대시에서 문으로 끊김 없이. 립은 DoorUpper 안쪽 면(inward 0.045)에 닿게\n\t\tK:zbox(\"DoorTrimBand\", Vector3.new(0.05, 0.24, len - 0.4), 0.024, CFrame.new(x + inward * 0.05, woodY, zc), P.trim)\n\t\tK:cyl(\"DoorChrome\", len - 0.42, 0.016, CFrame.new(x + inward * 0.054, woodY + 0.165, zc) * AZ, P.chrome)\n\telseif g == \"waterfall\" then\n\t\t-- (unchanged)\n\telseif g == \"metal_wood\" then\n\t\t-- (unchanged)\n\tend\n\tif P.ambient then\n\t\tK:cyl(\"DoorAmbient\", len - 0.6, 0.02, CFrame.new(x + inward * (if g == \"wood\" then 0.058 else 0.07), if g == \"line\" then lineY - 0.045 elseif g == \"wood\" then woodY + 0.13 else upY0 + 0.03, zc) * AZ, P.ambient)\n\tend\n\t-- (keep HEAD's bandLo/bandHi block and armrest/armY logic unchanged: wood -> bandLo, bandHi = woodY - 0.12, woodY + 0.18)\n\n\t-- 손잡이 컵 + 크롬 핸들 (문 앞쪽)\n\tlocal hz = if front then math.max(z0 + 0.42, (F.dashFace :: number) + 0.35) else z0 + 0.42\n\tlocal hy = armY + 0.45\n\tlocal imsY = if g == \"line\" then hy - 0.24 else hy - 0.14\n\tlocal imsZ = hz - 0.1\n\tif armY < bandLo then\n\t\tif g == \"wood\" then\n\t\t\t-- G80: 컵(±0.09)을 크롬 립(bandHi)과 창틀 롤(y1 - 0.02, r 0.07) 사이에 끼움 (G80: hy 2.51 -> 컵 2.42..2.60,\n\t\t\t-- 립 윗끝 2.403 · 창틀 아랫면 ~2.62 사이). IMS 는 같은 높이로 잠금 탭 뒤 (z hz + 0.36 ..)\n\t\t\thy = math.max(hy, math.min(bandHi + 0.1, y1 - 0.18))\n\t\t\timsY, imsZ = hy, hz + 0.36\n\t\telse\n\t\t\thy = math.max(hy, bandHi + (if g == \"line\" then 0.11 else 0.18))\n\t\t\timsY = if g == \"line\" then hy - 0.24 else hy - 0.14\n\t\tend\n\tend\n\tK:ell(\"HandleCup\", Vector3.new(0.06, 0.18, 0.46), CFrame.new(x + inward * 0.055, hy, hz), P.duct)\n\tK:capsule(\"DoorHandle\", Vector3.new(x + inward * 0.085, hy + 0.01, hz - 0.14), Vector3.new(x + inward * 0.085, hy + 0.01, hz + 0.14), 0.05, P.chrome)\n\tK:box(\"LockTab\", Vector3.new(0.05, 0.05, 0.08), CFrame.new(x + inward * 0.09, hy, hz + 0.27), P.button)\n\t-- IMS 시트 메모리 (1 · 2 · SET, 운전석 문)\n\tif driver and (S.key == \"sonata\" or S.key == \"g80\") then\n\t\tfor i = 0, 2 do\n\t\t\tK:box(\"ImsButton\", Vector3.new(0.03, 0.045, 0.07), CFrame.new(x + inward * 0.08, imsY, imsZ + i * 0.09), P.alloy)\n\t\tend\n\tend"
  },
  {
   "rank": 5,
   "ok": false,
   "problem": "Geometry is otherwise right. Both lips (2.395/2.465, r 0.008) sit on the flat DashUpper face below top-rr = 2.50. The upper lip top (2.473) stays about 0.005 below the screen housing and bezel bottoms (2.478..2.484), and the VentTabs fit between the lips. The problem is the slot face: HairlineVent's front is at face+0.002, a 5-stud-wide face only 0.002 in front of DashUpper's front face at exactly `face`. That is close enough to coplanar to z-fight (black duct vs dark leather shimmer) when the cabin is seen from tens of studs away through the windscreen of a parked car. The lips also float 0.004 off the face (back at face+0.004). Move the slot face to face+0.006 and seat the lips on the face. They still stand 0.012 proud of the slot, and the VentTabs (front face+0.04) still stand in front of the gap.",
   "correctedCode": "-- Dash.luau, Dash.build, g == \"wood\"\n\t\tlocal sy = top - 0.2\n\t\t-- 슬롯 앞면 face + 0.006 (대시 면과 0.002 차이면 멀리서 z-fighting) + 대시 면에 닿은 위 · 아래 크롬 립 2줄 (슬롯보다 0.012 앞)\n\t\tK:panel(\"HairlineVent\", width - 0.3, 0.05, 0.06, 0.024, CFrame.new(0, sy, face - 0.024), P.duct)\n\t\tfor _, ly in { sy + 0.035, sy - 0.035 } do\n\t\t\tK:cyl(\"HairlineLip\", width - 0.32, 0.016, CFrame.new(0, ly, face + 0.01), P.chrome)\n\t\tend"
  },
  {
   "rank": 6,
   "ok": false,
   "problem": "The stadium pad and crown are correct. panel(w 0.62, h 0.40, d 0.11, r 0.196) becomes rbox r 0.196 and gives a pill shape with its front at z 0.085. The crown front is at 0.12 and the emblem at 0.122 sits on the crown, with the wings floating at most 0.006 at their tips. The spoke ends and button panels are hidden in the pad, and the Roller just touches the pad's rounded end. The fault is that the existing G80 HubChin now sticks out in front of the flatter pad. HubChin is ell(0.341, 0.2, hub.Z*0.85 = 0.17) at z 0.04, so its front is at 0.125. Its centre is at y -0.174, where the pad face is 0.085 and the crown only about 0.099. That puts a lump 0.03-0.04 proud on the lower third of the pad, which is exactly the 'fairly flat face' the fix wants to remove. Under the old egg dome (front about 0.129 at that height) the chin was hidden. Make the chin shallower and move it back so it only shows as a small rounded lip below the pad's lower edge (y -0.23..-0.274), set back from the pad face.",
   "correctedCode": "-- Cockpit.luau wheel(): (pad + crown branch as proposed)\n\t\telseif kind == \"two\" then\n\t\t\t-- G80 RG3: 가로로 넓은 알약(스타디움)형 납작한 패드 + 얕은 크라운 (달걀형 돔 X)\n\t\t\tK:panel(\"Airbag\", hub.X, hub.Y, hub.Z * 0.55, hub.Y / 2 - 0.004, W * CFrame.new(0, hy, 0.03), P.wheelHub)\n\t\t\tK:ell(\"AirbagCrown\", Vector3.new(hub.X * 0.86, hub.Y * 0.78, 0.07), W * CFrame.new(0, hy, 0.03 + hub.Z * 0.275), P.wheelHub)\n\n-- and the existing G80 chin (after the spokes loop):\n-- old:\n\t\telseif kind == \"two\" then\n\t\t\tK:ell(\"HubChin\", Vector3.new(hub.X * 0.55, hub.Y * 0.5, hub.Z * 0.85), W * CFrame.new(0, hy - hub.Y * 0.36, 0.04), P.wheelHub)\n-- new:\n\t\telseif kind == \"two\" then\n\t\t\t-- G80: 아래가 비어 있고 허브가 아래로 조금 불룩. 납작한 패드(앞 z 0.085)보다 앞으로 튀지 않게 (앞 z 0.08), 패드 아래 끝 밑으로만 보이는 턱\n\t\t\tK:ell(\"HubChin\", Vector3.new(hub.X * 0.55, hub.Y * 0.5, hub.Z * 0.5), W * CFrame.new(0, hy - hub.Y * 0.36, 0.03), P.wheelHub)\n\n-- emblem line as proposed:\n\t\temblem(K, P, S.brand, W * CFrame.new(0, hy + 0.005, if kind == \"two\" then 0.03 + hub.Z * 0.275 + 0.037 else 0.06 + hub.Z / 2 + 0.002))"
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
  }
 ]
}
```

## verify:ray

```json
{
 "car": "ray",
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
   "problem": "The code is valid and gated: lowTray runs only for the Ray, and StackFoot only in pod_v. Three problems remain (checked in an offline Luau sim of the Ray fixture car_43395, which has the same fit as the GS25 Ray). (a) The premise is wrong. LowTray is 0.16 tall at y 0.595..0.755 and the carpet top is 0.36, so the tray never sat on the floor. After the move it is a shelf hanging off the foot with a 0.235 gap underneath. (b) StackFoot's occupant face is at face+0.17 (-1.88), which is 0.01 in front of the satin StackPod front (face+0.16 = -1.89). Its top (1.095) sits above the pod bottom (1.035), so its top corners cover the pod's lower satin rim across x +-0.46. (c) zbox rounds the edges parallel to Z, which are the hidden top and bottom corners. The vertical edges the occupants actually see stay square.",
   "correctedCode": "-- Dash.luau, pod_v branch. Replace the current StackFoot line\n--   K:zbox(\"StackFoot\", Vector3.new(pw - 0.34, fy1 - fy0, 0.34), 0.08, CFrame.new(cx, (fy0 + fy1) / 2, face), P.hard)\n-- with (vertical edges rounded: rbox axis = up; face at face+0.15, 0.01 behind the satin pod front, so the pod's lower rim stays visible):\n\t\t\tK:rbox(\"StackFoot\", Vector3.new(fy1 - fy0, pw - 0.34, 0.34), 0.08, CFrame.new(cx, (fy0 + fy1) / 2, face - 0.02) * CFrame.Angles(0, 0, math.pi / 2), P.hard)\n\n-- Console.luau: replace lowTray() (same part count; tray now stands on the carpet, y 0.335..0.755, z -1.90..-1.40, butted to the foot face)\nlocal function lowTray(K: any, F: any, P: any)\n\t-- 레이: 스택 발치 낮은 트레이 + 컵홀더 2 (사이 바닥은 비어 있음)\n\tlocal con = F.console\n\tlocal y = if con then con.top else F.floorY + 0.4\n\tlocal x = if con then con.x else 0\n\tif F.style.key == \"ray\" then\n\t\t-- 레이: StackFoot 뒷면(dashFace + 0.15)에 붙어 바닥에 서 있는 컵홀더 블록 (바닥 위 0.24 떠 있는 선반 X)\n\t\tlocal z = F.dashFace + 0.4\n\t\tlocal h = y + 0.02 - F.floorY\n\t\tK:zbox(\"LowTray\", Vector3.new(0.72, h, 0.5), 0.07, CFrame.new(x, F.floorY + h / 2, z), P.hard)\n\t\tcupholders(K, P, x, y + 0.03, z, false)\n\t\treturn\n\tend\n\tlocal z = if con then math.max(con.z0, F.dashFace) + 0.32 else F.dashFace + 0.32\n\tK:zbox(\"LowTray\", Vector3.new(0.72, 0.16, 0.5), 0.07, CFrame.new(x, y - 0.06, z), P.hard)\n\tcupholders(K, P, x, y + 0.03, z, false)\nend"
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
   "ok": false,
   "problem": "Gating (C.cowl is Ray-only), the ell and ClusterBack swap, the -6 parts delta and the claim that the front stays behind the bezel (local z -0.03 vs bezel back -0.027) all check out. The ears are gone in styles5. But the cowl does not reach the dash. Its y and z semi-axes are both 0.31, so its lowest point is 2.791 - 0.31 = 2.481, which is 0.026 above the dash top (2.455). ClusterBack's lowest point is 2.465. The binnacle is an egg touching the dash at one point, not a visor that falls to the dash. Two smaller points: the hood top at local z -0.34 is 0.381, not 0.374, and at local z -0.45 the cowl top (0.350) pokes 0.004 above the hood.",
   "correctedCode": "-- Cockpit.luau displays(), C.cowl block. Replace\n--   K:ell(\"ClusterCowl\", Vector3.new(hw, h + 0.2, hd), clCF * CFrame.new(0, 0.06, -0.34), P.soft)\n-- with (same top at local +0.37, same front at local z -0.03 behind the bezel; 0.16 deeper downward so the bottom (~2.32) sinks 0.13 into the dash top and the chin wraps over the dash roll; still clears the pod top (gap >= 0.034) and the vent rims; it now also stays under the hood at z -0.45):\n\t\t\tK:ell(\"ClusterCowl\", Vector3.new(hw, h + 0.36, hd), clCF * CFrame.new(0, -0.02, -0.34), P.soft)"
  },
  {
   "rank": 6,
   "ok": false,
   "problem": "The 2-seat loops, outer-only bolsters, skipped seams and the -26 parts delta are correct. The headrests are wrong. The applied guard `if #xs < 2 or (n == 2 and #xs ~= 2)` keeps the model's own 2 rear headrests. In the Ray model these sit at x = +-1.185, the outer positions of a 3-seat bench. The 2 seat backs are centred at +-0.9875, so each headrest sits 0.2 outboard of its back and insert (sim: RearHeadrest x 0.775..1.595 vs BenchBackInsert 0.394..1.579). The +-0.99 default the proposal describes is never reached for this car.",
   "correctedCode": "-- Seats.luau rearBench(). Replace\n--   if #xs < 2 or (n == 2 and #xs ~= 2) then\n-- with (a 2-seat bench always puts its headrests on the seat centres, not on the model's 3-seat positions):\n\tif #xs < 2 or n == 2 then\n\t\txs = { Vector3.new(s.x - edge, 0, 0), Vector3.new(s.x + edge, 0, 0) }\n\tend"
  },
  {
   "rank": 7,
   "ok": false,
   "problem": "The signatures, the Ray-only gate (kind == \"three\") and the icons path (+8 parts) are fine. The 'spoke stays attached' check ignores the r=0.08 corner rounding. The top corners are arcs centred at (+-0.05, -0.272) in the wheel frame. At x = +-0.12 the spoke top is at -0.233 and at x = +-0.13 it is at -0.272. The airbag and HubShell bottoms there are about -0.21. That leaves a see-through notch 0.02-0.06 tall on each side between the spoke's shoulders and the hub. The old 0.16-wide spoke fit fully under the pad.",
   "correctedCode": "-- Cockpit.luau wheel(), if kind == \"three\". Replace\n--   local y0, y1 = hy - hub.Y * 0.45, -(R - 0.03)\n-- with (spoke top -0.12 tucks behind the airbag pad: pad front z 0.145 > spoke front 0.035, pad width 0.44 > 0.26; rounded corners at x=+-0.13 now reach -0.20, above the pad bottom -0.21; the gloss trim (-0.57..-0.17) shows from under the pad down to the rim):\n\t\t\tlocal y0, y1 = hy - hub.Y * 0.25, -(R - 0.03)\n\t\t\t-- (LowerSpoke / LowerSpokeTrim panel lines unchanged)"
  },
  {
   "rank": 8,
   "ok": false,
   "problem": "The numbers assume the default pedal positions, but the Ray model has its own Pedal parts: brake (-1.10, 0.905, -2.55) and gas (-0.63, 0.735, -2.50). So pb = brake + (-0.5, 0.42, -0.12) = (-1.60, 1.325, -2.67). The pad spans y 1.25..1.40, but DashLower's underside is at 1.335 (for z <= -2.13), so the top half of the pad is buried in the dash. The whole PedalArm (y 1.37..1.79, z <= -2.69) is inside DashLower. The result is a rubber stub stuck to the underside of the dash, 0.62 deep in the footwell. Also, the applied code uses a 6-part panel, so the delta is 7 parts, not 2.",
   "correctedCode": "-- Trim.luau, replace the Ray parking-brake block\n\tif F.style.key == \"ray\" and brake then\n\t\t-- 레이: 발 주차 브레이크 - 브레이크 왼쪽 0.5, 0.2 위, 같은 깊이 (모델 페달 z -2.55 기준). 패드는 대시 아랫면보다 0.15 이상 아래\n\t\tlocal pb = brake + Vector3.new(F.side * 0.5, 0.2, 0.05)\n\t\tpb = Vector3.new(pb.X, math.min(pb.Y, F.dashBottom - 0.15), pb.Z)\n\t\tK:panel(\"ParkBrakePedal\", 0.22, 0.15, 0.04, 0.05, CFrame.new(pb) * CFrame.Angles(math.rad(-30), 0, 0), P.rubber)\n\t\t-- 팔: 패드에서 대시 아랫면 속으로 (끝은 항상 DashLower 안)\n\t\tK:seg(\"PedalArm\", pb + Vector3.new(0, 0.06, -0.04), Vector3.new(pb.X, F.dashBottom + 0.12, math.min(pb.Z - 0.32, F.dashFace - 0.3)), 0.045, P.metalDark)\n\tend\n-- Ray result (sim): pad (-1.60, 1.105, -2.50), y 1.03..1.18 (0.15 below the dash underside, 0.14 above the footrest top 0.89), z -2.555..-2.445 (clear of KneePanel z >= -2.38), x -1.71..-1.49 (0.17 from the brake pad); 0.17 of arm visible, arm end (1.455, -2.82) inside DashLower."
  },
  {
   "rank": 9,
   "ok": true,
   "problem": "",
   "correctedCode": ""
  }
 ]
}
```
