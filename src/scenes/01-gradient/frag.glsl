// * YOUR FIRST SHADER — the "hello world" of GLSL.
//
// House style, repo-wide: every SECTION heading starts with `// *`, and the
// lines under it are plain `//`, so the file skims as a list of headings.
// This function runs ONCE PER PIXEL, in parallel, for every pixel on screen.
// fragCoord = this pixel's position in pixels, origin at bottom-left, measured
// at the pixel's CENTRE — so it goes 0.5, 1.5, 2.5 ... and never lands exactly
// on a whole number. That half-pixel is why uv never quite reaches 0.0 or 1.0.
//
// The uniforms iResolution / iTime are provided for you (see the engine).

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
  // * TWO NAMES FOR THE SAME PIXEL. They answer different questions, so it's
  // normal to compute both and use whichever the next line needs.
  //
  // The same screen, labelled two ways (a = width / height, the aspect):
  //
  //        uv  — corner to corner              pos — centred, square
  //
  //     (0,1) +-------------+ (1,1)      (-a,1) +-------------+ (a,1)
  //           |             |                   |             |
  //           |             |                   |      + (0,0)|
  //           |             |                   |             |
  //     (0,0) +-------------+ (1,0)     (-a,-1) +-------------+ (a,-1)
  //
  //   0..1 on BOTH axes, so a               -1..1 up, wider than that
  //   square of uv is a rectangle           across, so a square of pos
  //   on a non-square window                really is square on screen
  //
  // uv: "where am I across the picture" — gradients, tiling, sampling a texture.
  vec2 uv  = fragCoord / iResolution.xy;                          // 0..1 — image space
  // pos: "where am I in space" — distance, shapes, rotation. BOTH axes are divided
  // by the height, so one unit across equals one unit up and circles stay round.
  vec2 pos = (2.0 * fragCoord - iResolution.xy) / iResolution.y;  // centred, square units

  // * TILE WITH fract(). It wraps once per 1.0 of input, so the tile count is the input's RANGE
  // times `tiles` — not `tiles` on its own. uv spans exactly 1.0 per axis, so
  // this gives exactly 2 x 2 tiles, each stretched by the canvas aspect ratio.
  //
  // Following one axis through the two steps:
  //
  //   uv              0 ------------------------- 1      spans 1.0
  //                             |
  //                             | * tiles (2.0)
  //                             v
  //   uv * tiles      0 ------------ 1 ------------ 2     spans 2.0
  //                             |
  //                             | fract() throws away the whole number
  //                             v
  //   cellPos         0 ------- 1  0 ------- 1            2 tiles, seam at 1
  //
  // So the tile count is how many INTEGERS the input crosses, which is its
  // range times `tiles`. That is the whole rule, and it is why swapping in
  // `pos` below changes the count without changing this line.
  const float tiles = 2.0;
  vec2 cellPos = fract(uv * tiles);
  // Swap in pos and the same `tiles` gives 4 rows and 4 x aspect columns, because
  // pos spans 2.0 vertically. Those tiles come out square rather than stretched,
  // and a seam lands on 0.0 — the centre of the screen — since 0 is an integer.
  // vec2 cellPos = fract(pos * tiles);

  // * COLOR FROM THE TILE COORDINATE.
  // cellPos.x -> red rising left to right WITHIN each tile,
  // cellPos.y -> green rising bottom to top within each tile,
  // and a blue channel that breathes over time with iTime.
  vec3 color = vec3(cellPos.x, cellPos.y, 0.5 + 0.5 * sin(iTime));

  // shorthand for RG by cellPos.x/cellPos.y
  // vec3 color = vec3(cellPos, 0.5 + 0.5 * sin(iTime));

  // * OUTPUT: red, green, blue, alpha.
  fragColor = vec4(color, 1.0);
}

// * TRY THIS:
//  • uncomment the pos line above — the seam jumps to the middle of the screen
//  • mirror instead of wrapping, for tiling with no hard seams:
//      vec2 cellPos = abs(fract(uv * tiles) * 2.0 - 1.0);
//  • colour by WHICH tile instead of position inside it — fract gives you the
//    first, floor gives you the second, and you'll want both in level 2:
//      vec2 cell = floor(uv * tiles);
//      vec3 color = vec3(mod(cell.x + cell.y, 2.0));
//  • drop the `const` and animate it: tiles = 1.0 + 3.0 * (0.5 + 0.5 * sin(iTime))
