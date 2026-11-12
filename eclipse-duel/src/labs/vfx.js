// VFX lab (temporary bootstrap: atlas check)
import * as THREE from 'three';
import { createLab } from '../core/lab.js';
import { createTextures } from '../vfx/textures.js';

createLab({
  setup(ctx) {
    const t0 = performance.now();
    const tex = createTextures(ctx.renderer);
    console.log('[ed] textures ms', (performance.now() - t0).toFixed(1));
    ctx._tex = tex;
  },
  scenarios: {
    atlas(ctx, lab, which = 'atlas', mode = 0) {
      const t = ctx._tex[which];
      const m = new THREE.Mesh(new THREE.PlaneGeometry(2, 2), new THREE.ShaderMaterial({
        depthTest: false, depthWrite: false, uniforms: { t: { value: t }, mode: { value: mode }, asp: { value: ctx.viewport.aspect } },
        vertexShader: 'varying vec2 vUv; uniform float asp; void main(){ vUv = uv; gl_Position = vec4(position.x / asp, position.y, 0.0, 1.0); }',
        fragmentShader: `uniform sampler2D t; uniform int mode; varying vec2 vUv; void main(){ vec4 s = texture2D(t, vUv);
          vec3 bg = vec3(mod(floor(vUv.x*64.0)+floor(vUv.y*64.0), 2.0) > 0.5 ? 0.02 : 0.035);
          vec3 col;
          if (mode == 0) { vec3 hot = vec3(0.95 + 0.05*s.g, 0.4 + 0.6*s.g, 0.12 + 0.88*s.g*s.g); col = mix(bg, hot * s.r, s.a); }
          else if (mode == 1) col = vec3(s.a);
          else if (mode == 2) col = s.rgb * s.a;
          else col = s.rgb;
          gl_FragColor = vec4(col * 0.75, 1.0); }`,
      }));
      m.frustumCulled = false; m.renderOrder = 999; m.material.transparent = true;
      ctx.scene.add(m);
    },
  },
});
