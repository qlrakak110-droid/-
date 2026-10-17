// Animated soldier (Mixamo "Vanguard" from the three.js examples) with procedural aiming:
// the legs/body play Idle/Walk/Run clips, then the upper body is posed with IK so both
// hands hold the weapon and the fingers wrap the grip.
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import * as SkeletonUtils from 'three/addons/utils/SkeletonUtils.js';

let base = null;
export async function loadCharacter(url = '/assets/soldier.glb') {
  base = await new GLTFLoader().loadAsync(url);
  // Keep rotations (+ hip translation) only, so per-rig bone scaling (FP arms, hidden head) sticks.
  for (const clip of base.animations) {
    clip.tracks = clip.tracks.filter((t) => t.name.endsWith('.quaternion') || t.name === 'mixamorigHips.position');
  }
  base.scene.traverse((o) => {
    if (o.isMesh) {
      o.castShadow = true;
      o.receiveShadow = true;
      o.frustumCulled = false;
      o.material.envMapIntensity = 0.8;
    }
  });
}

const _a = new THREE.Vector3(), _b = new THREE.Vector3(), _c = new THREE.Vector3(), _d = new THREE.Vector3();
const _q = new THREE.Quaternion(), _q2 = new THREE.Quaternion(), _pq = new THREE.Quaternion();

function setWorldQuat(bone, qw) {
  bone.parent.getWorldQuaternion(_pq);
  bone.quaternion.copy(_pq.invert().multiply(qw));
  bone.updateMatrixWorld(true);
}
function rotateWorld(bone, axis, angle) {
  bone.getWorldQuaternion(_q2);
  _q.setFromAxisAngle(axis, angle);
  setWorldQuat(bone, _q.multiply(_q2));
}
/** Rotate `bone` so the direction bone→child points along `dir` (world). */
function aim(bone, child, dir) {
  bone.getWorldPosition(_a);
  child.getWorldPosition(_b);
  const from = _b.sub(_a).normalize();
  _q.setFromUnitVectors(from, _c.copy(dir).normalize());
  bone.getWorldQuaternion(_q2);
  setWorldQuat(bone, _q.multiply(_q2));
}

/** Two-bone IK elbow position. */
function elbowPos(S, T, a, b, pole, out) {
  const d = _d.copy(T).sub(S);
  const dist = Math.min(Math.max(d.length(), 1e-4), a + b - 1e-4);
  const dir = d.normalize();
  const along = (a * a - b * b + dist * dist) / (2 * dist);
  const h = Math.sqrt(Math.max(0, a * a - along * along));
  const p = pole.clone().addScaledVector(dir, -pole.dot(dir)).normalize();
  return out.copy(S).addScaledVector(dir, along).addScaledVector(p, h);
}

const FINGERS = ['Index', 'Middle', 'Ring', 'Pinky'];

class Arm {
  constructor(root, side) {
    const B = (n) => root.getObjectByName(`mixamorig${side}${n}`);
    this.side = side;
    this.upper = B('Arm'); this.fore = B('ForeArm'); this.hand = B('Hand');
    this.mid = B('HandMiddle1'); this.index = B('HandIndex1'); this.pinky = B('HandPinky1');
    this.fingers = FINGERS.map((f) => [1, 2, 3].map((i) => B(`Hand${f}${i}`)));
    this.fingerTips = FINGERS.map((f) => B(`Hand${f}4`));
    this.thumb = [1, 2, 3].map((i) => B(`HandThumb${i}`));
    this.thumbTip = B('HandThumb4');
    this.a = this.upper.getWorldPosition(_a).distanceTo(this.fore.getWorldPosition(_b));
    this.b = this.fore.getWorldPosition(_a).distanceTo(this.hand.getWorldPosition(_b));
  }
  palmNormal(out) {
    const fd = this.mid.getWorldPosition(_a).sub(this.hand.getWorldPosition(_b)).normalize();
    const side = this.index.getWorldPosition(_b).sub(this.pinky.getWorldPosition(_c)).normalize();
    out.crossVectors(fd, side).normalize();
    if (this.side === 'Right') out.negate();
    return out;
  }
  /** Place the wrist at `target`, fingers along `fingerDir`, palm facing `palmDir`. */
  solve(target, pole, fingerDir, palmDir, curl, trigger = false) {
    const S = this.upper.getWorldPosition(new THREE.Vector3());
    const E = elbowPos(S, target, this.a, this.b, pole, new THREE.Vector3());
    aim(this.upper, this.fore, E.sub(S));
    const E2 = this.fore.getWorldPosition(new THREE.Vector3());
    aim(this.fore, this.hand, target.clone().sub(E2));
    aim(this.hand, this.mid, fingerDir);
    // roll around the finger axis so the palm faces the weapon
    const fd = this.mid.getWorldPosition(new THREE.Vector3()).sub(this.hand.getWorldPosition(new THREE.Vector3())).normalize();
    const cur = this.palmNormal(new THREE.Vector3());
    const want = palmDir.clone().addScaledVector(fd, -palmDir.dot(fd)).normalize();
    const ang = Math.atan2(_d.crossVectors(cur, want).dot(fd), cur.dot(want));
    rotateWorld(this.hand, fd, ang);
    // curl fingers toward the palm
    const palm = this.palmNormal(new THREE.Vector3());
    this.fingers.forEach((chain, fi) => {
      const k = trigger && fi === 0 ? 0.35 : 1;
      chain.forEach((bone, j) => {
        const child = j < 2 ? chain[j + 1] : this.fingerTips[fi];
        const dir = child.getWorldPosition(new THREE.Vector3()).sub(bone.getWorldPosition(new THREE.Vector3())).normalize();
        const axis = new THREE.Vector3().crossVectors(dir, palm).normalize();
        rotateWorld(bone, axis, curl[j] * k);
      });
    });
    const tdir = this.thumbTip.getWorldPosition(new THREE.Vector3()).sub(this.thumb[0].getWorldPosition(new THREE.Vector3())).normalize();
    const taxis = new THREE.Vector3().crossVectors(tdir, palm).normalize();
    rotateWorld(this.thumb[0], taxis, curl[0] * 0.5);
  }
}

const CURL_GRIP = [0.9, 1.2, 0.7];
const CURL_FORE = [0.7, 1.0, 0.6];

export class CharacterRig {
  /**
   * @param tint      colour multiplied into the body material (player colour)
   * @param firstPerson  hide head/legs and lengthen arms for the viewmodel
   */
  constructor({ tint = null, firstPerson = false, armScale = 1.15 } = {}) {
    this.root = new THREE.Group();
    this.model = SkeletonUtils.clone(base.scene);
    this.root.add(this.model);
    this.materials = [];
    this.model.traverse((o) => {
      if (!o.isMesh) return;
      o.material = o.material.clone();
      this.materials.push(o.material);
      if (tint && o.material.name === 'VanguardBodyMat') o.material.color.copy(tint);
      if (firstPerson) { o.castShadow = false; o.receiveShadow = false; }
    });
    // First person: show only forearms and hands by clipping each arm just behind the elbow.
    // A fragment is removed only when it is behind *both* elbow planes.
    this.clip = firstPerson ? [new THREE.Plane(), new THREE.Plane()] : null;
    if (this.clip) {
      for (const m of this.materials) {
        m.clippingPlanes = this.clip;
        m.clipIntersection = true;
        m.side = THREE.DoubleSide;
      }
    }
    const B = (n) => this.model.getObjectByName(`mixamorig${n}`);
    this.bones = { hips: B('Hips'), spine: B('Spine'), spine1: B('Spine1'), spine2: B('Spine2'), neck: B('Neck'), head: B('Head') };
    const fpScale = () => {
      // Stretch only the (clipped, invisible) upper arms so the hands can reach the weapon.
      for (const s of ['Left', 'Right']) {
        B(`${s}Arm`).scale.setScalar(armScale);
        B(`${s}ForeArm`).scale.setScalar(1 / armScale);
      }
      for (const n of ['Neck', 'LeftUpLeg', 'RightUpLeg']) B(n).scale.setScalar(0.0001);
    };
    if (firstPerson) fpScale();
    this.model.updateMatrixWorld(true);
    this.armR = new Arm(this.model, 'Right');
    this.armL = new Arm(this.model, 'Left');

    this.mixer = new THREE.AnimationMixer(this.model);
    const clip = (n) => base.animations.find((a) => a.name === n);
    this.actions = {};
    for (const n of ['Idle', 'Walk', 'Run']) {
      const a = this.mixer.clipAction(clip(n));
      a.play();
      a.setEffectiveWeight(n === 'Idle' ? 1 : 0);
      this.actions[n] = a;
    }
    this.mixer.update(Math.random() * 2);


    this.firstPerson = firstPerson;
  }

  /** Blend locomotion clips by speed (m/s). */
  locomote(dt, speed) {
    const w = Math.min(1, speed / 3), r = Math.max(0, Math.min(1, (speed - 4) / 3));
    this.actions.Idle.setEffectiveWeight(1 - w);
    this.actions.Walk.setEffectiveWeight(w * (1 - r));
    this.actions.Run.setEffectiveWeight(w * r);
    this.actions.Walk.timeScale = Math.max(0.6, speed / 2.2);
    this.actions.Run.timeScale = Math.max(0.7, speed / 6);
    this.mixer.update(dt);
  }

  /**
   * Hold a weapon: `gun` is the weapon group (already placed in world), `info` its attachment points.
   * `twist` turns the torso so the support shoulder comes forward.
   */
  hold(gun, info, { twist = -0.45, pitch = 0, fpReach = false } = {}) {
    const root = this.root;
    root.updateMatrixWorld(true);
    const up = new THREE.Vector3(0, 1, 0);
    const right = new THREE.Vector3(1, 0, 0).transformDirection(root.matrixWorld);
    const sp = this.bones.spine2;
    if (!this.firstPerson) {
      rotateWorld(this.bones.spine1, up, twist * 0.5);
      rotateWorld(sp, up, twist * 0.5);
      rotateWorld(sp, right, pitch * 0.45);
      rotateWorld(this.bones.neck, up, -twist * 0.9);
      rotateWorld(this.bones.head, right, pitch * 0.5);
    }
    gun.updateMatrixWorld(true);
    const fwd = new THREE.Vector3(0, 0, -1).transformDirection(gun.matrixWorld);
    const gUp = new THREE.Vector3(0, 1, 0).transformDirection(gun.matrixWorld);
    const gRight = new THREE.Vector3(1, 0, 0).transformDirection(gun.matrixWorld);
    const toW = (p) => gun.localToWorld(new THREE.Vector3(p[0], p[1], p[2]));

    // Right hand: wrist just behind/right of the pistol grip, fingers wrapping forward-down.
    const grip = info.grip;
    const tR = toW([grip[0] + 0.035, grip[1] + 0.03, grip[2] + 0.05]);
    const fR = fwd.clone().multiplyScalar(0.55).addScaledVector(gUp, -0.85).normalize();
    this.armR.solve(tR, gUp.clone().negate().addScaledVector(gRight, 0.8), fR, gRight.clone().negate(), CURL_GRIP, true);

    // Left hand: under the handguard, palm up; on pistols it cups the right hand.
    if (info.fore) {
      const f = info.fore;
      const reach = fpReach ? 0.12 : 0.06;
      const tL = toW([f[0] - 0.045, f[1] - 0.04, f[2] + 0.07 + reach]);
      const fL = info.foreVertical ? fwd.clone().addScaledVector(gUp, -1).normalize()
        : fwd.clone().multiplyScalar(0.55).addScaledVector(gRight, 0.6).addScaledVector(gUp, 0.2).normalize();
      const palm = info.foreVertical ? gRight.clone() : gUp.clone().addScaledVector(gRight, 0.5).normalize();
      this.armL.solve(tL, gUp.clone().negate().addScaledVector(gRight, -0.9), fL, palm, CURL_FORE);
    } else {
      const tL = toW([grip[0] - 0.05, grip[1] + 0.0, grip[2] + 0.03]);
      const fL = fwd.clone().multiplyScalar(0.4).addScaledVector(gRight, 0.55).addScaledVector(gUp, -0.6).normalize();
      this.armL.solve(tL, gUp.clone().negate().addScaledVector(gRight, -0.8), fL, gRight.clone(), CURL_FORE);
    }
    this.updateClip();
  }

  updateClip() {
    if (!this.clip) return;
    [this.armR, this.armL].forEach((arm, i) => {
      // Keep only what is in front of the elbow along the view direction.
      const e = arm.fore.getWorldPosition(new THREE.Vector3());
      const n = new THREE.Vector3(0, 0, -1).transformDirection(this.root.matrixWorld);
      this.clip[i].setFromNormalAndCoplanarPoint(n, e.addScaledVector(n, -0.03));
    });
  }

  setProtect(on) {
    for (const m of this.materials) m.emissive?.setHex(on ? 0x16264a : 0x000000);
  }
  dispose() {
    for (const m of this.materials) m.dispose();
  }
}
