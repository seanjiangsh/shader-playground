# Shader Playground

A framework-free **WebGL + GLSL** playground for learning shaders from scratch,
ShaderToy-style — with a clean path to add **Pixi.js** and **Three.js** scenes
later, once GLSL feels natural.

No Pixi, no Three, no shader libraries. Just a ~250-line WebGL harness so nothing
is hidden from you. Every experiment you make is saved as its own scene and shows
up in the sidebar, so the repo grows into a gallery of everything you've tried.

## Quick start

```bash
corepack enable pnpm   # once per machine — makes pnpm available
pnpm install
pnpm dev               # opens http://localhost:5173
```

This project is pinned to **pnpm** via the `packageManager` field in
`package.json`, so corepack fetches the exact version for you. Use `pnpm`, not
`npm` — mixing them produces a second lockfile and a differently-shaped
`node_modules`.

Edit any `.glsl` file and the browser hot-reloads instantly. Use the sidebar (or
the ↑/↓ arrow keys) to switch scenes. Drag on the canvas to feed `iMouse`.

## What's inside

```
pnpm-workspace.yaml   pnpm's settings file (not a monorepo — see the comments)
scripts/
  check-shaders.mjs   compiles + links every scene's GLSL, no browser needed
src/
  engine/
    Renderer.ts     the "engine": WebGL context, fullscreen quad / grid, shader
                    compile, the render loop, standard uniforms, pass chaining
    RenderTarget.ts render-to-texture: the framebuffer object level 4 needs
    shaderSource.ts injected uniforms + precision; shared with the validator
    types.ts        the Scene contract (shader scenes + custom Pixi/Three scenes)
  scenes/
    index.ts        auto-discovers every scene folder (you never edit this)
    01-gradient/    L1 · color per pixel + time
    02-shape-sdf/   L2 · signed distance fields — a starter with exercises
    _templates/     multi-pass starter + ready-made Pixi & Three scenes
  _parked/          finished scenes, out of the sidebar until you want them
  ui/gallery.ts     the sidebar
  main.ts           app shell: swaps scenes, hash routing, keyboard nav
```

Only the levels you've reached are active — the rest are parked in `src/_parked/`
so the sidebar stays a clean slate while you work through the basics yourself.
Bring one back whenever you want to compare notes:

```bash
mv src/_parked/03-noise src/scenes/
```

See `src/_parked/README.md` for what's in there and a suggested order.

## Checking your shaders without a browser

```bash
pnpm test:shaders    # also runs as part of `pnpm build`
```

This compiles **and links** every pass of every scene — parked ones included —
through `glslangValidator`, Khronos's reference GLSL compiler. Linking is the
part that matters: some rules govern the _relationship_ between the vertex and
fragment stage, so each shader can compile alone and still fail together. That's
the trap that produced the `iFrame` precision bug, which Chrome ran happily and
Firefox rejected.

Errors report your own line numbers, the same as the in-browser overlay:

```
01-gradient · image
ERROR: fragment:13: '' :  syntax error, unexpected SEMICOLON, expecting RIGHT_PAREN
```

The scenes are loaded through Vite's SSR loader and assembled by
`src/engine/shaderSource.ts` — the very module the engine uses — so what gets
validated is byte-for-byte what WebGL receives, injected uniforms and all.
It enforces the _spec_, though; browsers add quirks on top, so this is necessary
rather than sufficient. Keep opening Firefox occasionally.

## The uniforms your shaders get (ShaderToy-compatible)

```glsl
uniform vec3  iResolution;  // viewport size in pixels (z = 1.0)
uniform float iTime;        // seconds since the scene started
uniform float iTimeDelta;   // seconds since last frame
uniform int   iFrame;       // frame counter
uniform vec4  iMouse;       // xy = pointer px (y up), zw = click px

// level 4 only — the textures produced by other passes:
uniform sampler2D iChannel0, iChannel1, iChannel2, iChannel3;
uniform vec3 iChannelResolution[4];  // pixel size of each bound channel
```

You **don't declare these** — the engine injects them. Because the names match
ShaderToy, you can paste most ShaderToy fragment shaders straight into a
`frag.glsl`. Write either a ShaderToy-style `void mainImage(out vec4, in vec2)`
**or** a classic `void main()` using `gl_FragColor`; the engine detects which and
wraps it for you.

> Copying from **The Book of Shaders**? Rename `u_resolution` → `iResolution`,
> `u_time` → `iTime`, and remove its `uniform` lines (the engine already
> provides them).

## Add a scene (30 seconds)

Drop a folder under `src/scenes/` with a `scene.ts` that exports a `ShaderScene`.
It appears in the sidebar automatically — no registry to edit.

```ts
// src/scenes/06-my-idea/scene.ts
import type { ShaderScene } from '../../engine/types';
import fragment from './frag.glsl?raw';

const scene: ShaderScene = {
  id: '06-my-idea',
  title: 'My idea',
  level: 2,
  blurb: 'what it explores',
  fragment,
};
export default scene;
```

## Multi-pass scenes (level 4)

A `ShaderScene` can declare `passes`. Each pass is an ordinary fragment shader
that renders into a **texture** instead of the screen; later passes read those
textures as `iChannel0..3`. The scene's own `fragment` always runs last and is
what you see — exactly ShaderToy's Buffer A/B/C/D → Image model.

```ts
passes: [
  { id: 'scene',  fragment: sceneSrc },
  { id: 'bright', fragment: brightSrc, inputs: ['scene'], scale: 0.5 },
],
inputs: ['scene', 'bright'],  // -> iChannel0, iChannel1 in frag.glsl
fragment,
```

Three things are worth knowing before you write one:

`scale` sets the target size as a fraction of the canvas. Anything soft — blur,
bloom, glow — should run at `0.5`, both for the pixel count and because the
downsample blurs for free. Inside a pass, `iResolution` is _that pass's_ target
size, so `fragCoord / iResolution.xy` still gives you 0..1 uv, and
`iChannelResolution[n]` tells you the size of the texture you're reading (which
is how a blur converts a radius in pixels into a step in uv).

A pass that lists **its own id** in `inputs` reads its previous frame. That's
feedback, and it's how a shader gets memory. You can't sample a texture while
rendering into it, so the engine keeps two textures for that pass and swaps them
each frame — "ping-pong". Everything stateful on the GPU, from trails to fluid
to Game of Life, is built on this.

Targets are plain 8-bit RGBA, so values above 1.0 clamp between passes, and
resizing the canvas throws a feedback buffer's history away. Both are honest
limits of the simple version, and both are noted in the scene comments with a
pointer at what real engines do instead.

## Adding Pixi / Three later

The `Scene` type has a second variant, `CustomScene`, that is handed its own
`<canvas>` and owns it — so a Three.js or Pixi.js scene lives right alongside
your raw-GLSL scenes without the engine getting in the way. Ready-to-use
starters are in `src/scenes/_templates/` (`three-scene.ts.txt`,
`pixi-scene.ts.txt`). When you're ready:

```bash
pnpm add three        # or: pnpm add pixi.js
# copy _templates/three-scene.ts.txt -> src/scenes/06-three-cube/scene.ts
```

That scene shows up in the sidebar with a small `lib` badge. Your GLSL knowledge
carries straight over — only the plumbing (ShaderMaterial / Filter) is new.

## Roadmap (maps to the learning phases)

| Level | Folder pattern | Focus                                                       |
| ----- | -------------- | ----------------------------------------------------------- |
| 1     | `01-*`         | GLSL basics, color per pixel, `iTime`                       |
| 2     | `02..04-*`     | SDFs, patterns, noise, reading inputs · _parked_            |
| 3     | `05-*`         | vertex shaders, geometry, the perspective divide · _parked_ |
| 4     | `06..07-*`     | multi-pass / framebuffers: blur, bloom, feedback · _parked_ |
| —     | `_templates`   | graduate to Pixi / Three when GLSL is second nature         |

Next after level 4: point the same machinery at _simulation_ rather than
looks — Game of Life (`filter: 'nearest'`, one texel per cell), then
reaction–diffusion. The engine already does everything they need; only the
shader changes.

## Notes

- WebGL 1 / GLSL ES 1.00 on purpose — it's the simplest teaching target and
  matches The Book of Shaders. Three.js/WebGPU and TSL come later.
- Shader compile errors are shown full-screen with **your** line numbers
  (the engine emits `#line 1` before your source).
- Test in Firefox as well as Chrome. Chrome's ANGLE tolerates several things the
  GLSL ES spec forbids; Firefox enforces them. Uniform precision matching across
  stages is the classic one — see the comment above `PRECISION_HEADER` in
  `src/engine/shaderSource.ts`.
