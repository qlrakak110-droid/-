/* car_glass.js — 자동차 유리: 검은 반투명 틴팅 + 빛 반사 (광안리 임시 스튜디오 · 차량 외형 전용)
 * Classic script. Load after three.min.js + rblx_gfx, before carskin_model.js / taxi_model.js. Exposes window.GWCarGlass.
 *
 *   GWCarGlass.material(role)        outside pass (FrontSide). role: 'glass' | 'glass_dark' (privacy glass)
 *   GWCarGlass.inner(role)           inside pass (BackSide) for the cabin view; add the inner mesh BEFORE the outer one
 *                                    (same position -> three's stable sort draws far windows' insides first)
 *   GWCarGlass.both(role)            one DoubleSide pass (meshes without a consistent outward winding)
 *   GWCarGlass.prepare(geo, role)    per-window data (attribute cgw = VLT, shade band y0, y1): windows are the connected
 *                                    islands of the mesh; the windshield (front-facing island in the front half, -Z = front)
 *                                    gets a lighter tint and a dark band at the top, every other window the privacy tint
 *   GWCarGlass.lowMaterial()         opaque gloss-black glass for the instanced far LOD (one draw call for all far cars)
 *   GWCarGlass.isGlass(m) / isInner(m)
 *   GWCarGlass.TINT                  VLT presets (visible light transmittance at normal incidence)
 *
 * Shading (replaces the Roblox-glass output line of RblxGfx.adopt, so ambient / sky occlusion / fog stay Roblox-like):
 *   - premultiplied: colour = reflection (+ a little film scatter), alpha = 1 - transmittance, blend One / 1-SrcAlpha:
 *     the windows stay black and see-through while reflections keep full strength at any tint
 *   - Fresnel (n = 1.52): ~4 % mirror head-on, a bright sky mirror at grazing angles; the tint path length grows with the
 *     refraction angle, so windows also turn darker toward the edges of the car, like real tinted glass
 *   - reflections: the sky environment (PMREM IBL; analytic sky gradient on the low tier), a distant city skyline band and
 *     the road below the horizon (lit windows in the skyline at night); sun / street lamp glints from the direct lights,
 *     capped so the bloom stays a glint
 *   - inside the cabin (back faces): the tint is eye-adapted (pow(VLT, insideExp)), the glass mirrors the dim cabin
 *     (dashboard haze on the lower windshield, never the sky) and the instrument glow at night
 */
(function (root) {
  'use strict';
  const THREE = root.THREE;
  if (!THREE) return;
  const G = root.RblxGfx;

  const TINT = {
    glass: 0.2, // 측면·뒷유리: 검은 반투명 (투과 20 %)
    glass_dark: 0.1, // 프라이버시 유리 (솔라티 뒷칸 등)
    windshield: 0.4, // 앞유리: 스모크 틴팅 (운전 시야는 남김)
    band: 0.1, // 앞유리 상단 차광 띠
  };
  const CFG = {
    insideExp: 0.72, // 실내에서 본 투과율 = VLT^insideExp (눈 적응: 옆 0.31, 앞 0.52)
    reflGain: 1.5, // 코팅 유리: 정면 ~6 %, 비스듬하면 거울
    glintMax: 24.0, // 해 / 가로등 하이라이트 상한 (블룸 과다 방지)
    city: 1.0, // 반사 속 스카이라인 세기
    cabin: [0.1, 0.095, 0.09], // 실내에서 유리에 비치는 실내 밝기 계수
  };

  const GLASS_LINE = 'outgoingLight = ( totalDiffuse + totalEmissiveRadiance ) * diffuseColor.a + totalSpecular * 1.6;';

  const VERT_PARS = `
attribute vec3 cgw;
varying vec3 vCgw;
varying float vCgY;
`;
  const VERT_MAIN = `
	vCgw = cgw;
	vCgY = position.y;
`;
  const FRAG_PARS = `
varying vec3 vCgw;
varying float vCgY;
uniform float cgVlt;
uniform float cgInsideExp;
uniform float cgReflGain;
uniform float cgGlintMax;
uniform float cgCity;
uniform vec3 cgCabin;
uniform float cgNightU;
float cgHash( float n ) { return fract( sin( n ) * 43758.5453123 ); }
`;
  // runs where Roblox glass would compute outgoingLight; sets outgoingLight (premultiplied) and diffuseColor.a
  const FRAG_MAIN = `
{
	vec3 cgN = normal; // faces the viewer (three flips it on back faces)
	vec3 cgV = geometry.viewDir;
	float cgNV = clamp( dot( cgN, cgV ), 1e-3, 1.0 );
	float cgF = 0.04 + 0.96 * pow( 1.0 - cgNV, 5.0 );
	bool cgIn = ! gl_FrontFacing;
	// per-window tint, dark shade band at the top of the windshield
	float cgT0 = vCgw.x > 0.0 ? vCgw.x : cgVlt;
	float cgWs = step( 0.4, cgT0 );
	if ( vCgw.z > vCgw.y ) cgT0 = mix( cgT0, min( cgT0, ${TINT.band.toFixed(3)} ), smoothstep( vCgw.y, vCgw.z, vCgY ) );
	if ( cgIn ) cgT0 = pow( cgT0, cgInsideExp );
	// longer path through the tint at grazing angles (refraction n = 1.52), two air/glass interfaces
	float cgCosT = sqrt( max( 1.0 - ( 1.0 - cgNV * cgNV ) / 2.3104, 0.04 ) );
	float cgTr = pow( cgT0, 1.0 / cgCosT ) * ( 1.0 - cgF ) * ( 1.0 - cgF );
	float cgA = clamp( 1.0 - cgTr, 0.0, 1.0 );
	vec3 cgRw = inverseTransformDirection( reflect( - cgV, cgN ), viewMatrix );
#ifdef CG_RBX
	float cgNight = max( cgNightU, 1.0 - smoothstep( 0.015, 0.09, dot( rbxSkyZen, vec3( 0.2126, 0.7152, 0.0722 ) ) ) );
#else
	float cgNight = cgNightU;
#endif
	vec3 cgRefl;
	if ( ! cgIn ) {
	#if defined( USE_ENVMAP ) && defined( ENVMAP_TYPE_CUBE_UV )
		vec3 cgSky = getIBLRadiance( cgV, cgN, 0.02 );
		#ifdef CG_RBX
		cgSky *= rbxEnvSpec * mix( 0.25, 1.0, rbxSV );
		#endif
	#elif defined( CG_RBX )
		vec3 cgSky = rbxSkyGrad( cgRw ) * rbxEnvSpec * mix( 0.15, 1.0, rbxSV );
	#else
		vec3 cgSky = vec3( 0.32, 0.42, 0.58 ) * ( 0.55 + 0.45 * cgRw.y );
	#endif
		// distant skyline: building silhouettes along the horizon (world azimuth), lit windows at night
		float cgPhi = atan( cgRw.z, cgRw.x ) * 9.0;
		float cgB = floor( cgPhi );
		float cgH = 0.03 + 0.2 * pow( cgHash( cgB * 7.13 + 1.7 ), 2.0 );
		float cgAa = max( fwidth( cgRw.y ), 1e-4 );
		float cgM = ( 1.0 - smoothstep( cgH - cgAa, cgH + cgAa, cgRw.y ) ) * smoothstep( - 0.06, - 0.01, cgRw.y );
		vec2 cgWin = vec2( fract( cgPhi ) * 7.0, cgRw.y * 80.0 );
		float cgLit = step( 0.68, cgHash( floor( cgWin.x ) * 3.1 + floor( cgWin.y ) * 17.7 + cgB * 1.3 ) );
		cgLit *= step( 0.3, fract( cgWin.x ) ) * step( 0.35, fract( cgWin.y ) );
		cgLit *= 1.0 - smoothstep( 0.25, 0.6, fwidth( cgWin.y ) ); // fade the window grid out where it would alias
		// day: sunlit / shaded facades (brightness per building, faint window rows); night: dark blocks, lit windows
		float cgFacade = 0.35 + 0.55 * cgHash( cgB * 3.7 + 9.1 );
		float cgRows = 1.0 - 0.25 * step( 0.55, fract( cgWin.y ) ) * ( 1.0 - smoothstep( 0.25, 0.6, fwidth( cgWin.y ) ) );
		vec3 cgDay = cgSky * cgFacade * cgRows * vec3( 1.0, 0.97, 0.93 );
		vec3 cgCityCol = mix( cgDay, vec3( 0.004, 0.005, 0.008 ), cgNight ) + cgLit * cgNight * vec3( 1.0, 0.7, 0.4 ) * 0.45;
	#ifdef CG_RBX
		vec3 cgRoad = rbxHemiGround * 0.9 + cgSky * 0.06;
	#else
		vec3 cgRoad = cgSky * 0.18;
	#endif
		vec3 cgEnv = mix( cgSky, cgCityCol, cgM * cgCity );
		cgEnv = mix( cgEnv, cgRoad, smoothstep( - 0.01, - 0.1, cgRw.y ) );
		cgRefl = cgF * cgEnv * cgReflGain;
	} else {
		// inside: the glass mirrors the dim cabin (dashboard / seats below, headliner above), never the sky
	#ifdef CG_RBX
		vec3 cgAmb = mix( rbxAmbIn, rbxAmbOut, 0.6 ) * 3.14159 + rbxSunCol * 0.2;
	#else
		vec3 cgAmb = vec3( 0.7 );
	#endif
		vec3 cgCab = cgCabin * cgAmb * mix( 0.45, 1.0, smoothstep( 0.1, - 0.45, cgRw.y ) );
		// instrument / navigation screens glowing in the lower windshield at night
		cgCab += cgWs * cgNight * vec3( 0.03, 0.07, 0.14 ) * smoothstep( - 0.1, - 0.6, cgRw.y );
		cgRefl = cgF * cgCab * cgReflGain;
	}
	vec3 cgGlint = min( reflectedLight.directSpecular, vec3( cgGlintMax ) );
	outgoingLight = totalDiffuse * cgA * 0.5 + cgRefl + cgGlint;
	diffuseColor.a = cgA;
}
`;

  function rep(src, a, b) { return src.indexOf(a) < 0 ? src : src.replace(a, b); }
  let warned = false;
  function patchShader(shader, uniforms) {
    for (const k in uniforms) shader.uniforms[k] = uniforms[k];
    shader.vertexShader = rep(shader.vertexShader, '#include <common>', '#include <common>\n' + VERT_PARS);
    shader.vertexShader = rep(shader.vertexShader, '#include <begin_vertex>', '#include <begin_vertex>\n' + VERT_MAIN);
    let fs = rep(shader.fragmentShader, '#include <common>', '#include <common>\n' + FRAG_PARS);
    if (fs.indexOf(GLASS_LINE) >= 0) fs = fs.replace(GLASS_LINE, FRAG_MAIN); // after RblxGfx: Roblox fog still applies (alpha-aware)
    else {
      fs = fs.replace('#include <output_fragment>', FRAG_MAIN + '\n#include <output_fragment>');
      if (!warned && G) { warned = true; console.warn('[carglass] RblxGfx glass output line not found: glass without Roblox fog'); }
    }
    shader.fragmentShader = fs;
  }

  const shared = {
    cgInsideExp: { value: CFG.insideExp },
    cgReflGain: { value: CFG.reflGain },
    cgGlintMax: { value: CFG.glintMax },
    cgCity: { value: CFG.city },
    cgCabin: { value: new THREE.Vector3(CFG.cabin[0], CFG.cabin[1], CFG.cabin[2]) },
    cgNightU: { value: 0 },
  };

  const cache = new Map();
  function make(role, side, tag) {
    const key = role + '|' + tag;
    if (cache.has(key)) return cache.get(key);
    const dark = role === 'glass_dark';
    const m = new THREE.MeshStandardMaterial({ color: dark ? 0x050608 : 0x07090c, metalness: 0, roughness: 0.035, side, transparent: true, depthWrite: false });
    m.name = 'gw:carglass:' + key;
    m.blending = THREE.CustomBlending;
    m.blendEquation = THREE.AddEquation;
    m.blendSrc = THREE.OneFactor;
    m.blendDst = THREE.OneMinusSrcAlphaFactor;
    m.blendSrcAlpha = THREE.OneFactor;
    m.blendDstAlpha = THREE.OneMinusSrcAlphaFactor;
    m.premultipliedAlpha = false;
    m.extensions = { derivatives: true };
    m.defines = { RBX_GLASS: '' };
    const uniforms = Object.assign({ cgVlt: { value: dark ? TINT.glass_dark : TINT.glass } }, shared);
    let adopted = false;
    try { if (G && G.adopt) { G.adopt(m); adopted = !!m.userData.rbxAdopted; } } catch (e) { adopted = false; }
    if (adopted) m.defines.CG_RBX = '';
    else delete m.defines.RBX_GLASS;
    const base = m.onBeforeCompile, baseKey = m.customProgramCacheKey;
    const hasBase = adopted && base && base !== THREE.Material.prototype.onBeforeCompile;
    m.onBeforeCompile = function (shader, renderer) {
      if (hasBase) base.call(this, shader, renderer);
      patchShader(shader, uniforms);
    };
    const bk = hasBase && baseKey ? String(baseKey.call(m)) : '';
    m.customProgramCacheKey = function () { return 'gwcarglass1|' + tag + '|' + bk; };
    m.userData.gwCarGlass = { role, inner: tag === 'in', uniforms };
    m.needsUpdate = true;
    cache.set(key, m);
    return m;
  }

  // per-window data: connected islands of the glass mesh -> windshield (lighter + shade band) / everything else (privacy)
  function prepare(geo, role) {
    if (!geo || !geo.attributes || !geo.attributes.position || geo.userData.cgPrepared) return geo;
    geo.userData.cgPrepared = true;
    const pos = geo.attributes.position, idx = geo.index, nv = pos.count;
    const nt = idx ? idx.count : nv;
    const at = (i) => (idx ? idx.getX(i) : i);
    const par = new Int32Array(nv);
    for (let i = 0; i < nv; i++) par[i] = i;
    const find = (a) => { while (par[a] !== a) { par[a] = par[par[a]]; a = par[a]; } return a; };
    for (let t = 0; t + 2 < nt; t += 3) {
      const a = find(at(t)), b = find(at(t + 1)), c = find(at(t + 2));
      par[b] = a; par[find(c)] = a;
    }
    let z0 = Infinity, z1 = -Infinity;
    for (let i = 0; i < nv; i++) { const z = pos.getZ(i); if (z < z0) z0 = z; if (z > z1) z1 = z; }
    const zMid = (z0 + z1) / 2;
    const isl = new Map(); // root -> [nx, ny, nz, area, cz*area, minY, maxY]
    const A = new THREE.Vector3(), B = new THREE.Vector3(), C = new THREE.Vector3(), U = new THREE.Vector3(), V = new THREE.Vector3();
    for (let t = 0; t + 2 < nt; t += 3) {
      A.fromBufferAttribute(pos, at(t)); B.fromBufferAttribute(pos, at(t + 1)); C.fromBufferAttribute(pos, at(t + 2));
      U.subVectors(B, A); V.subVectors(C, A); U.cross(V);
      const area = U.length() / 2;
      const r = find(at(t));
      let s = isl.get(r);
      if (!s) { s = [0, 0, 0, 0, 0, Infinity, -Infinity]; isl.set(r, s); }
      s[0] += U.x / 2; s[1] += U.y / 2; s[2] += U.z / 2; s[3] += area; s[4] += ((A.z + B.z + C.z) / 3) * area;
      s[5] = Math.min(s[5], A.y, B.y, C.y); s[6] = Math.max(s[6], A.y, B.y, C.y);
    }
    const base = role === 'glass_dark' ? TINT.glass_dark : TINT.glass;
    const info = new Map();
    for (const [r, s] of isl) {
      const l = Math.hypot(s[0], s[1], s[2]) || 1, nx = s[0] / l, ny = s[1] / l, nz = s[2] / l;
      const cz = s[3] > 0 ? s[4] / s[3] : 0;
      const ws = role !== 'glass_dark' && nz < -0.3 && Math.abs(nx) < 0.6 && ny > -0.2 && cz < zMid;
      if (ws) { const h = s[6] - s[5]; info.set(r, [TINT.windshield, s[6] - 0.24 * h, s[6] - 0.05 * h]); }
      else info.set(r, [base, 0, 0]);
    }
    const arr = new Float32Array(nv * 3);
    for (let i = 0; i < nv; i++) { const v = info.get(find(i)) || [base, 0, 0]; arr[i * 3] = v[0]; arr[i * 3 + 1] = v[1]; arr[i * 3 + 2] = v[2]; }
    geo.setAttribute('cgw', new THREE.BufferAttribute(arr, 3));
    return geo;
  }

  let low = null;
  function lowMaterial() {
    if (low) return low;
    low = new THREE.MeshStandardMaterial({ color: 0x07090c, metalness: 0, roughness: 0.06 });
    low.name = 'gw:carglass:low';
    try { if (G && G.adopt) G.adopt(low); } catch (e) { /* lighting adopt optional */ }
    low.userData.gwCarGlassLow = true;
    return low;
  }

  root.GWCarGlass = {
    TINT, CFG,
    material: (role) => make(role === 'glass_dark' ? 'glass_dark' : 'glass', THREE.FrontSide, 'out'),
    inner: (role) => make(role === 'glass_dark' ? 'glass_dark' : 'glass', THREE.BackSide, 'in'),
    both: (role) => make(role === 'glass_dark' ? 'glass_dark' : 'glass', THREE.DoubleSide, 'both'),
    prepare,
    lowMaterial,
    isGlass: (m) => !!(m && m.userData && m.userData.gwCarGlass),
    isInner: (m) => !!(m && m.userData && m.userData.gwCarGlass && m.userData.gwCarGlass.inner),
    setNight: (v) => { shared.cgNightU.value = v ? 1 : 0; },
  };
})(typeof window !== 'undefined' ? window : globalThis);
