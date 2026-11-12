// Armour kit: geometry core, armour builders, cloth helpers, looks, texture sets and the static display kit.
// See src/char/kit/README.md for the catalogue.

export * from './geo.js';
export * from './armor.js';
export * from './cloth.js';
export * from './looks.js';
export { createStaticKit } from './static.js';
export { SET, SET_SCALE, SET_BUMP, configureTextureSets, getTextureSets } from './textures.js';
