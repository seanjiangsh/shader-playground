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
// The same number, shown twice. Cover one and you can still read the other:
//
//        1 +---------------------------+
//          |                     __--''|   the LINE: this pixel is on it
//          |               __--''      |   when its height equals y
//     tile |         __--''            |
//   height |   __--''                  |   the GRADIENT: this column's
//          |--''                       |   colour IS y, so the whole column
//        0 +---------------------------+   is one shade
//          0          x  (0..1)        1
//
//          dark ......................... light      <- what the colour does
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
// Tiles are numbered in READING ORDER, the way you would read a page:
//
//        +----+----+----+----+----+
//        |  0 |  1 |  2 |  3 |  4 |   <- top row
//        +----+----+----+----+----+
//        |  5 |  6 |  7 |  8 |  9 |
//        +----+----+----+----+----+
//        | 10 | 11 | 12 | 13 | 14 |
//        +----+----+----+----+----+
//        | 15 | 16 | 17 | 18 | 19 |
//        +----+----+----+----+----+
//        | 20 | 21 | 22 | 23 | 24 |   <- bottom row
//        +----+----+----+----+----+
//
// GL's y axis points UP, so row 0 of the coordinates is the bottom one. That
// is why the row term is flipped when the index is computed in mainImage.

// * TUNING — the dials, each labelled with its space.
const float TILES_ACROSS = 5.0;    // count
const float TILES_DOWN   = 5.0;    // count
const float LINE_PIXELS  = 2.0;    // screen pixels: the graph line's width
const float BORDER_PIXELS = 1.0;   // screen pixels: the tile separator
const float WAVE_SPEED   = 2.0;    // radians per second: how fast the wave travels
const float PULSE_SPEED  = 1.0;    // radians per second: how fast the arch breathes

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

// * CONSTANTS
const float PI = 3.14159265;
const float TWO_PI = 6.28318531;

// * sin01 — sine, remapped from its natural -1..1 swing into 0..1.
//
// This tiny function is the most reusable idea in the sine family, and naming
// it is worth more than the characters it saves. sin() answers a question
// about angles and hands back a number that is half negative; a tile, a colour
// channel and a brightness all want 0..1. The `0.5 + 0.5 *` shuffle is how you
// get from one to the other, and it turns up everywhere once you start looking.
//
// What it does to the number line:
//
//   sin gives you    -1 ---------- 0 ---------- +1
//                     |            |            |
//   * 0.5            -0.5 ------- 0 --------- +0.5    (half the swing)
//                     |            |            |
//   + 0.5             0 --------- 0.5 --------- 1     (lift the middle)
//
// So the two halves do two separate jobs: multiplying by 0.5 shrinks the swing
// so it spans 1 instead of 2, and adding 0.5 moves the middle up from 0 to 0.5.
float sin01(in float angle) {
  return 0.5 + 0.5 * sin(angle);
}

// * PLOT — how much of this pixel the graph line covers, 0..1.
//
// `tileUv` is where we are inside the tile, 0..1 on both axes. `y` is the
// function's value at tileUv.x. So abs(tileUv.y - y) is "how far above or
// below the curve am I", and the line is everywhere that distance is small.
//
// Looking at one column of pixels, side on:
//
//     tileUv.y
//        ^
//        |   .  distToCurve is big    -> outside the line, returns 0
//        |   .
//        |  ---------------------------  y + half the thickness
//        |  ~~~~~~ the curve, y ~~~~~~~  distToCurve = 0
//        |  ---------------------------  y - half the thickness
//        |   .
//        |   .  distToCurve is big    -> outside the line, returns 0
//
// Which is the same two-step you built in scene 02, reused exactly:
//
//   distToCurve = abs(tileUv.y - y)        a distance field, 0 on the curve
//   band        = distToCurve - half       NEGATIVE inside the line's band
//   mask        = the one-pixel ramp       soft edge, no jaggies
//
// The only new part is measuring the thickness in screen pixels, which needs
// pixelY — one screen pixel expressed in tile-uv units.
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
// vertical one, so the line looks thinner there — and past a certain steepness
// it stops being a line at all and becomes a row of dashes. Tile 08 at two
// humps is the first place it is unmistakable; the numbers are in its comment.
//
//     measured UP           measured PERPENDICULAR
//                                   /
//        |  /                      /|
//        | /  <- the band is      / |  <- the band stays the same width
//        |/      LINE_PIXELS     /  |     whichever way the curve leans
//       /|       tall, so a     /   |
//      / |       steep curve   /
//               gets a thin
//               sliver of it
//
// The correction is one multiply: the vertical band has to grow by
// sqrt(1 + slope*slope). Three ways to get the slope, worst to best:
//
//   1. Raise LINE_PIXELS until the dashes overlap. Works, but it fattens the
//      flat parts too — the wrong lever for a steep-curve problem.
//   2. Ask the tile for a second sample and difference them:
//        slope = (yAt(x + pixelX) - yAt(x)) / pixelX
//      No calculus, works for any function, costs one extra evaluation. It
//      does mean drawGraph grows an argument and every tile passes two y's.
//   3. fwidth(y) — ask the GPU how much y changed between neighbouring pixels.
//      One line, no second sample. It needs the OES_standard_derivatives
//      extension, which WebGL 1 does not switch on by default but which is
//      available essentially everywhere in practice (measured at 99.97% of
//      devices on web3dsurvey.com, 97% on caniuse). Turning it on is a small
//      engine change: gl.getExtension('OES_standard_derivatives') plus an
//      `#extension GL_OES_standard_derivatives : enable` line in the injected
//      header, and the same line in scripts/check-shaders.mjs so the validator
//      still matches what the engine builds.
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

// * TILE 01 — SMOOTHSTEP, the ease.
//
// You have used smoothstep since scene 01 for anti-aliasing. This is the first
// time you can SEE what it is: an S. Flat at both ends, steepest in the middle.
//
// What it actually computes, once the edges are taken care of:
//
//   t = clamp((x - edge0) / (edge1 - edge0), 0, 1)   where am I between them
//   y = t * t * (3 - 2 * t)                          the S itself
//
// That cubic is chosen so its SLOPE is zero at t = 0 and t = 1. Which is the
// whole point of an ease: something that starts and stops without a jerk. The
// linear tile next door has slope 1 everywhere, including at the ends, which
// is exactly what makes a linear animation feel mechanical.
//
// The gradient says it better than the graph. Look at the tile: black holds on
// for a long time, white holds on for a long time, and the change happens in a
// rush through the middle. That IS the ease, felt rather than plotted.
//
// EDGES 0.05 AND 0.95 rather than 0 and 1 — a real choice with two effects.
// Squeezing the same S into a span of 0.9 makes it steeper: the maximum slope
// goes from 1.5 to 1.5 / 0.9 = 1.667. And because the clamp is doing work now,
// y is exactly 0 for the first 5% of the tile and exactly 1 for the last 5%,
// so the curve has genuinely FLAT runs at both ends instead of just touching
// the corners. Those runs sit right on the tile boundary and end up half
// hidden under the border, which is what you can see at the bottom-left and
// top-right. Not wrong, just worth knowing you chose it. smoothstep(0.0, 1.0,
// x) gives the plain version with no flat runs.
//
// WATCH THE LINE WIDTH. This is the first tile steep enough to show the
// limitation noted on plot(): it measures straight up, not perpendicular to
// the curve. The vertical thickness is a constant 2.00 px everywhere — I
// measured it — but the width you actually SEE is that divided by
// sqrt(1 + slope*slope), which at the steepest point is 2 / 1.94 = 1.03 px.
// So the line looks about half as thick through the middle as it does at the
// ends. Nothing is broken; the ruler is just pointing the wrong way.
vec3 tileSmoothstep(in vec2 tileUv, in float pixelY) {
  float y = smoothstep(0.05, 0.95, tileUv.x);
  return drawGraph(tileUv, y, pixelY);
}

// * TILES 02, 03, 04 — POWER, the bias dial.
//
// Three tiles, one function, one number changed. That is the point of writing
// it with the exponent as a PARAMETER rather than as three near-identical
// copies: pow is not three shaping functions, it is one with a dial on it.
//
// What the dial does, in one sentence: raising a number BETWEEN 0 AND 1 to a
// power above 1 makes it smaller, and to a power below 1 makes it bigger. Our
// x is always 0..1, so that is the whole behaviour.
//
//   exponent   at x = 0.5   the curve           the gradient
//   --------   ----------   -----------------   ----------------------------
//     0.5        0.707      bulges ABOVE the    brightens early, then coasts
//                           diagonal            (most of the tile is light)
//     1.0        0.500      IS the diagonal     even — no bias at all
//     2.0        0.250      sags BELOW the      stays dark, rushes at the end
//                           diagonal            (most of the tile is dark)
//
// The three shapes, side by side:
//
//       pow(x, 0.5)        pow(x, 1.0)        pow(x, 2.0)
//    1 |    _--''''     1 |         ,'     1 |          /
//      |  ,'              |       ,'         |         /
//      | /                |     ,'           |       ,'
//      |/                 |   ,'             |    _,'
//    0 +------------    0 + ,'--------     0 +--''-------
//      0           1      0           1      0           1
//
//       fast start,       the straight       slow start,
//       slow finish         reference        fast finish
//
// 1.0 earns its slot even though it is identical to tile 00. It is the neutral
// middle of the family, and having "no bias" drawn between the two biased ones
// is what makes the other two readable at a glance.
//
// 0.5 and 2.0 are MIRROR IMAGES of each other, reflected across the diagonal.
// That is not a coincidence: x^0.5 is the square root, which is the inverse of
// x^2, and a function and its inverse are always reflections in the line
// y = x. Once you see that, the whole family reads as one shape being tipped
// one way or the other.
//
// Reach for it when something "ramps up too fast" or "hangs around too long".
// A fade that feels sudden usually wants an exponent above 1; a bar that takes
// forever to get going usually wants one below 1.
//
// TWO NOTES ON pow() ITSELF, since this is the first tile that really uses it.
//
// It has a DOMAIN. In GLSL ES, pow(x, y) is undefined when x is negative, and
// also when x is 0 and y is 0 or less. Here x is a tile coordinate, so it is
// never negative, and every exponent used is positive, so we are safe — but
// only because of those two facts, not because pow is safe in general. The
// first attempt at this tile passed tileUv.y as the exponent, which put
// pow(0.0, 0.0) at the tile's bottom-left corner: undefined, and drivers
// disagree about what to return there.
//
// And for a SQUARE specifically, tileUv.x * tileUv.x is the better line. It is
// one multiply, where pow usually compiles to exp2(y * log2(x)), and it has no
// domain restrictions at all. pow earns its place the moment the exponent is
// not a small whole number, which is exactly why 0.5 is in this family.
//
// WATCH THE LINE WIDTH on the 2.0 tile. It is the steepest curve in the
// gallery so far, and plot() measures straight up rather than perpendicular to
// the curve, so the line thins out noticeably at the right-hand end. Same
// artifact as on smoothstep, more obvious here.
vec3 tilePow(in vec2 tileUv, in float pixelY, in float exponent) {
  float y = pow(tileUv.x, exponent);
  return drawGraph(tileUv, y, pixelY);
}

// * TILES 05, 06, 07 — SINE, and the first things in the gallery that MOVE.
//
// The idea that unlocks all of this: everything inside sin() is an ANGLE in
// radians, and iTime is SECONDS. So any number multiplying iTime is radians
// per second, and one full cycle takes TWO_PI divided by it. WAVE_SPEED = 2.0
// is a cycle every 3.1 seconds. For N cycles per second, use N * TWO_PI.
//
// There are exactly three things you can animate in a wave, and they feel
// completely different. Two are here; the third is exercise 4b.
//
//   PHASE      add to the angle       the wave slides sideways    <- tile 06
//   AMPLITUDE  multiply the result    the wave grows and shrinks  <- tile 07
//   FREQUENCY  multiply x             more or fewer humps         <- exercise
//
// Tile 05 is the still reference, and it earns its slot: motion is hard to
// judge with nothing beside it holding still.

vec3 tileSine(in vec2 tileUv, in float pixelY) {
  float y = sin01(tileUv.x * TWO_PI);
  return drawGraph(tileUv, y, pixelY);
}

// PHASE. Adding to the angle slides the whole wave along x — add and it
// travels left, subtract and it travels right. Nothing about the wave's SHAPE
// changes, which is exactly what makes it read as movement rather than as
// distortion.
vec3 tileSinePhase(in vec2 tileUv, in float pixelY) {
  float y = sin01(tileUv.x * TWO_PI + iTime * WAVE_SPEED);
  return drawGraph(tileUv, y, pixelY);
}

// AMPLITUDE. Multiplying the result scales the wave's height.
//
// The base here is the ARCH, sin(x * PI), not the full period the other two
// use, and that is the right call rather than an inconsistency. The arch
// already sits on zero at both ends, so scaling it down reads as deflating.
// Scale a full 0..1 period instead and the whole wave sinks toward black,
// which reads as the graph falling out of the tile rather than as a pulse.
//
// sin01 is doing a second, different job here. Its output is the MULTIPLIER,
// and a multiplier has to stay in 0..1 or a negative one would flip the arch
// upside down and out of sight. Same helper, opposite end of the expression.
vec3 tileSineAmplitude(in vec2 tileUv, in float pixelY) {
  float y = sin(tileUv.x * PI) * sin01(iTime * PULSE_SPEED);
  return drawGraph(tileUv, y, pixelY);
}

// FREQUENCY, the third knob. Multiplying x decides how many humps fit across
// the tile.
//
// The trap avoided here: sin(tileUv.x * iTime) looks reasonable and is wrong,
// because iTime grows forever, so the humps get denser without limit until
// the tile is a grey blur. mix() between two fixed values keeps it bounded,
// and the wave breathes instead of running away.
//
// The 0 end of the range is worth watching rather than treating as a corner
// case. At humps = 0 the angle is 0 everywhere, sin(0) is 0, and sin01 turns
// that into 0.5 — so the tile flattens to mid grey with a straight line
// through the middle. "No wave" is not a broken wave, it is a flat one.
//
// Unlike tile 06, this does not TRAVEL, it STRETCHES. The angle at any point
// is TWO_PI * humps * x, which stays 0 at x = 0 whatever humps does, so the
// left edge is pinned and every point moves more the further right it sits.
// Watch the two tiles side by side: one slides bodily, one accordions.
//
// THE LINE GOES DOTTED at the busy end, and this is the tile that finally
// makes plot()'s limitation impossible to ignore. plot() lights a band
// measured straight UP, LINE_PIXELS tall, which is 2 screen pixels. But on a
// 180 x 120 tile the steepest part of the wave climbs:
//
//     humps = 1     2.1 screen pixels of rise per column   (just about joins)
//     humps = 2     4.2 screen pixels of rise per column   (visible dashes)
//     humps = 3     6.3 screen pixels of rise per column   (clearly dotted)
//
// Every column IS lit — none are skipped — but each column's 2-pixel dash
// sits several pixels above its neighbour, so the dashes never touch:
//
//     column:  1     2     3     4
//                               [=]      each dash is LINE_PIXELS tall
//                         [=]
//                   [=]                  but the next one is 4 px away
//              [=]
//
// On the flat parts the rise per column is nearly zero, the dashes overlap,
// and the line looks solid. That is why it only breaks up where it is steep.
// The fix is to measure PERPENDICULAR to the curve rather than vertically,
// which means the band has to grow by sqrt(1 + slope*slope) — see the note on
// plot() for the three ways to get that slope.
vec3 tileSineFrequency(in vec2 tileUv, in float pixelY) {
  float humps = mix(0.0, 2.0, sin01(iTime));
  float y = sin01(tileUv.x * TWO_PI * humps);
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
  if (index == 1) return tileSmoothstep(tileUv, pixelY);
  if (index == 2) return tilePow(tileUv, pixelY, 0.5);
  if (index == 3) return tilePow(tileUv, pixelY, 1.0);
  if (index == 4) return tilePow(tileUv, pixelY, 2.0);
  if (index == 5) return tileSine(tileUv, pixelY);
  if (index == 6) return tileSinePhase(tileUv, pixelY);
  if (index == 7) return tileSineAmplitude(tileUv, pixelY);
  if (index == 8) return tileSineFrequency(tileUv, pixelY);
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
// 2. POWER.  [done — tiles 02, 03, 04 at exponents 0.5, 1.0, 2.0]
//    Bias. Above 1.0 pushes values toward 0 (slow start, fast finish); below
//    1.0 does the opposite, and pow(x, 0.5) is sqrt(x). The knob to reach for
//    when something "ramps up too fast" or "hangs around too long".
//
//    Written as one tilePow() with the exponent as an argument, because this
//    is one function with a dial rather than three functions. Add pow(x, 5.0)
//    by adding one dispatch line — no new function needed. The exponent-1.0
//    tile is deliberately a duplicate of the linear one: "no bias" needs a
//    picture too, sitting between the two biased ones.
//
//    The first attempt at this was a tilePow2() with the exponent hard-coded,
//    and it went wrong twice in a way worth remembering: the exponent was
//    tileUv.y rather than a constant, which quietly stopped it being a
//    function of x at all, and then the name said 2 while the body said 0.5.
//    Both disappear once the varying part is a parameter with a name.
//
// 3. STEP AND CLAMP.  y = step(0.5, x), and y = clamp(x * 2.0 - 0.5, 0.0, 1.0)
//    The hard cut, and the flattened ramp. Worth drawing once so the staircase
//    edges of step() are a picture rather than a warning.
//
// 4. SINE.  [done — tiles 05, 06, 07: still, phase, amplitude]
//    The 0.5 + 0.5 * pattern you have written many times, finally graphed, and
//    now pulled out into sin01() because it is the reusable half of the idea.
//    One full period across the tile, because TWO_PI is one whole turn.
//
//    Half a period, sin(x * PI), is worth knowing as its own trick: over the
//    range 0..PI sine never goes negative, so it lands in 0..1 with no
//    remapping at all. That is the arch tile 07 pulses. Reach for a full
//    period when you want a wave, the arch when you want a single hump.
//
//    The general lesson is about RANGE. sin swings -1..1 and a tile shows
//    0..1, so more than half the answer is off-screen unless you remap it.
//    Seen once without the remap: the second half of the wave simply left the
//    tile and the gradient clamped to flat black. Not broken, out of frame —
//    a reflex worth building for every function whose output is not already
//    0..1.
//
// 4b. SINE, THE THIRD KNOB: FREQUENCY.  [done — tile 08]
//    float humps = mix(0.0, 2.0, sin01(iTime));
//    y = sin01(x * TWO_PI * humps)
//
//    The trap is that sin(x * iTime) looks reasonable and is wrong: iTime grows
//    forever, so the humps get denser without limit until the tile is a grey
//    blur. mix() between two fixed values keeps it bounded. Worth writing the
//    broken version once and watching it for ten seconds.
//
//    Two things this tile taught that were not about frequency at all. Zero
//    humps is a flat line at 0.5, not a bug — "no wave" is a wave with nothing
//    left in it. And it is the first tile steep enough to break the graph line
//    into dashes, which turned plot()'s vertical-measurement note from a
//    footnote into something you can see. Numbers and the fix are in the
//    tile's comment.
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
