// Character kit: geometry core, murim builders (robes, heads, lamellar, ornaments), plate-armour builders, cloth helpers,
// looks, texture sets and the static display kit. See src/char/kit/README.md for the catalogue.

export * from './geo.js';
export * from './armor.js';
export * from './murim.js';
export * from './head.js';
export * from './cloth.js';
export * from './looks.js';
export { createStaticKit } from './static.js';
export { mannequin } from './mannequin.js';
export { SET, SET_SCALE, SET_BUMP, configureTextureSets, getTextureSets, requireTextureSet, prewarmTextureSets, textureSetTimings } from './textures.js';
