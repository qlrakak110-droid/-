// ECLIPSE DUEL rules engine — public API. Pure deterministic JavaScript: no three.js, no DOM. See README.md.

export { createMatch, mergeRules } from './match.js';
export { validateFighterDef, assertFighterDef, compileFighterDef, resolveCommand, AI_ROLES } from './defs.js';
export { deriveFrameData, fighterFrameData, frameDataTable } from './framedata.js';
export { createHumanController, createScriptedController, createIdleController, actionsProvider } from './controllers.js';
export { createAIController, AI_LEVELS } from './ai.js';
export { sampleFighter } from './sample-fighter.js';
export {
  DEFAULT_RULES, DEFAULT_STATS, DEFAULT_MOVEMENT, HIT_DEFAULTS, LEVELS, STATES, BUTTONS, NEUTRAL_INPUT,
} from './constants.js';
export { makeRng } from './rng.js';
