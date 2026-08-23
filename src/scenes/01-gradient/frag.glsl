// Your first shader — the "hello world" of GLSL.
// This function runs ONCE PER PIXEL, in parallel, for every pixel on screen.
// fragCoord = this pixel's position in pixels, origin at bottom-left, measured
// at the pixel's CENTRE — so it goes 0.5, 1.5, 2.5 ... and never lands exactly
// on a whole number. That half-pixel is why uv never quite reaches 0.0 or 1.0.
//
// The uniforms iResolution / iTime are provided for you (see the engine).

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
  // Two names for the same pixel. They answer different questions, so it's
  // normal to compute both and use whichever the next line needs.
  // uv: "where am I across the picture" — gradients, tiling, sampling a texture.
  vec2 uv  = fragCoord / iResolution.xy;                          // 0..1 — image space
  // pos: "where am I in space" — distance, shapes, rotation. BOTH axes are divided
  // by the height, so one unit across equals one unit up and circles stay round.
  vec2 pos = (2.0 * fragCoord - iResolution.xy) / iResolution.y;  // centred, square units

  // fract() wraps once per 1.0 of input, so the tile count is the input's RANGE
  // times `tiles` — not `tiles` on its own. uv spans exactly 1.0 per axis, so
  // this gives exactly 2 x 2 tiles, each stretched by the canvas aspect ratio.
  const float tiles = 2.0;
  vec2 cellPos = fract(uv * tiles);
  // Swap in pos and the same `tiles` gives 4 rows and 4 x aspect columns, because
  // pos spans 2.0 vertically. Those tiles come out square rather than stretched,
  // and a seam lands on 0.0 — the centre of the screen — since 0 is an integer.
  // vec2 cellPos = fract(pos * tiles);

  // cellPos.x -> red rising left to right WITHIN each tile,
  // cellPos.y -> green rising bottom to top within each tile,
  // and a blue channel that breathes over time with iTime.
  vec3 color = vec3(cellPos.x, cellPos.y, 0.5 + 0.5 * sin(iTime));

  // shorthand for RG by cellPos.x/cellPos.y
  // vec3 color = vec3(cellPos, 0.5 + 0.5 * sin(iTime));

  // Output: red, green, blue, alpha.
  fragColor = vec4(color, 1.0);
}

// TRY THIS:
//  • uncomment the pos line above — the seam jumps to the middle of the screen
//  • mirror instead of wrapping, for tiling with no hard seams:
//      vec2 cellPos = abs(fract(uv * tiles) * 2.0 - 1.0);
//  • colour by WHICH tile instead of position inside it — fract gives you the
//    first, floor gives you the second, and you'll want both in level 2:
//      vec2 cell = floor(uv * tiles);
//      vec3 color = vec3(mod(cell.x + cell.y, 2.0));
//  • drop the `const` and animate it: tiles = 1.0 + 3.0 * (0.5 + 0.5 * sin(iTime))
