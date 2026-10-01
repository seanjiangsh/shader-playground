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
//   2. the tile border       so the empty tiles are still visible
//   3. the graph line        mix(so far, lineColor, lineCoverage)
//
// The line goes LAST, on top of the border, because a graph can run right
// along the edge of its tile: step is 0 or 1, so its whole line lives on the
// frame. With the border on top, tile 01 showed no line at all. Painting
// order is a decision about what matters most, and here the graph wins.
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
// Everything here is converted to SCREEN PIXELS first and kept there, which is
// why the ramp is a bare `0.5 + band` with nothing to divide by: once the
// numbers are in pixels, "one pixel wide" is literally 1.0.
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
// * MEASURING THE WIDTH THE RIGHT WAY — why plot() takes TWO y values.
//
// abs(tileUv.y - y) measures straight UP, not perpendicular to the curve. On a
// flat stretch those are the same thing. On a steep one they are not, and the
// gap gets bad fast: the line first looks thinner than asked for, then stops
// being a line at all and breaks into a row of dashes.
//
//     measured UP                    measured PERPENDICULAR
//                                            /
//        |  /                               /|
//        | /   the band is LINE_PIXELS     / |   the band is LINE_PIXELS
//        |/    tall, so a steep curve     /  |   wide whichever way the
//       /|     only gets a thin sliver   /   |   curve happens to lean
//      / |     of it                    /
//
// Why dashes and not just a thin line: the band only covers LINE_PIXELS of
// height per column, but a steep curve climbs more than that between one
// column and the next, so each column's little dash sits above the previous
// one with a gap in between. Tile 10 at two humps climbs 4.2 pixels per column
// against a 2 pixel band, which is exactly what you see.
//
// THE CORRECTION is one multiply. A right triangle with a run of 1 and a rise
// of `slope` has a hypotenuse of sqrt(1 + slope*slope), and that is the factor
// between measuring up and measuring across:
//
//       perpendicular distance = vertical distance / sqrt(1 + slope*slope)
//
//   flat,  slope 0   ->  sqrt(1)    = 1.0    no change at all
//   steep, slope 4   ->  sqrt(17)   = 4.1    the vertical band must be 4x
//                                            taller to stay 1x wide
//
// GETTING THE SLOPE without any calculus: ask the tile's own function twice, a
// single pixel apart, and take rise over run. That is why every tile now
// passes `y` and `yNext`, and why the formula for each tile lives in its own
// little f...() function — evaluating the same formula at two places is only
// safe if there is exactly ONE copy of it to keep in step.
//
// The run is one screen pixel by construction, so the slope is just the rise,
// expressed in screen pixels. Two other ways to get it, for the record:
// raising LINE_PIXELS until the dashes overlap (works, but fattens the flat
// parts too — the wrong lever), and fwidth(), which asks the GPU directly.
// fwidth is one line and no second sample, but it needs the
// OES_standard_derivatives extension: available on essentially every device in
// practice (99.97% on web3dsurvey.com, 97% on caniuse) but off by default in
// WebGL 1, so switching it on means an engine change and a matching line in
// scripts/check-shaders.mjs. The finite difference needs neither, and doing it
// by hand once is what makes fwidth make sense later.
float plot(in vec2 tileUv, in vec2 tilePixel, in float y, in float yNext) {
  // The rise between the two samples, in SCREEN pixels. Both halves have to be
  // in the same units or the triangle is wrong — this is the units trap the
  // whole file keeps coming back to. The run is 1 screen pixel by
  // construction, because that is the step the tile took.
  float slope = (yNext - y) / tilePixel.y;
  float widen = sqrt(1.0 + slope * slope);

  // DON'T DRAW ACROSS A JUMP. A cliff looks like an enormous slope, so widen
  // grows enormous with it and the band ends up tall enough to paint a vertical
  // line joining the two sides of the gap — see tile 11, where fract falls off
  // its tooth. A line plotter would draw that connector, because it joins the
  // samples it was given. We refuse: fract has no value at the jump, so there
  // is nothing there to plot, and leaving the gap says so.
  //
  //     drawn (a plotter's view)        left out (ours)
  //
  //       /|  /|  /|                      /   /   /
  //      / | / | / |                     /   /   /
  //     /  |/  |/  |                    /   /   /
  //
  // 20 is not arbitrary, and the first guess at it was wrong twice over, which
  // is the part worth keeping. Measured across every tile in the gallery, the
  // steepest HONEST slope is pow(x, 0.5) at its left edge, at 8.9 pixels per
  // pixel, while fract's cliff reads 118. A cap of 8 — the obvious first
  // number — would have clipped tile 04 without anyone noticing. And CAPPING
  // widen rather than refusing outright does not remove the connector, it only
  // shortens it: at a cap of 20 the column still lights 21 pixels instead of
  // 105. Two plausible ideas, both wrong, both cheap to check by measuring.
  //
  // Anything from roughly 10 to 100 separates an honest slope from a cliff, so
  // 20 sits with room on both sides.
  if (abs(slope) > 20.0) return 0.0;

  // Vertical distance to the curve, in screen pixels, then divided by widen to
  // turn it into the perpendicular distance.
  float distPixels = abs(tileUv.y - y) / tilePixel.y;
  float perpPixels = distPixels / widen;

  // Now everything is in pixels: subtract half the line width, and the ramp is
  // one pixel wide with nothing left to convert.
  float band = perpPixels - 0.5 * LINE_PIXELS;
  return 1.0 - clamp(0.5 + band, 0.0, 1.0);
}

// * TILE BORDER — a thin separator so empty tiles still read as tiles.
// tileUv is 0..1 inside the tile, so min(tileUv, 1 - tileUv) is the distance
// to the nearest edge on each axis, and the smaller of the two is the distance
// to the nearest edge at all. Same coverage ramp as everything else.
//
// It lives up here, before drawGraph, because drawGraph now paints it: the
// border has to go on BETWEEN the gradient and the line, and only drawGraph
// has both in hand. GLSL needs a function written above wherever it is used.
float tileBorder(in vec2 tileUv, in vec2 tilePixel) {
  vec2 toEdge = min(tileUv, 1.0 - tileUv) / tilePixel;   // in screen pixels
  float dist = min(toEdge.x, toEdge.y) - BORDER_PIXELS;
  return 1.0 - clamp(0.5 + dist, 0.0, 1.0);
}

// * PAINT ONE GRAPH — the body every tile shares.
//
// Hand it the two y values and it does the rest, in the three layers listed
// at the top of the file: the gradient, then the border, then the line on
// top of both. The gradient only ever uses `y`; `yNext` exists purely so
// plot() can work out how steep the curve is here.
vec3 drawGraph(in vec2 tileUv, in vec2 tilePixel, in float y, in float yNext) {
  vec3 color = mix(lowColor, highColor, y);                         // 1. gradient
  color = mix(color, borderColor, tileBorder(tileUv, tilePixel));   // 2. border
  float lineCoverage = plot(tileUv, tilePixel, y, yNext);
  return mix(color, lineColor, lineCoverage);                       // 3. line, last
}

// * THE SHAPE FUNCTIONS — one per tile, x in and y out, and nothing else.
//
// These exist because each formula now has to be evaluated TWICE, at x and at
// x one pixel to the right. Writing it out twice inside the tile would work
// and would be a trap: change one copy, forget the other, and the line's width
// silently goes wrong in a way no compiler can catch. One named function, two
// calls, no way to drift.
//
// They also read as a list of the gallery's contents, which is a nice
// side-effect of pulling them out.
float fLinear(in float x)                     { return x; }
float fSmoothstep(in float x)                 { return smoothstep(0.05, 0.95, x); }
float fStep(in float x)                       { return step(0.5, x); }
float fPow(in float x, in float exponent)     { return pow(x, exponent); }
float fSine(in float x)                       { return sin01(x * TWO_PI); }
float fSinePhase(in float x)                  { return sin01(x * TWO_PI + iTime * WAVE_SPEED); }
float fSineAmplitude(in float x)              { return sin(x * PI) * sin01(iTime * PULSE_SPEED); }
float fSineFrequency(in float x) {
  float humps = mix(0.0, 2.0, sin01(iTime));
  return sin01(x * TWO_PI * humps);
}
float fFract(in float x) { return fract(x * 3.0); }

// mod's second argument is the WRAP POINT, so it gets a name instead of being
// a bare 2.0 in the middle of a line. Dividing by that same number afterwards
// is what squeezes the result back into 0..1 — and that division turns out to
// matter far more than it looks. Tile 12 has the whole story.
float fMod(in float x) {
  float stretch = 5.0;   // how far x is stretched before any wrapping happens
  float wrapAt  = 2.0;   // the modulus: the count folds back to 0 here
  return mod(x * stretch, wrapAt) / wrapAt;
}

// Teeth that shrink as they march to the right: a repeat MULTIPLIED by a fade.
// Three named steps rather than one dense line, because the whole idea of the
// tile is that there ARE two separate things being multiplied.
float fSawShrink(in float x) {
  float teeth    = 4.0;               // how many teeth fit across the tile
  float tooth    = fract(x * teeth);  // 0..1, the identical ramp every time
  float envelope = 1.0 - x;           // 1 at the left, fading to 0 at the right
  return tooth * envelope;
}
// float fSawShrink(in float x) { return fract(x * 4.0) * exp(-3.0 * x); }  // decay instead of a straight fade — tile 13

float fAbs(in float x)                   { return abs(x * 2.0 - 1.0); }        // the V — tile 14
float fTent(in float x)                  { return 1.0 - fAbs(x); }             // the V upside down — tile 15
float fAbsShift(in float x)              { return abs(x * 2.0 - 0.6); }        // the crease moved left — tile 16
// float fAbsShift(in float x) { return abs(x - 0.3) / 0.7; }  // the same crease, kept inside 0..1 — tile 16

float fMin(in float x)                   { return min(x, 1.0 - x); }           // the lower of two lines — tile 17
float fMax(in float x)                   { return max(x, 1.0 - x); }           // the higher of two lines — tile 18
float fMinMaxMix(in float x, in float t) { return mix(fMin(x), fMax(x), t); }  // tent at t = 0, V at t = 1 — tiles 19, 20

// * TILE 00 — LINEAR, y = x.
//
// The identity function, and the one to start from because there is nothing to
// misread: the value rises evenly from 0 on the left to 1 on the right, so the
// gradient is even and the graph is the diagonal. Every other tile in the
// gallery is a comparison against this one.
vec3 tileLinear(in vec2 tileUv, in vec2 tilePixel) {
  float x = tileUv.x;
  return drawGraph(tileUv, tilePixel, fLinear(x), fLinear(x + tilePixel.x));
}

// * TILE 01 — STEP, the hard cut.
//
// step(edge, x) asks one yes-or-no question: is x past the edge?
//
//     x             0 ......... 0.5 ......... 1
//     step(0.5, x)  0 0 0 0 0 0  1 1 1 1 1 1 1
//                   no ........  yes .........
//
// 0 before the edge, 1 from the edge on, nothing in between. The edge comes
// FIRST and x second, which is easy to get backwards; step(x, 0.5) asks the
// opposite question and gives the mirror image.
//
// It sits next to the linear tile on purpose. Tile 00 goes from 0 to 1 as
// gently as possible; this one does the same trip as suddenly as possible,
// and smoothstep (tile 03) is the whole range in between. In fact smoothstep
// with its two edges squeezed together IS a step: smoothstep(0.5, 0.5001, x)
// is indistinguishable from this tile.
//
// THE GRADIENT is the sharpest in the gallery: pure black on the left, pure
// white on the right, a hard seam at 0.5. It is the only function here with
// no values in between, and it is also every hard edge you have drawn so far
// in one line. A circle with no anti-aliasing is step(radius, distance).
//
// THE JUMP is a cliff, like every tooth of tile 11, so plot()'s guard leaves
// a gap there rather than painting a vertical connector.
//
// * WHERE THE LINE LIVES — the tile that changed the layer order.
//
// y is only ever 0 or 1, so the whole line sits ON the bottom and top edges
// of the tile. When the border was painted over everything, that hid it
// completely: measured, 0 visible line pixels. Nothing was wrong with the
// maths; the frame was simply drawn over the graph.
//
// Two honest fixes were on the table. Squeezing this tile's answer into
// 0.1..0.9 would have brought the line back, but then y would no longer be
// exactly step. Drawing the border UNDER the line fixes every tile at once
// and keeps every function honest, so that is what drawGraph does now (see
// LAYERS at the top of the file). Measured after: the line shows in 179 of
// 180 columns.
//
// It is only half as thick as elsewhere, 1 pixel instead of 2. The line is
// centred on y = 0, so half of it is below the tile, and that half belongs
// to the tile underneath. Same reason the tips of tiles 14 and 15 look thin.
vec3 tileStep(in vec2 tileUv, in vec2 tilePixel) {
  float x = tileUv.x;
  return drawGraph(tileUv, tilePixel, fStep(x), fStep(x + tilePixel.x));
}

// * TILE 03 — SMOOTHSTEP, the ease.
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
// the corners. Those runs sit right on the tile boundary, at the bottom-left
// and top-right, which is why the line looks thinner there: half of it is
// outside the tile. (They used to be hidden under the border too, until tile
// 01 moved the border underneath the line.) Not wrong, just worth knowing you chose it. smoothstep(0.0, 1.0,
// x) gives the plain version with no flat runs.
//
// WATCH THE LINE WIDTH. This is the first tile steep enough to show the
// limitation noted on plot(): it measures straight up, not perpendicular to
// the curve. The vertical thickness is a constant 2.00 px everywhere — I
// measured it — but the width you actually SEE is that divided by
// sqrt(1 + slope*slope), which at the steepest point is 2 / 1.94 = 1.03 px.
// So the line looks about half as thick through the middle as it does at the
// ends. Nothing is broken; the ruler is just pointing the wrong way.
// (Fixed since: tile 10 made this impossible to ignore, and plot() now
// measures across the curve, so the line no longer thins through the S.)
vec3 tileSmoothstep(in vec2 tileUv, in vec2 tilePixel) {
  float x = tileUv.x;
  return drawGraph(tileUv, tilePixel, fSmoothstep(x), fSmoothstep(x + tilePixel.x));
}

// * TILES 04, 05, 06 — POWER, the bias dial.
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
// Want a fourth? pow(x, 5.0) is one more line in drawTile and no new
// function, which is the payoff of the exponent being a parameter. The first
// attempt at this family was a tilePow2() with the exponent written inside,
// and it went wrong twice: the name said 2 while the body said 0.5, and for a
// while the exponent was tileUv.y, which quietly stopped it being a function
// of x at all. Both problems disappear once the part that varies is a
// parameter with a name.
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
// artifact as on smoothstep, more obvious here. (Fixed since, in plot(),
// after tile 10.)
vec3 tilePow(in vec2 tileUv, in vec2 tilePixel, in float exponent) {
  float x = tileUv.x;
  return drawGraph(tileUv, tilePixel, fPow(x, exponent), fPow(x + tilePixel.x, exponent));
}

// * TILES 07 TO 10 — SINE, and the first things in the gallery that MOVE.
//
// The idea that unlocks all of this: everything inside sin() is an ANGLE in
// radians, and iTime is SECONDS. So any number multiplying iTime is radians
// per second, and one full cycle takes TWO_PI divided by it. WAVE_SPEED = 2.0
// is a cycle every 3.1 seconds. For N cycles per second, use N * TWO_PI.
//
// There are exactly three things you can animate in a wave, and they feel
// completely different, so each one gets a tile of its own.
//
//   PHASE      add to the angle       the wave slides sideways    <- tile 08
//   AMPLITUDE  multiply the result    the wave grows and shrinks  <- tile 09
//   FREQUENCY  multiply x             more or fewer humps         <- tile 10
//
// Tile 07 is the still reference, and it earns its slot: motion is hard to
// judge with nothing beside it holding still.
//
// A FULL WAVE OR AN ARCH. x * TWO_PI is one whole turn across the tile, so
// you get a full wave, and it needs sin01 to fit. x * PI is half a turn, and
// over 0..PI sine never goes negative, so the arch lands in 0..1 with no
// remapping at all. Reach for the full turn when you want a wave, the arch
// when you want a single hump. Tile 09 uses the arch.
//
// RANGE, the reflex this family teaches. sin swings -1..1 and a tile shows
// 0..1, so more than half the answer is off-screen unless you remap it. Seen
// once without the remap: the second half of the wave simply left the tile
// and the gradient sat at flat black. Not broken, out of frame. Ask "does
// this still fit 0..1?" of every function whose output is not already there;
// tiles 12 and 16 both come back to it.

vec3 tileSine(in vec2 tileUv, in vec2 tilePixel) {
  float x = tileUv.x;
  return drawGraph(tileUv, tilePixel, fSine(x), fSine(x + tilePixel.x));
}

// * TILE 08 — PHASE, the wave slides sideways.
//
// Adding to the angle slides the whole wave along x — add and it
// travels left, subtract and it travels right. Nothing about the wave's SHAPE
// changes, which is exactly what makes it read as movement rather than as
// distortion.
vec3 tileSinePhase(in vec2 tileUv, in vec2 tilePixel) {
  float x = tileUv.x;
  return drawGraph(tileUv, tilePixel, fSinePhase(x), fSinePhase(x + tilePixel.x));
}

// * TILE 09 — AMPLITUDE, the wave grows and shrinks.
//
// Multiplying the result scales the wave's height.
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
vec3 tileSineAmplitude(in vec2 tileUv, in vec2 tilePixel) {
  float x = tileUv.x;
  return drawGraph(tileUv, tilePixel, fSineAmplitude(x), fSineAmplitude(x + tilePixel.x));
}

// * TILE 10 — FREQUENCY, the third knob.
//
// Multiplying x decides how many humps fit across the tile.
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
// Unlike tile 08, this does not TRAVEL, it STRETCHES. The angle at any point
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
// which means growing the band by sqrt(1 + slope*slope). plot() does that
// now, and this tile is the reason it does: see MEASURING THE WIDTH THE RIGHT
// WAY, above plot().
vec3 tileSineFrequency(in vec2 tileUv, in vec2 tilePixel) {
  float x = tileUv.x;
  return drawGraph(tileUv, tilePixel, fSineFrequency(x), fSineFrequency(x + tilePixel.x));
}

// * TILE 11 — FRACT, the sawtooth, and the first BROKEN curve in the gallery.
//
// fract() keeps the fractional part and throws the whole number away, so as x
// climbs it ramps 0 up to 1, drops instantly back to 0, and does it again.
// Multiplying by 3.0 is the tile-count rule from scene 01: x spans 1.0, so
// multiplying by 3 makes it cross three integers, and you get three teeth.
//
//   y  1 |   /|   /|   /|
//        |  / |  / |  / |      each tooth ramps up...
//        | /  | /  | /  |
//      0 |/   |/   |/   |      ...then falls off a cliff
//        +---------------
//        0              1
//
// The gradient says it just as loudly: three black-to-white sweeps with a hard
// seam between them. That seam is exactly the one you met in scene 01 when
// fract() first tiled the screen — same function, now drawn as a graph instead
// of used as a coordinate.
//
// mod(x * 3.0, 1.0) gives an identical picture here. In GLSL the two really
// are the same thing, because mod is defined as x - y * floor(x / y) and floor
// rounds DOWN. The difference only bites in languages where % truncates toward
// zero instead, which makes it negative for negative inputs.
//
// WHAT THE SLOPE FIX DOES WITH A CLIFF, which is worth understanding because
// it is the first place the new plot() meets something it was not designed for.
//
// At a tooth, the two samples land either side of the drop, so the "rise"
// between them is nearly a whole tile height in one pixel. Measured: the slope
// reaches -118 screen pixels per pixel, so widen is sqrt(1 + 118*118) = 118,
// and the band becomes 118 times taller. That is enough to cover the entire
// height of the tile in that one column, which paints a one-pixel VERTICAL
// line joining the top of one tooth to the bottom of the next. Three teeth,
// three connectors, and you can count them in the picture.
//
// So what does the tile draw? Three separate ramps with a clean gap at each
// tooth. plot() refuses to draw when the slope is absurd, which is the choice
// made here: a line plotter would join its samples and paint the vertical, but
// fract has no value at the jump, so there is nothing there to plot. Both are
// defensible; this one says out loud that the function is broken there.
//
// Flipping it back is deleting one line in plot(). Worth doing once to see the
// difference — the connected version reads as a sawtooth, the gapped version
// reads as what the maths actually is.
//
// The threshold has its own story, recorded beside the line in plot(): the
// first guess at it was wrong twice, and measuring rather than reasoning is
// what caught both. That is the part of this tile most likely to be useful
// somewhere else.
vec3 tileFract(in vec2 tileUv, in vec2 tilePixel) {
  float x = tileUv.x;
  return drawGraph(tileUv, tilePixel, fFract(x), fFract(x + tilePixel.x));
}

// * TILE 12 — MOD, which is the same picture as tile 11 ON PURPOSE.
//
// It is not a mistake and it is not nearly the same, it is exactly the same.
// GLSL defines mod as
//
//     mod(x, y) = x - y * floor(x / y)
//
// so with y = 1.0 that is x - floor(x), and fract is DEFINED as x - floor(x).
// Same two operations in the same order, so the same bits come out. Checked
// over 200001 samples across the tile: the largest difference is exactly 0.0,
// and the arrays are bit-identical.
//
// So why keep the tile? Because "these two are the same" is a fact worth being
// able to see rather than take on trust, the same way tile 05 draws pow(x, 1.0)
// on top of the linear tile to give "no bias" a picture. Two slots spent
// proving two things are identical is cheap next to being unsure.
//
// WHERE THEY DO PART COMPANY, which is the part to remember:
//
//   1. THE MODULUS IS A PARAMETER — but a smaller one than it first looks.
//      fract is mod with the wrap point hard-wired to 1. The tile as written
//      wraps at 2 and then divides by 2 to get back inside 0..1, and those two
//      steps cancel each other out:
//
//          mod(a, m) / m   ==   fract(a / m)        exactly, for any m
//
//      Checked over 200001 samples at several moduli: largest difference 0.0,
//      or 1.7e-16 when m divides awkwardly, which is float rounding rather
//      than a different answer. (Writing * 0.5 instead of / 2.0 changes
//      nothing either — measured difference exactly 0.0.)
//
//      So this tile is fract(x * 2.5) in a disguise: stretched by 5, wrapped
//      at 2, is two and a half teeth. That is why it looks like tile 11 with
//      the tooth count changed. It IS tile 11 with the tooth count changed.
//
//      The modulus only earns its keep when you DON'T divide it back out.
//      Delete the / wrapAt and the result runs 0..2, so the top half of every
//      tooth is above the roof of the tile: the graph line disappears for half
//      of each tooth and the gradient sits at flat white there, because mix()
//      does not clamp. Worth doing for ten seconds — a value quietly escaping
//      its 0..1 box is a bug you want to have seen once on purpose.
//
//      Said plainly: mod's second argument changes the SCALE of the output,
//      not the SHAPE of it. For the shape, x is the dial. And for a shape
//      fract genuinely cannot make on its own, see tile 13.
//
//   2. OTHER LANGUAGES DISAGREE. GLSL's mod uses floor, which rounds DOWN, so
//      it always returns something with the sign of y. C, C++, Java and
//      JavaScript's % truncates toward ZERO instead, so it keeps the sign of x:
//
//                       GLSL mod(x, 1.0)      C / JS  x % 1
//          x = -0.25          0.75               -0.25
//          x = -1.25          0.75               -0.25
//          x =  0.25          0.25                0.25
//
//      They agree for positive x and disagree for negative, which is exactly
//      the case that slips through testing. Worth knowing before porting a
//      shader to or from JavaScript, and it is why ports of noise functions
//      sometimes come out subtly wrong.
vec3 tileFMod(in vec2 tileUv, in vec2 tilePixel) {
  float x = tileUv.x;
  return drawGraph(tileUv, tilePixel, fMod(x), fMod(x + tilePixel.x));
}

// * TILE 13 — AN ENVELOPE: teeth that shrink as they go.
//
// The question: how do you get a sawtooth whose teeth get smaller and smaller
// towards the right? The instinct is to hunt for a parameter of fract or mod
// that does it, and there isn't one. Neither function has a "getting quieter"
// dial, because neither of them knows where it is — fract(x * 4.0) hands back
// the identical ramp every time round, by definition.
//
// The move is not to change the repeat at all. Keep it, and multiply it by a
// SECOND function whose whole job is to fade:
//
//     y  =  tooth(x)   *   envelope(x)
//           \_______/      \_________/
//            the shape       how loud it is here
//
//   tooth    = fract(x * 4.0)      1 |/|/|/|/|    the same ramp, four times
//                                  0 +---------
//
//   envelope = 1.0 - x             1 |--__        a plain falling ramp
//                                  0 +-----__
//
//   the product                    1 |/|          tall on the left,
//                                  0 +--|_|.-..   barely there on the right
//
// This is the same move as tile 09, where sin(x * PI) was multiplied by a
// pulsing amplitude. The only difference is what drives the multiplier: tile
// 07 keyed it to iTime, so the whole graph breathes; this one keys it to x, so
// the fade happens ACROSS the tile instead of over time. Same maths, and in
// audio and animation it goes by the same name either way — an envelope.
//
// Measured peak heights, left to right: 0.744, 0.497, 0.250, 0.062. Evenly
// spaced, because the envelope falls evenly. Swap in the commented exp()
// variant beside fSawShrink and they become 0.471, 0.222, 0.105 — each tooth
// roughly half the one before, which is what decay looks like in the real
// world: a plucked string, a bouncing ball, a dying echo.
//
// Once you have seen an envelope, it turns up everywhere: a texture fading
// out with distance, a wobble that settles down, a ripple dying away from
// where it was dropped. A repeat on its own has no memory of where it is;
// the envelope is what gives it one.
//
// * TWO THINGS THE PICTURE SHOWS THAT THE FORMULA DOES NOT
//
// The ramps are not quite straight. A straight ramp times a straight fade is a
// quadratic, so each tooth leans over a little. Harmless here, and worth
// recognising as a general fact: multiply two shapes together and you get a
// third one that is neither of them.
//
// The gaps at the cliffs close up as the teeth shrink, and that is the guard
// inside plot() showing its seams. The guard drops the line when the slope
// passes 20, and a cliff's slope is essentially its height measured in screen
// pixels — so once a tooth is short enough its cliff falls UNDER the threshold
// and gets drawn as a vertical connector, while the tall ones on the left stay
// gapped. It even depends on the window size, because pixels are the unit:
//
//     window 600 tall  ->  cliff slopes 88, 59, 30    all three gapped
//     window 400 tall  ->  cliff slopes 59, 39, 20    the third one joins up
//
// Resize the window slowly and you can watch the third gap heal itself. The 20
// was only ever a number that happened to suit the curves already in the
// gallery. The honest version derives it from the steepest slope a tile MEANS
// to draw, so that "absurd" is defined by the picture rather than by a
// constant — parked here until some tile needs it badly enough to be worth the
// extra machinery.
vec3 tileSawShrink(in vec2 tileUv, in vec2 tilePixel) {
  float x = tileUv.x;
  return drawGraph(tileUv, tilePixel, fSawShrink(x), fSawShrink(x + tilePixel.x));
}

// * TILE 14 — ABS, the fold.
//
// abs() throws the minus sign away, and that is all it does. On its own that
// sounds too small to be interesting. The trick is to make half the numbers
// negative FIRST, so there is something to throw away:
//
//     x               0 ........ 0.5 ........ 1
//     x * 2.0         0 ........  1  ........ 2     stretch to twice the width
//           - 1.0    -1 ........  0  ........ 1     slide so the middle is 0
//     abs(...)        1 ........  0  ........ 1     fold the left half up
//
// Picture the graph of x * 2.0 - 1.0 as a straight diagonal that dips below
// the floor on the left. abs() takes the part under the floor and flips it
// up, like folding a sheet of paper along the line y = 0:
//
//     before abs                        after abs
//
//     1 |          /                    1 |\         /
//       |        /                        |  \     /
//     0 |------/------                  0 |----\ /----
//       |    /                                 ^ the crease, at x = 0.5
//    -1 |  /
//
// The gradient says it too: white at both edges, black down the middle, and
// symmetric, because the two halves are now mirror copies of each other.
//
// * YOU HAVE ALREADY USED THIS
//
// sdBox in scene 02 starts with abs(pos). Same fold, one dimension up: it
// folds the plane along both axes so the box only has to be worked out for
// one quarter, and the other three quarters are mirror images for free. A
// box is four identical corners, and abs is how you get four for the price
// of one.
//
// * THE CREASE
//
// The bottom of the V is a sharp point, not a curve. The slope jumps from
// -2 straight to +2 with nothing in between. That is the fingerprint of abs,
// and of min and max too: they make hard creases wherever they switch. It is
// exactly what smin in scene 02 exists to round off.
//
// The line survives the crease without help. In screen pixels the V's slope
// is only about 1.3 on a 900 x 600 window (2 up for every 1 across, squashed
// by the tile being wider than it is tall), a long way under the guard of
// 20, so plot() draws both arms and the join normally.
//
// Tiles 15 and 16 are two small variations on this one: flip it over, and
// move the crease.
vec3 tileAbs(in vec2 tileUv, in vec2 tilePixel) {
  float x = tileUv.x;
  return drawGraph(tileUv, tilePixel, fAbs(x), fAbs(x + tilePixel.x));
}

// * TILE 15 — THE TENT, which is the V turned upside down.
//
// 1.0 - y is the flip you have met before: 0 becomes 1, 1 becomes 0, and
// everything between swaps ends. Do it to the V and the crease that was at
// the bottom is now a peak at the top:
//
//     fAbs  (tile 14)          fTent = 1.0 - fAbs
//
//     1 |\        /            1 |      /\       <- peak
//       |  \    /                |    /    \     (the old crease)
//     0 |____\/____            0 |__/________\__
//
// Notice fTent is written as 1.0 - fAbs(x), not by typing the formula out
// again. That is the same "one named function, no copies to drift" rule as
// the reason these functions exist at all: fix fAbs and the tent follows.
//
// The gradient flips too, black at both edges and white down the middle. A
// tent like this is the everyday way to say "strongest at the centre, fading
// evenly to nothing at both sides", and you will meet it again as a falloff.
//
// ONE THING THE PICTURE SHOWS: the tips of both the V and the tent land
// exactly on the edge of the tile, at y = 0 and y = 1. The line is centred
// on the curve, so half its width at the tip sits outside the tile and gets
// cut off, which is why the tips look thin. The maths is fine, the point is
// just drawn on the frame. (The border used to paint over the other half as
// well, until tile 01 moved it underneath the line.) Scale by 0.9 and add
// 0.05 if you ever want the tips to sit clear of the edges.
vec3 tileTent(in vec2 tileUv, in vec2 tilePixel) {
  float x = tileUv.x;
  return drawGraph(tileUv, tilePixel, fTent(x), fTent(x + tilePixel.x));
}

// * TILE 16 — MOVING THE CREASE, and a value escaping its box.
//
// The crease is always where the inside of the abs() is zero, because that
// is the one place where there is no sign to throw away. So to move it, solve
// "inside = 0" for x:
//
//     x * 2.0 - 1.0 = 0    ->   x = 0.5     tile 14, crease in the middle
//     x * 2.0 - 0.6 = 0    ->   x = 0.3     this tile, crease left of centre
//
// The catch is the right arm. It still climbs at the same steepness, 2 up for
// every 1 across, but it now starts from x = 0.3 instead of 0.5, so it has
// further to go. It reaches 1.0 at x = 0.8 and carries on to 1.4 by the right
// edge. From x = 0.8 on, the value is above the roof of the tile:
//
//     y 1.4 |                    .    <- where the arm really ends
//       1.0 +----------------/--------  the roof of the tile
//           |\            /   |
//           |  \        /     |   no line past here, flat white
//         0 |____\____/_______|__
//           0    0.3        0.8   1
//
// Measured: the line is drawn in 145 of the 180 columns, and the last fifth
// of the tile is flat white, because mix() does not stop at 1 and the screen
// clamps whatever comes out. Same lesson as sin before it was remapped, and
// as the un-divided mod on tile 12: every time you move or stretch a
// function, check that its answer still fits 0..1.
//
// The fix is to scale by the LONGER arm, so both ends land at 1 or below:
//
//     abs(x - 0.3) / 0.7        0.7 = the distance from the crease to x = 1
//
// That is the commented alternative beside fAbsShift. Swap it in and the
// right arm lands exactly on 1.0 at the right edge, while the left arm, being
// shorter, only reaches 0.3 / 0.7 = 0.43 on the left.
vec3 tileAbsShift(in vec2 tileUv, in vec2 tilePixel) {
  float x = tileUv.x;
  return drawGraph(tileUv, tilePixel, fAbsShift(x), fAbsShift(x + tilePixel.x));
}

// * TILE 17 — MIN, which picks the lower of two answers.
//
// min(a, b) looks at two numbers and hands back whichever is smaller. Here
// the two numbers are two straight lines, one climbing and one falling:
//
//     a = x          0 at the left, 1 at the right
//     b = 1.0 - x    1 at the left, 0 at the right
//
// Draw both, then keep only the LOWER one at each x:
//
//     1 |\            /|          1 |              |
//       |   \      /   |            |              |
//   0.5 |      \/      |        0.5 |      /\      |   <- the crossing,
//       |   /      \   |            |   /      \   |      at x = 0.5
//     0 |/____________\|          0 |/____________\|
//        b falls, a climbs            min keeps the lower
//
// On the left, a is the lower one, so the graph follows a upward. On the
// right, b is lower, so it follows b downward. The switch happens where the
// two lines cross, x = 0.5, and that switch is the crease at the top.
//
// So the shape is a TENT, and it only reaches half height. The peak is where
// the two lines cross, and they cross at 0.5, so nothing can go higher: the
// gradient never gets past mid grey. (A correction: the hint for this tile
// said it would be the tent upside down. It is not. It is the right way up,
// at half the height. The render settled it.)
//
// * TWO FORMULAS, ONE PICTURE
//
// Put this tile next to tile 15 and they are the same shape, one squashed to
// half height. That is not a coincidence, it is exact:
//
//     min(x, 1.0 - x)  ==  0.5 * fTent(x)       largest difference 2.8e-17
//
// The reason is a small identity worth keeping in your pocket, because it
// says min is made of abs:
//
//     min(a, b)  ==  (a + b) / 2  -  abs(a - b) / 2
//
// Read it in plain English: start halfway between the two numbers, then step
// down by half the gap between them. You land exactly on the smaller one.
// Checked on a million random pairs: largest difference 8.9e-16, which is
// rounding. With a = x and b = 1.0 - x the halfway point is always 0.5, and
// the gap is abs(2x - 1), which is fAbs. That is why the min crease and the
// abs crease look alike: they are the same crease.
//
// * WHY THIS MATTERS: IT IS SCENE 02'S UNION
//
// In scene 02, min(circle, box) joined two shapes into one. Each distance
// field says "how far am I from this shape", and min keeps the nearer, so a
// point belongs to whichever shape it is closer to. That is this tile, with
// the two lines standing in for the two shapes. The crease where the winner
// changes hands is the same crease smin rounds off in scene 02: this is the
// one-dimensional picture of why smin exists.
vec3 tileMin(in vec2 tileUv, in vec2 tilePixel) {
  float x = tileUv.x;
  return drawGraph(tileUv, tilePixel, fMin(x), fMin(x + tilePixel.x));
}

// * TILE 18 — MAX, the other half of the pair.
//
// Same two lines as tile 17, a = x climbing and b = 1.0 - x falling. This
// time keep the HIGHER one at each x:
//
//     1 |\            /|          1 |\            /|
//       |   \      /   |            |   \      /   |
//   0.5 |      \/      |        0.5 |      \/      |   <- the crossing,
//       |   /      \   |            |              |      now the lowest
//     0 |/____________\|          0 |______________|      point
//        b falls, a climbs            max keeps the higher
//
// On the left, b is the higher one, so the graph follows b downward. On the
// right, a is higher, so it follows a upward. So the shape is a V, and it
// never goes below 0.5, because the lowest max can be is where the two lines
// meet. The gradient shows it: nothing darker than mid grey anywhere.
//
// Same identity as tile 17, with the minus turned into a plus:
//
//     max(a, b)  ==  (a + b) / 2  +  abs(a - b) / 2
//
// Start halfway between the two numbers, then step UP by half the gap, and
// you land on the bigger one. With these two lines that gives
//
//     max(x, 1.0 - x)  ==  0.5 + 0.5 * fAbs(x)      largest difference 1.1e-16
//
// which is tile 14's V, squashed to half height and lifted into the top
// half of the tile.
//
// * MIN AND MAX TOGETHER
//
// Put tiles 17 and 18 side by side and they fit into each other like two
// halves of a mould: one is exactly the room the other leaves. That is also
// exact, and for any two numbers, not just these:
//
//     min(a, b) + max(a, b)  ==  a + b
//
// Between them, min and max just share out a and b: one takes the smaller,
// the other the bigger, and nothing is lost. Here a + b = 1 at every x, so
// fMin(x) + fMax(x) is exactly 1 all the way across.
//
// In scene 02, max was INTERSECTION: max(circle, box) keeps the FARTHER of
// the two distances, so a point only counts as inside when it is inside
// both shapes. Union and intersection are these two tiles, one dimension up.
//
// * THE BUG THIS TILE HAD, worth remembering
//
// The first version sampled the second point as fMax(tilePixel.x) instead of
// fMax(x + tilePixel.x). Without the x, it asked for the value one pixel from
// the tile's LEFT EDGE, the same fixed spot for every pixel, so yNext was
// about 0.994 everywhere. plot() then read a made-up slope as steep as 59:
// the guard hid the line in 118 of the 180 columns, and the columns near the
// edges got smeared green wedges instead.
//
// The clue for next time: the gradient still looked right, because it only
// uses y. When the colours are right and the line is wrong, check the
// second f(...) call first.
vec3 tileMax(in vec2 tileUv, in vec2 tilePixel) {
  float x = tileUv.x;
  return drawGraph(tileUv, tilePixel, fMax(x), fMax(x + tilePixel.x));
}

// * TILE 19 — MIX, exactly halfway between min and max.
//
// min and max SWITCH: at each x they hand back one answer or the other.
// mix(a, b, t) BLENDS instead. t says how far to walk from a toward b:
//
//     t = 0.0   ->  all a
//     t = 0.5   ->  exactly halfway between them
//     t = 1.0   ->  all b
//
// Written out, it is a + (b - a) * t: start at a, and go t of the way to b.
//
// Here a is tile 17's tent, b is tile 18's V, and t is 0.5. What comes out
// is a dead straight line at 0.5, all the way across, and the gradient is
// one flat mid grey. That is not a bug, and tile 18 already told you it
// would happen: min + max is always a + b, and here a + b = x + (1 - x) = 1
// at every x. So halfway between them, (min + max) / 2, is always 0.5.
//
// The picture makes it obvious. The tent and the V are the two halves of the
// same X, the lines x and 1 - x cut at their crossing:
//
//        1 |\            /|   <- max keeps the top half (tile 18)
//          |   \      /   |
//      0.5 |======X=======|   <- halfway between them: flat
//          |   /      \   |
//        0 |/____________\|   <- min keeps the bottom half (tile 17)
//
// At every x, the V is exactly as far above 0.5 as the tent is below it, so
// the point halfway between them never moves off 0.5. The two creases cancel.
//
// The same flat line turned up on tile 10, when the wave had zero humps.
// Different road, same place: "nothing left to show" draws as a flat line in
// the middle of the tile, not as an empty tile.
//
// * WHY t IS A PARAMETER
//
// fMinMaxMix takes the blend amount t as its second input instead of having
// 0.5 written inside it, the same move tilePow made with its exponent. That
// makes this tile just one setting of a dial: fMinMaxMix(x, 0.5). Tile 20
// uses the very same function and only changes where t comes from.
vec3 tileMinMaxMix(in vec2 tileUv, in vec2 tilePixel) {
  float x = tileUv.x;
  float t = 0.5;   // fixed exactly halfway: tile 20 lets it move
  return drawGraph(tileUv, tilePixel, fMinMaxMix(x, t), fMinMaxMix(x + tilePixel.x, t));
}

// * TILE 20 — MORPH, the mix set moving.
//
// Tile 19 with the fixed 0.5 replaced by a t that swings 0..1 and back:
//
//     float t = sin01(iTime * PULSE_SPEED);
//
// Same tool as tile 09's pulse, and the same speed, so put the two tiles
// side by side and they breathe in step. As t sweeps, the tile morphs
// through three shapes you have already met:
//
//     t = 0.0   the tent        (tile 17)
//     t = 0.5   the flat line   (tile 19)
//     t = 1.0   the V           (tile 18)
//
// A NAME CHANGE: this was first called tileMinMaxMixFrequency. Frequency is
// the knob that multiplies x and changes how many humps fit (tile 10).
// Nothing here changes the count; what moves is how far the blend has gone,
// so "morph" says what you see.
//
// * THE CREASE NEVER GOES AWAY
//
// Worked out, the whole family is one formula:
//
//     mix(fMin(x), fMax(x), t)  ==  0.5 + (t - 0.5) * fAbs(x)
//
// checked to 1.1e-16 at five values of t. Read it as "the V from tile 14,
// scaled by (t - 0.5), sitting on a line at 0.5":
//
//     t = 0.0    0.5 - 0.5 * fAbs     the V flipped and squashed: a tent
//     t = 0.25   0.5 - 0.25 * fAbs    a flatter tent
//     t = 0.5    0.5 +   0 * fAbs     no V left at all: the flat line
//     t = 0.75   0.5 + 0.25 * fAbs    a shallow V
//     t = 1.0    0.5 + 0.5 * fAbs     the full V
//
// So the crease is there the whole time. It shrinks to nothing at t = 0.5,
// flips over, and grows back pointing the other way. Mixing two creased
// shapes gives you another creased shape, because mix blends whole curves,
// it does not round off a corner. Rounding a corner is what smin in scene
// 02 is for.
//
// It also answers the question tile 09 raised: multiplying by a changing
// number is amplitude. Here that multiplier, (t - 0.5), goes NEGATIVE for
// half the cycle, and a negative amplitude flips the shape upside down. On
// tile 09 sin01 kept the multiplier in 0..1 for exactly that reason; here
// the flip is the whole point.
vec3 tileMinMaxMorph(in vec2 tileUv, in vec2 tilePixel) {
  float x = tileUv.x;
  float t = sin01(iTime * PULSE_SPEED);   // 0 = tent, 0.5 = flat, 1 = V
  return drawGraph(tileUv, tilePixel, fMinMaxMix(x, t), fMinMaxMix(x + tilePixel.x, t));
}

// * TILE — NOT WRITTEN YET. Copy tileLinear, rename it, change the one line
// that computes y, and add it to drawTile below.
vec3 tileTodo(in vec2 tileUv, in vec2 tilePixel) {
  return mix(todoColor, borderColor, tileBorder(tileUv, tilePixel));   // no graph, so no line to put on top
}

// * DISPATCH — index in, color out.
//
// GLSL ES 1.00 has no function pointers and no arrays of functions, so a
// straight if-chain is the honest way to do this. It costs nothing real: every
// pixel takes exactly one branch, and the branch is the same for every pixel
// in a tile, which is the case GPUs handle best.
//
// Uncomment a line as you write each tile.
vec3 drawTile(in int index, in vec2 tileUv, in vec2 tilePixel) {
  if (index == 0)  return tileLinear(tileUv, tilePixel);
  if (index == 1)  return tileStep(tileUv, tilePixel);
  // index 2: clamp, not written yet
  if (index == 3)  return tileSmoothstep(tileUv, tilePixel);
  if (index == 4)  return tilePow(tileUv, tilePixel, 0.5);
  if (index == 5)  return tilePow(tileUv, tilePixel, 1.0);
  if (index == 6)  return tilePow(tileUv, tilePixel, 2.0);
  if (index == 7)  return tileSine(tileUv, tilePixel);
  if (index == 8)  return tileSinePhase(tileUv, tilePixel);
  if (index == 9)  return tileSineAmplitude(tileUv, tilePixel);
  if (index == 10) return tileSineFrequency(tileUv, tilePixel);
  if (index == 11) return tileFract(tileUv, tilePixel);
  if (index == 12) return tileFMod(tileUv, tilePixel);
  if (index == 13) return tileSawShrink(tileUv, tilePixel);
  if (index == 14) return tileAbs(tileUv, tilePixel);
  if (index == 15) return tileTent(tileUv, tilePixel);
  if (index == 16) return tileAbsShift(tileUv, tilePixel);
  if (index == 17) return tileMin(tileUv, tilePixel);
  if (index == 18) return tileMax(tileUv, tilePixel);
  if (index == 19) return tileMinMaxMix(tileUv, tilePixel);
  if (index == 20) return tileMinMaxMorph(tileUv, tilePixel);
  return tileTodo(tileUv, tilePixel);
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

  // Each tile paints its own border now (inside drawGraph, or in tileTodo),
  // so the line can go on top of it. Nothing left to add here.
  vec3 color = drawTile(index, tileUv, tilePixel);
  fragColor = vec4(color, 1.0);
}

// * EXERCISES — the gallery, roughly in the order The Book of Shaders builds
// them. One tile each. Write the function, add it to drawTile, look at it
// beside the linear one.
// ---------------------------------------------------------------------------
//
// DONE. Everything a tile taught lives in that tile's own comment, so this
// list only says where to look, in gallery order:
//
//   LINEAR                          tile 00
//   STEP                            tile 01
//   SMOOTHSTEP                      tile 03
//   POWER                           tiles 04, 05, 06
//   SINE: still, phase, amplitude   tiles 07, 08, 09
//   SINE: frequency                 tile 10
//   FRACT AND MOD                   tiles 11, 12
//   ENVELOPE                        tile 13
//   ABS, TENT, MOVED CREASE         tiles 14, 15, 16
//   MIN, MAX, MIX, MORPH            tiles 17, 18, 19, 20
//
// STILL TO DO:
//
// CLAMP, tile 02 (its slot is kept next to step).
//    y = clamp(x * 2.0 - 0.5, 0.0, 1.0). A ramp with its ends flattened: the
//    "keep it inside 0..1" reflex written as a function. Step is the jump,
//    clamp is the same trip taken as a slope with flat landings at each end.
//
// THE LAST ROW, tiles 21 to 24, planned:
//    21  PARABOLA              pow(4.0 * x * (1.0 - x), k)    a smooth hump
//    22  EXPONENTIAL IMPULSE   h * exp(1.0 - h), h = k * x    fast hit, slow fade
//    23  GAUSSIAN BELL         exp(-(x - 0.5)^2 / (2 s^2))    the tent, uncreased
//    24  CUBIC BEZIER          a mix of mixes                 built from tile 19
//    More Bezier, or a smoothstep "window", can go in a sixth row: raising
//    TILES_DOWN to 6 adds five slots without moving any existing number.
//
// ANIMATE ONE MORE.  Multiply anything by iTime inside a sin(), or move a
//    smoothstep's edges with it, and watch the curve breathe. The graph is the
//    quickest way to understand an animation you cannot yet picture.
//
// EXTRA CREDIT, once the gallery fills up: label the tiles by drawing a small
// bar at the bottom whose length is the index, or colour the border of the
// tile you are hovering using iMouse.
//
// STUCK? `pnpm test:shaders` will tell you about syntax and type errors without
// you having to hunt for a blank screen in the browser.
