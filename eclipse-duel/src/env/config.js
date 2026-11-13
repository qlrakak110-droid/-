// 「천무대 天武臺」: art constants shared by every env sub-module (layout radii, light directions, palette, tiers).
// Angles on the ring: theta is measured from -Z toward +X, so theta = 0 is straight behind the terrace centre as seen
// from the duel camera (the vista), +90 deg = +X (east), -90 deg = -X (west, the hall), 180 deg = +Z (south, the gate)
// and ring points are (R sin(theta), y, -R cos(theta)).

import * as THREE from 'three';
import { DEG } from '../core/math.js';

const dirFromAzEl = (az, el) => new THREE.Vector3(Math.sin(az * DEG) * Math.cos(el * DEG), Math.sin(el * DEG), -Math.cos(az * DEG) * Math.cos(el * DEG)).normalize();

/**
 * Direction toward the eclipse (black sun). Low on purpose: the game's fight camera tilts down 4.5–8.5° with a 34–40°
 * vertical fov, so the top of its frame sits only ~12° above the horizon. At 6° the disc and inner corona sit in the
 * upper third of every fight framing, just above the fighters' heads.
 */
export const SUN_DIR = dirFromAzEl(2, 6.2);
/**
 * Direction toward the cold rim light. Motivated by the corona but raised and swung to the right of it: a light
 * straight behind the fighters only grazes their silhouettes, while this one rims heads, shoulders and the right
 * edge opposite the front-left key.
 */
export const RIM_DIR = dirFromAzEl(28, 24);
/** Direction toward the key light (front-left, high): models the fighters from the camera side. */
export const KEY_DIR = new THREE.Vector3(-0.42, 0.78, 0.5).normalize();
/** Apparent angular radius of the eclipse disc (radians). Exaggerated for drama. */
export const SUN_RADIUS = 2.9 * DEG;
/** Polar angle (around the sun axis, 0 = screen right, CCW) of the diamond-ring bead. */
export const DIAMOND_PHI = 48 * DEG;
/** Ambient wind (m/s): banners, talismans, bamboo, smoke, leaves and clouds all drift with it. */
export const WIND = new THREE.Vector3(0.9, 0.0, 0.25);

/** Ring layout in metres. */
export const LAYOUT = {
  floorR: 15.6,      // terrace floor radius (the retaining wall of the raised court stands here)
  floorTexExtent: 16, // floor bake covers [-E, E] on x and z
  fightBand: 1.3,    // half width (z) of the worn contact band along the fight line
  wallR: 15.6,       // retaining wall face
  wallT: 1.1,        // (kept for older callers) wall thickness
  platY: 1.44,       // top of the raised court around the terrace (8 stair risers of 0.18)
  railH: 1.0,        // balustrade height on the court edge
  pillarR: 17.5,     // gallery (회랑): inner column row
  galleryR1: 20.5,   // gallery: outer column row
  slotDeg: 12,       // gallery column spacing
  thetaMax: Math.PI, // the ring is built all the way round (the action-RPG mode turns 360 degrees)
  gap: 27 * DEG,     // |theta| < gap: the broken rim open to the cloud sea (the vista behind the fighters)
  wallFrom: 30 * DEG, // the retaining wall starts here (its ends at the vista shoulders are broken)
  cloudY: -11,       // sea of cloud level
  outerR: 36,        // the summit ground ends here (drops into the mist)
  // the four fire sources of env.braziers / env.points, [theta deg, radius, kind]: two lit stone lanterns (석등) on
  // the vista shoulders, two bronze incense braziers (향로) further round
  braziers: [
    [-37, 13.7, 'lantern'], [37, 13.7, 'lantern'], [-63, 13.6, 'censer'], [63, 13.6, 'censer'],
  ],
  // more lit stone lanterns (no real lights: baked glow + a floor pool): at the feet of the gate and hall stairs and
  // on the east side
  lamps: [
    [166, 14.25], [-166, 14.25], [-68, 19.3, 1.44], [-88, 19.3, 1.44], [112, 14.3],
  ],
};

/** The recessed stair flights from the terrace floor up to the raised court. */
export const STAIRS = [
  { id: 'gate', th: 180 * DEG, width: 5.2, run: 2.64, steps: 8 },
  { id: 'hall', th: -78 * DEG, width: 4.8, run: 2.64, steps: 8 },
];
/** The hall (천무전) on the west side: centre direction, distance of its plinth front from the terrace centre. */
export const HALL = { th: -78 * DEG, front: 20.2, bay: 3.2, bays: 5, porch: 1.5, wall: 4.1, depth: 10.4, plinth: 0.72, colH: 4.2 };
/** The mountain gate (산문) on the south side: column line distance from the terrace centre. */
export const GATE = { th: 180 * DEG, line: 20.7, colH: 5.6, halfBay: 2.15, wing: 5.0 };

/** Old impact centre (x, z) and radius: floor bake + heaved slabs. */
export const IMPACT = [-4.4, -6.2, 2.9];

/**
 * Radius of the terrace floor's edge at ring angle `th` (radians): the retaining wall face, except across the vista
 * where the rim has broken away into the cloud sea (a ragged bite up to ~1.7 m deep).
 */
export function rimR(th) {
  const a = Math.abs(Math.atan2(Math.sin(th), Math.cos(th)));
  const g = LAYOUT.gap;
  if (a >= g + 3 * DEG) return LAYOUT.floorR;
  const k = 1 - Math.min(1, Math.max(0, (a - (g - 5 * DEG)) / (8 * DEG)));
  const s = k * k * (3 - 2 * k);
  const n = 0.5 + 0.5 * Math.sin(th * 23.0 + 1.3) * Math.sin(th * 9.7 + 0.4) + 0.35 * Math.sin(th * 61.0 + 2.1);
  const big = 0.5 + 0.5 * Math.sin(th * 5.3 + 0.9);
  return LAYOUT.floorR - s * (0.35 + 0.75 * big + 0.42 * Math.max(0, n));
}

/** Linear-HDR palette (THREE.Color components are linear). Mid-tones of the backdrop stay low on purpose. */
export const PALETTE = {
  zenith: new THREE.Color(0.0009, 0.0012, 0.0026),
  skyMid: new THREE.Color(0.0032, 0.0042, 0.0085),
  horizon: new THREE.Color(0.014, 0.0145, 0.02),
  glow: new THREE.Color(0.17, 0.08, 0.042),     // 360-degree eclipse "sunset" band at the horizon
  corona: new THREE.Color(0.82, 0.9, 1.0),
  chromo: new THREE.Color(1.0, 0.24, 0.3),
  fogNear: new THREE.Color(0.0105, 0.0125, 0.018),
  sunHalo: new THREE.Color(0.03, 0.036, 0.05),    // fog in-scatter around the eclipse
  key: new THREE.Color(0.86, 0.9, 1.0),
  rim: new THREE.Color(0.55, 0.68, 1.0),
  hemiSky: new THREE.Color(0.1, 0.12, 0.19),
  hemiGround: new THREE.Color(0.06, 0.04, 0.03),
  fire: new THREE.Color(1.0, 0.5, 0.18),
  // faded 단청 on the timber (albedo, linear): lacquer red, jade green, bare weathered wood, ink-black board, ochre
  lacquer: [0.2, 0.034, 0.024],
  jade: [0.03, 0.078, 0.064],
  wood: [0.05, 0.043, 0.036],
  ink: [0.012, 0.011, 0.011],
  ochre: [0.36, 0.25, 0.08],
  tile: [0.5, 0.52, 0.6],        // roof tile tint on the stone material (blue-black fired clay)
};

/** Per-tier knobs derived from ctx.quality (envDetail 0..2). */
export function tierSettings(quality, override) {
  const d = override !== undefined ? override : quality.envDetail;
  return {
    detail: d,
    floorTex: d >= 2 ? 2048 : 1024,
    stoneTex: d >= 1 ? 1024 : 512,
    ornTex: d >= 1 ? 1024 : 512,     // relief atlas cell rows: the atlas is 2:1 (8 x 4 cells)
    pointLights: d >= 2 ? 4 : d >= 1 ? 2 : 0,
    banners: d >= 1 ? 8 : 5,
    ash: Math.round((d >= 2 ? 520 : d >= 1 ? 380 : 240) * (quality.particleScale || 1)),
    embers: Math.round((d >= 2 ? 110 : d >= 1 ? 80 : 50) * (quality.particleScale || 1)),
    leaves: Math.round((d >= 2 ? 90 : d >= 1 ? 64 : 36) * (quality.particleScale || 1)),
    fogCards: d >= 1,
    shafts: d >= 1 ? 7 : 3,
    reflection: d >= 2,
    rubble: d >= 2 ? 1 : d >= 1 ? 0.75 : 0.45,
    skyOctaves: d >= 1 ? 5 : 3,
    // blob shadow under contacts (env.setContact) where there is no shadow map; a hint of it deepens PCF contact
    blobShadow: quality.shadows ? 0.25 : 0.8,
  };
}
