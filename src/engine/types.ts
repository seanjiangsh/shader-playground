// ---------------------------------------------------------------------------
// Scene types
// ---------------------------------------------------------------------------
// There are two kinds of scene:
//
//   1. ShaderScene  — the everyday kind. You just supply GLSL. The engine
//                     compiles it, draws it on a fullscreen quad (or a grid),
//                     and feeds it ShaderToy-style uniforms. This is what you
//                     use for levels 1–4 while learning raw GLSL.
//
//   2. CustomScene  — an escape hatch. The scene is handed its own <canvas>
//                     and does whatever it wants with it. This is how you add
//                     Pixi.js or Three.js scenes LATER without touching the
//                     engine: a Three scene just news up a THREE.WebGLRenderer
//                     on the canvas it's given. See src/scenes/_templates/.
//
// Every scene, whichever kind, shows up in the sidebar automatically.
// ---------------------------------------------------------------------------

/** Which built-in geometry a ShaderScene draws onto. */
export type Geometry =
  | 'quad' // two triangles covering the screen — the ShaderToy model (fragment only)
  | 'grid'; // a subdivided plane — needed when you want a vertex shader to move points

/**
 * One off-screen pass (level 4). This is ShaderToy's "Buffer A/B/C/D" idea:
 * a fragment shader that draws into a texture instead of the screen, so a
 * LATER pass can read the result. Chain a few and you get blur, bloom,
 * feedback, or a simulation whose state lives in a texture.
 *
 * Passes run in array order, then the scene's own `fragment` runs last and
 * goes to the screen (that's ShaderToy's "Image" tab).
 */
export interface Pass {
  /** Name other passes use in their `inputs`. Keep it short: 'blurH', 'state'. */
  id: string;
  /** Fragment shader source, same rules as a scene's: mainImage or main. */
  fragment: string;
  /** Optional vertex shader. Rarely needed — passes are usually a plain quad. */
  vertex?: string;
  /** Defaults to 'quad'. Use 'grid' to render real geometry into a texture. */
  geometry?: Geometry;
  /** Grid resolution when geometry === 'grid'. Default 128. */
  gridResolution?: number;
  /**
   * Pass ids to bind as iChannel0, iChannel1, … (up to 4), in this order.
   * A pass may list ITSELF: that means "read my own previous frame", and the
   * engine keeps two textures for it and swaps them each frame (ping-pong).
   */
  inputs?: string[];
  /**
   * Render target size as a fraction of the canvas. Default 1.
   * 0.5 is the standard blur trick: a quarter of the pixels, and the hardware's
   * bilinear filtering does part of the blurring for you, for free.
   */
  scale?: number;
  /**
   * Texture filtering when a later pass samples this one. Default 'linear'.
   * Use 'nearest' when the texture holds simulation state rather than an image
   * — you don't want neighbouring cells silently blended together.
   */
  filter?: 'nearest' | 'linear';
}

export interface ShaderScene {
  kind?: 'shader';
  /** Stable id, also used in the URL hash. Usually the folder name. */
  id: string;
  /** Human title shown in the sidebar. */
  title: string;
  /** 1–4. Groups the scene in the sidebar and hints at difficulty. */
  level: number;
  /** One-line description shown under the canvas. */
  blurb?: string;

  /** Fragment shader source (GLSL ES 1.00). */
  fragment: string;
  /**
   * Optional vertex shader source. If omitted, the engine uses a passthrough
   * vertex shader suited to the chosen geometry. Provide your own once you
   * reach level 3 and want to move vertices.
   */
  vertex?: string;
  /** Defaults to 'quad'. Use 'grid' for vertex-shader scenes. */
  geometry?: Geometry;
  /** Grid resolution when geometry === 'grid'. Default 128 (128×128 cells). */
  gridResolution?: number;

  /**
   * Level 4: off-screen passes to run before this scene's `fragment`, in order.
   * Omit for a normal single-pass scene — nothing changes.
   */
  passes?: Pass[];
  /**
   * Pass ids bound to iChannel0, iChannel1, … for the final on-screen fragment.
   */
  inputs?: string[];
}

/** Handle returned by a CustomScene so the app can tear it down on switch. */
export interface SceneInstance {
  dispose(): void;
}

export interface CustomScene {
  kind: 'custom';
  id: string;
  title: string;
  level: number;
  blurb?: string;
  /**
   * Called once when this scene becomes active. You own the canvas from here.
   * Return something with dispose() so we can clean up when the user switches
   * away (stop your RAF loop, destroy the Pixi/Three renderer, etc).
   */
  mount(canvas: HTMLCanvasElement): SceneInstance;
}

export type Scene = ShaderScene | CustomScene;

export function isCustomScene(s: Scene): s is CustomScene {
  return s.kind === 'custom';
}
