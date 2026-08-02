// ---------------------------------------------------------------------------
// Shader assembly: turning the GLSL you write into the GLSL the driver sees.
//
// This lives in its own file for one reason: `scripts/check-shaders.mjs`
// imports it too. The validator has to check the EXACT strings the engine
// hands to WebGL, headers and all — a checker that rebuilds them itself would
// slowly drift out of sync and quietly stop testing the real thing.
// ---------------------------------------------------------------------------

// These uniforms are injected into every scene's shaders, so you never declare
// them yourself. Names match ShaderToy so you can paste shaders across.
export const UNIFORM_HEADER = /* glsl */ `
uniform vec3  iResolution;   // viewport size in pixels (z = 1.0)
uniform float iTime;         // seconds since the scene started
uniform float iTimeDelta;    // seconds since the last frame
uniform int   iFrame;        // frame counter
uniform vec4  iMouse;        // xy = mouse px (y up), zw = click px
uniform sampler2D iChannel0; // level 4: the output texture of another pass
uniform sampler2D iChannel1;
uniform sampler2D iChannel2;
uniform sampler2D iChannel3;
uniform vec3 iChannelResolution[4]; // pixel size of each bound channel
`;

export const DEFAULT_VERT_QUAD = /* glsl */ `
attribute vec2 aPosition;
void main() {
  gl_Position = vec4(aPosition, 0.0, 1.0);
}
`;

export const DEFAULT_VERT_GRID = /* glsl */ `
attribute vec3 aPosition;
attribute vec2 aUv;
varying vec2 vUv;
void main() {
  vUv = aUv;
  gl_Position = vec4(aPosition, 1.0);
}
`;

// Precision, declared identically in BOTH stages — and it has to be identical.
// GLSL ES 1.00 gives the two stages different DEFAULTS: `int` defaults to highp
// in a vertex shader but mediump in a fragment shader. Since the uniform block
// above is injected into both, `uniform int iFrame` would end up declared at two
// different precisions, and the spec says a uniform that doesn't match exactly
// in type *and* precision is not linkable. Chrome's ANGLE quietly tolerates it;
// Firefox refuses with "Uniform `iFrame` is not linkable between attached
// shaders". Spelling out both precisions removes the difference.
//
// (`highp` in a fragment shader is optional in ES 1.00, but highp float and
// highp int are gated by the same flag — so this adds no requirement that
// `precision highp float` didn't already impose.)
export const PRECISION_HEADER = `precision highp float;\nprecision highp int;\n`;

/** Build a fragment shader: precision + uniforms + your source (+ a main()
 *  wrapper if you wrote a ShaderToy-style mainImage instead of main). */
export function assembleFragment(userSrc: string): string {
  const hasMainImage = /void\s+mainImage\s*\(/.test(userSrc);
  const hasMain = /void\s+main\s*\(/.test(userSrc);
  const wrapper =
    hasMainImage && !hasMain
      ? `\nvoid main() {\n  vec4 color = vec4(0.0, 0.0, 0.0, 1.0);\n  mainImage(color, gl_FragCoord.xy);\n  gl_FragColor = color;\n}\n`
      : '';
  return (
    PRECISION_HEADER +
    UNIFORM_HEADER +
    `\n#line 1\n` + // so shader-compile errors report YOUR line numbers
    userSrc +
    wrapper
  );
}

export function assembleVertex(userSrc: string): string {
  return PRECISION_HEADER + UNIFORM_HEADER + `\n#line 1\n` + userSrc;
}
