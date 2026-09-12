// * LEVEL 1.1 — ALGORITHMIC DRAWING. A gallery of graphs, one per tile.
//
// House style, repo-wide: every SECTION heading starts with `// *`, and the
// lines under it are plain `//`. The Better Comments extension paints the
// starred line, so a long file skims as a list of headings.
//
// Follows https://thebookofshaders.com/05/ — shaping functions. The whole idea
// is small: a function takes x and gives back y, and the tile DRAWS that
// function so you can see its shape instead of imagining it. Once you can see
// them, you start reaching for them on purpose: linear for a plain ramp,
// smoothstep for an ease, pow for a bias, sin for a wobble.
//
// Two different things happen in every tile, and it is worth keeping them
// apart in your head:
//
//   1. THE COLOR is driven by the VALUE of y at this x. Every pixel in a
//      column gets the same y, so the tile reads as vertical bands going from
//      the "low" color to the "high" one. That is the function felt as a
//      gradient.
//   2. THE LINE is drawn where this pixel's HEIGHT equals y. That is the
//      function seen as a graph.
//
// The same number, shown twice. Cover one and you can still read the other.
//
// * A NOTE ON `pct`
//
// The Book of Shaders calls the plot's result `pct`, which is confusing the
// first time because there are two "percentages" in play:
//
//   y    = f(x)          the function's VALUE, 0..1 up the tile
//   pct  = plot(...)     how much of THIS PIXEL is covered by the line, 0..1
//
// `pct` is a blend percentage, used as the t in a mix(). It is not the
// percentage along the x axis. In this file it is called `lineCoverage`,
// because that is what it is.
//
// * LAYERS, back to front — same discipline as scene 02:
//
//   1. the value gradient    mix(lowColor, highColor, y)
//   2. the graph line        mix(lineColor, so far, lineCoverage)
//   3. the tile border       so the empty tiles are still visible
//
// * HOW THE GRID IS LAID OUT
//
// Exactly 5 x 5, filling the window, so the tiles STRETCH when the window is
// not square. That is deliberate: a gallery needs a fixed 25 slots so that
// "tile 7" always means the same function. Anchoring the tiles to the short
// edge would keep them square but change how many fit along the long edge,
// and the numbering would move as you resize. The commented alternative below
// does it the other way if you want to see the difference.
//
// Tiles are numbered in READING ORDER: 0 is top-left, 4 is top-right, 24 is
// bottom-right. GL's y axis points up, which is why the row term is flipped.

// * TUNING — the dials, each labelled with its space.
const float TILES_ACROSS = 5.0;    // count
const float TILES_DOWN   = 5.0;    // count
const float LINE_PIXELS  = 2.0;    // screen pixels: the graph line's width
const float BORDER_PIXELS = 1.0;   // screen pixels: the tile separator

// * PALETTE
//
// The value ramp is now pure black to pure white, which is the honest way to
// show a 0..1 number: no colour cast to read past, and 0.5 looks like 0.5.
//
// It also sets a constraint on everything drawn ON TOP. The ramp covers every
// grey there is, so any overlay that is itself grey will vanish wherever the
// background happens to match it. Two ways out, and this palette uses both:
//
//   1. differ in HUE. A saturated colour can never be confused with a value,
//      because no value is saturated.
//   2. sit in the MIDDLE of the luminance range, so the worst case is a tie
//      with mid grey rather than a disappearance into black or white.
//
// borderColor is a slate blue at luminance 0.42, so it reads against black
// (0.42 apart) and against white (0.58 apart), and its hue keeps it legible
// even where the background is mid grey.
//
// todoColor is deliberately NOT pure black. An unwritten tile must not look
// like a tile whose function returns 0 everywhere — those are different
// things and the picture should say so. The faint indigo tint is the tell.
vec3 lowColor    = vec3(0.00, 0.00, 0.00);  // y = 0
vec3 highColor   = vec3(1.00, 1.00, 1.00);  // y = 1
vec3 lineColor   = vec3(0.30, 1.00, 0.45);
vec3 borderColor = vec3(0.35, 0.42, 0.62);
vec3 todoColor   = vec3(0.11, 0.10, 0.16);
//
// The LINE is the interesting case, and the rule above needs correcting for it.
// Rule 2 — sit in the middle of the luminance range — does nothing here. On
// y = x the background of a column IS that column's value, so the line's
// backdrop sweeps the entire 0..1 ramp and every possible line luminance is
// matched exactly somewhere. Green (luminance 0.81) ties with the background
// at x = 0.81; red (0.41) ties at x = 0.41. Measured both: the worst
// luminance contrast is 0.002 and 0.001 respectively. Neither is better.
//
// And yet both lines are perfectly readable end to end, which is the lesson:
// what carries them is rule 1 alone. At the tie point the line is a saturated
// hue on a neutral grey, and chroma is doing all the work while luminance does
// none. So the choice of hue is free, and the only genuine mistake would be a
// desaturated line — a grey or near-grey line really would vanish at its own
// value, with nothing left to see it by.
//   vec3 lineColor = vec3(1.00, 0.25, 0.25);   // red, if you prefer it

// * PLOT — how much of this pixel the graph line covers, 0..1.
//
// `tileUv` is where we are inside the tile, 0..1 on both axes. `y` is the
// function's value at tileUv.x. So abs(tileUv.y - y) is "how far above or
// below the curve am I", and the line is everywhere that distance is small.
//
// That expression is a distance field, and this is the same two-step you built
// in scene 02: subtract a half-thickness to turn the curve into a BAND, then
// run it through a one-pixel ramp to get an anti-aliased mask. The only new
// part is measuring the thickness in screen pixels, which needs pixelY —
// one screen pixel expressed in tile-uv units.
//
// The Book of Shaders writes it in one line instead:
//
//   float plot(vec2 st) { return smoothstep(0.02, 0.0, abs(st.y - st.x)); }
//
// Same shape, two differences worth knowing. Its 0.02 is in tile-uv units, so
// the line gets visually thicker as the tile gets bigger; ours is in pixels
// and holds its weight. And smoothstep with the arguments in that order is a
// falling S-curve, which softens the edge over a fixed 0.02 rather than over
// one pixel, so it looks blurrier than it needs to.
//
// HONEST LIMITATION: abs(tileUv.y - y) measures straight UP, not perpendicular
// to the curve. Where the curve is steep the true distance is shorter than the
// vertical one, so the line looks thinner there. Watch it on a steep pow()
// curve and you will see it. The proper fix divides by sqrt(1 + slope*slope),
// which means knowing the derivative; the usual shortcut is fwidth(), and that
// needs an extension WebGL 1 does not give us by default. Live with it for
// now, but know it is there.
float plot(in vec2 tileUv, in float y, in float pixelY) {
  float distToCurve = abs(tileUv.y - y);
  float band = distToCurve - 0.5 * LINE_PIXELS * pixelY;
  return 1.0 - clamp(0.5 + band / pixelY, 0.0, 1.0);
}

// * PAINT ONE GRAPH — the body every tile shares.
//
// Hand it the y you computed and it does the rest: colour by the value, then
// draw the line on top. So a new tile is one line of maths plus one call.
vec3 drawGraph(in vec2 tileUv, in float y, in float pixelY) {
  vec3 color = mix(lowColor, highColor, y);
  float lineCoverage = plot(tileUv, y, pixelY);
  return mix(color, lineColor, lineCoverage);
}

// * TILE 00 — LINEAR, y = x.
//
// The identity function, and the one to start from because there is nothing to
// misread: the value rises evenly from 0 on the left to 1 on the right, so the
// gradient is even and the graph is the diagonal. Every other tile in the
// gallery is a comparison against this one.
vec3 tileLinear(in vec2 tileUv, in float pixelY) {
  float y = tileUv.x;
  return drawGraph(tileUv, y, pixelY);
}

// * TILE — NOT WRITTEN YET. Copy tileLinear, rename it, change the one line
// that computes y, and add it to drawTile below.
vec3 tileTodo(in vec2 tileUv, in float pixelY) {
  return todoColor;
}

// * DISPATCH — index in, color out.
//
// GLSL ES 1.00 has no function pointers and no arrays of functions, so a
// straight if-chain is the honest way to do this. It costs nothing real: every
// pixel takes exactly one branch, and the branch is the same for every pixel
// in a tile, which is the case GPUs handle best.
//
// Uncomment a line as you write each tile.
vec3 drawTile(in int index, in vec2 tileUv, in float pixelY) {
  if (index == 0) return tileLinear(tileUv, pixelY);
  // if (index == 1) return tileSmoothstep(tileUv, pixelY);
  // if (index == 2) return tilePow2(tileUv, pixelY);
  // if (index == 3) return tileSqrt(tileUv, pixelY);
  // if (index == 4) return tileSine(tileUv, pixelY);
  return tileTodo(tileUv, pixelY);
}

// * TILE BORDER — a thin separator so empty tiles still read as tiles.
// tileUv is 0..1 inside the tile, so min(tileUv, 1 - tileUv) is the distance
// to the nearest edge on each axis, and the smaller of the two is the distance
// to the nearest edge at all. Same coverage ramp as everything else.
float tileBorder(in vec2 tileUv, in vec2 tilePixel) {
  vec2 toEdge = min(tileUv, 1.0 - tileUv) / tilePixel;   // in screen pixels
  float dist = min(toEdge.x, toEdge.y) - BORDER_PIXELS;
  return 1.0 - clamp(0.5 + dist, 0.0, 1.0);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
  // 0..1 across the whole window. uv, not the centred pos of scene 02, because
  // a grid of graphs wants "where am I across the picture", and each graph
  // wants its own 0..1 box.
  vec2 uv = fragCoord / iResolution.xy;

  vec2 grid = vec2(TILES_ACROSS, TILES_DOWN);

  // Square tiles anchored to the short edge, if you want to see the other
  // choice. The tile count along the long axis stops being a whole number, so
  // the edge tiles get clipped and the numbering shifts as you resize:
  // grid = vec2(TILES_ACROSS) * iResolution.xy / min(iResolution.x, iResolution.y);

  vec2 cell    = uv * grid;      // 0..5 across, 0..5 up
  vec2 tileId  = floor(cell);    // which tile: 0..4 on each axis
  vec2 tileUv  = fract(cell);    // where inside it: 0..1 on each axis

  // One screen pixel, measured in tile-uv units, per axis. The tiles are
  // stretched, so x and y are different numbers — that is exactly why this is
  // a vec2 and not a float.
  vec2 tilePixel = grid / iResolution.xy;

  // Reading order: 0 top-left, 24 bottom-right. GL's y points up, so the row
  // has to be flipped to count downward.
  int index = int(tileId.x) + int((TILES_DOWN - 1.0) - tileId.y) * int(TILES_ACROSS);

  vec3 color = drawTile(index, tileUv, tilePixel.y);
  color = mix(color, borderColor, tileBorder(tileUv, tilePixel));

  fragColor = vec4(color, 1.0);
}

// * EXERCISES — the gallery, roughly in the order The Book of Shaders builds
// them. One tile each. Write the function, add it to drawTile, look at it
// beside the linear one.
// ---------------------------------------------------------------------------
//
// 0. LINEAR.  [done]  y = x
//
// 1. SMOOTHSTEP.  y = smoothstep(0.0, 1.0, x)
//    An S-curve: flat at both ends, steep in the middle. This is the ease you
//    already used for anti-aliasing, seen as a shape for the first time.
//    Then try narrowing the edges: smoothstep(0.3, 0.7, x).
//
// 2. POWER.  y = pow(x, 2.0), then 0.5, then 5.0
//    Bias. Above 1.0 pushes values toward 0 (slow start, fast finish); below
//    1.0 does the opposite. pow(x, 0.5) is sqrt(x). This is the knob to reach
//    for when something "ramps up too fast".
//
// 3. STEP AND CLAMP.  y = step(0.5, x), and y = clamp(x * 2.0 - 0.5, 0.0, 1.0)
//    The hard cut, and the flattened ramp. Worth drawing once so the staircase
//    edges of step() are a picture rather than a warning.
//
// 4. SINE.  y = 0.5 + 0.5 * sin(x * 6.2831)
//    The 0.5 + 0.5 * pattern you have written many times, finally graphed. One
//    full period across the tile because 6.2831 is 2*PI. Multiply x by 2.0 for
//    two humps.
//
// 5. FRACT AND MOD.  y = fract(x * 3.0), y = mod(x * 3.0, 1.0)
//    Sawtooth. The vertical jumps show why fract() tiles and why the seam is
//    always at the integers.
//
// 6. ABS AND SIGN.  y = abs(x * 2.0 - 1.0)
//    The V. Same fold you used in sdBox, one dimension down.
//
// 7. MIN, MAX, MIXING TWO CURVES.  y = min(x, 1.0 - x), y = mix(a, b, x)
//    Where the union and intersection of scene 02 come from, seen as graphs.
//
// 8. ANIMATE ONE.  Multiply anything by iTime inside a sin(), or move a
//    smoothstep's edges with it, and watch the curve breathe. The graph is the
//    quickest way to understand an animation you cannot yet picture.
//
// EXTRA CREDIT, once the gallery fills up: label the tiles by drawing a small
// bar at the bottom whose length is the index, or colour the border of the
// tile you are hovering using iMouse.
//
// STUCK? `pnpm test:shaders` will tell you about syntax and type errors without
// you having to hunt for a blank screen in the browser.
