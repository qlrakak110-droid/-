// Eclipse Ruins: art constants shared by every env sub-module (layout radii, light directions, palette, tiers).
// Angles on the ring: theta is measured from -Z toward +X, so theta = 0 is straight behind the arena centre as seen
// from the fight camera and ring points are (R sin(theta), y, -R cos(theta)).

import * as THREE from 'three';
import { DEG } from '../core/math.js';

const dirFromAzEl = (az, el) => new THREE.Vector3(Math.sin(az * DEG) * Math.cos(el * DEG), Math.sin(el * DEG), -Math.cos(az * DEG) * Math.cos(el * DEG)).normalize();

/** Direction toward the eclipse (black sun) — also the cold rim light. */
export const SUN_DIR = dirFromAzEl(5, 12.5);
/** Direction toward the key light (front-left, high): models the fighters from the camera side. */
export const KEY_DIR = new THREE.Vector3(-0.42, 0.78, 0.5).normalize();
/** Apparent angular radius of the eclipse disc (radians). Exaggerated for drama. */
export const SUN_RADIUS = 2.9 * DEG;
/** Polar angle (around the sun axis, 0 = screen right, CCW) of the diamond-ring bead. */
export const DIAMOND_PHI = 48 * DEG;
/** Ambient wind (m/s): banners, ash, flames and clouds all drift with it. */
export const WIND = new THREE.Vector3(0.9, 0.0, 0.25);

/** Ring layout in metres. */
export const LAYOUT = {
  floorR: 15.6,      // textured arena floor radius (wall face sits here)
  floorTexExtent: 16, // floor bake covers [-E, E] on x and z
  fightBand: 1.3,    // half width (z) of the worn contact band along the fight line
  wallR: 15.6,       // podium wall inner face
  wallT: 1.1,        // podium wall thickness
  pillarR: 17.6,     // colossal colonnade radius
  pillarCount: 22,   // slots around the full circle (only the back ~250 degrees are built)
  tierR0: 19.2,      // collapsed seating tier: first step radius
  tierR1: 27.5,      // last step radius
  thetaMax: 128 * DEG, // build the ring for |theta| <= this (the camera never sees behind itself)
  gap: 27 * DEG,     // |theta| < gap: the collapsed vista behind the fighters
  cloudY: -11,       // sea of cloud level
  braziers: [ // [theta deg, radius]
    [-37, 13.7], [37, 13.7], [-63, 13.6], [63, 13.6],
  ],
};

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
};

/** Per-tier knobs derived from ctx.quality (envDetail 0..2). */
export function tierSettings(quality, override) {
  const d = override !== undefined ? override : quality.envDetail;
  return {
    detail: d,
    floorTex: d >= 2 ? 2048 : 1024,
    stoneTex: d >= 1 ? 1024 : 512,
    pointLights: d >= 2 ? 4 : d >= 1 ? 2 : 0,
    banners: d >= 1 ? 8 : 5,
    ash: Math.round((d >= 2 ? 650 : d >= 1 ? 480 : 300) * (quality.particleScale || 1)),
    embers: Math.round((d >= 2 ? 300 : d >= 1 ? 220 : 140) * (quality.particleScale || 1)),
    fogCards: d >= 1,
    shafts: d >= 1 ? 7 : 3,
    reflection: d >= 2,
    rubble: d >= 2 ? 1 : d >= 1 ? 0.75 : 0.45,
    skyOctaves: d >= 1 ? 5 : 3,
  };
}
