# Scene templates

Three ways to add a scene. Copy a template into a numbered folder and rename it
to `scene.ts` — it'll appear in the sidebar automatically (no registry edits).

## 1. A shader scene (levels 1–3) — the everyday kind

Just GLSL. See any existing `NN-*/scene.ts`. Minimal version:

```ts
import type { ShaderScene } from '../../engine/types';
import fragment from './frag.glsl?raw';

const scene: ShaderScene = {
  id: '06-my-scene',
  title: 'My scene',
  level: 2,
  fragment,
};
export default scene;
```

## 2. A multi-pass shader scene (level 4)

Same thing, plus a `passes` array: each pass renders into a texture that later
passes read as `iChannel0..3`. Start from `multipass-scene.ts.txt`, or read
`06-blur-bloom` (a chain) and `07-feedback-trails` (a pass that reads itself).

## 3. A custom scene (Pixi / Three, LATER)

Once GLSL feels natural and you want a real 3D engine, use a **CustomScene**.
It's handed its own `<canvas>` and owns it completely — the raw-WebGL engine
steps out of the way. `three-scene.ts.txt` and `pixi-scene.ts.txt` here are
ready-to-use starting points.

To activate one:
1. `pnpm add three`  (or `pnpm add pixi.js`)
2. copy `three-scene.ts.txt` to `06-three-cube/scene.ts`
3. that's it — it shows up in the sidebar with a `lib` badge.

The templates are kept as `.txt` so the project builds with zero extra
dependencies until you opt in.
