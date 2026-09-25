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
// one with a gap in between. Tile 08 at two humps climbs 4.2 pixels per column
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
  // line joining the two sides of the gap — see tile 09, where fract falls off
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
  // number — would have clipped tile 02 without anyone noticing. And CAPPING
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

// * PAINT ONE GRAPH — the body every tile shares.
//
// Hand it the two y values and it does the rest: colour by the value at this
// pixel, then draw the line on top. The gradient only ever uses `y`; `yNext`
// exists purely so plot() can work out how steep the curve is here.
vec3 drawGraph(in vec2 tileUv, in vec2 tilePixel, in float y, in float yNext) {
  vec3 color = mix(lowColor, highColor, y);
  float lineCoverage = plot(tileUv, tilePixel, y, yNext);
  return mix(color, lineColor, lineCoverage);
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
// matter far more than it looks. Tile 10 has the whole story.
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
// float fSawShrink(in float x) { return fract(x * 4.0) * exp(-3.0 * x); }  // decay instead of a straight fade — tile 11

float fAbs(in float x)      { return abs(x * 2.0 - 1.0); }   // the V — tile 12
float fTent(in float x)     { return 1.0 - fAbs(x); }        // the V upside down — tile 13
float fAbsShift(in float x) { return abs(x * 2.0 - 0.6); }   // the crease moved left — tile 14
// float fAbsShift(in float x) { return abs(x - 0.3) / 0.7; }  // the same crease, kept inside 0..1 — tile 14

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
vec3 tileSmoothstep(in vec2 tileUv, in vec2 tilePixel) {
  float x = tileUv.x;
  return drawGraph(tileUv, tilePixel, fSmoothstep(x), fSmoothstep(x + tilePixel.x));
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
vec3 tilePow(in vec2 tileUv, in vec2 tilePixel, in float exponent) {
  float x = tileUv.x;
  return drawGraph(tileUv, tilePixel, fPow(x, exponent), fPow(x + tilePixel.x, exponent));
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

vec3 tileSine(in vec2 tileUv, in vec2 tilePixel) {
  float x = tileUv.x;
  return drawGraph(tileUv, tilePixel, fSine(x), fSine(x + tilePixel.x));
}

// PHASE. Adding to the angle slides the whole wave along x — add and it
// travels left, subtract and it travels right. Nothing about the wave's SHAPE
// changes, which is exactly what makes it read as movement rather than as
// distortion.
vec3 tileSinePhase(in vec2 tileUv, in vec2 tilePixel) {
  float x = tileUv.x;
  return drawGraph(tileUv, tilePixel, fSinePhase(x), fSinePhase(x + tilePixel.x));
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
vec3 tileSineAmplitude(in vec2 tileUv, in vec2 tilePixel) {
  float x = tileUv.x;
  return drawGraph(tileUv, tilePixel, fSineAmplitude(x), fSineAmplitude(x + tilePixel.x));
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
vec3 tileSineFrequency(in vec2 tileUv, in vec2 tilePixel) {
  float x = tileUv.x;
  return drawGraph(tileUv, tilePixel, fSineFrequency(x), fSineFrequency(x + tilePixel.x));
}

// * TILE 09 — FRACT, the sawtooth, and the first BROKEN curve in the gallery.
//
// fract() keeps the fractional part and throws the whole number away, so as x
// climbs it ramps 0 up to 1, drops instantly back to 0, and does it again. The
// * 3.0 is the tile-count rule from scene 01: x spans 1.0, so multiplying by 3
// makes it cross three integers, and you get three teeth.
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

// * TILE 10 — MOD, which is the same picture as tile 09 ON PURPOSE.
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
// able to see rather than take on trust, the same way tile 03 draws pow(x, 1.0)
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
//      at 2, is two and a half teeth. That is why it looks like tile 09 with
//      the tooth count changed. It IS tile 09 with the tooth count changed.
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
//      fract genuinely cannot make on its own, see tile 11.
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

// * TILE 11 — AN ENVELOPE: teeth that shrink as they go.
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
// This is the same move as tile 07, where sin(x * PI) was multiplied by a
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

// * TILE 12 — ABS, the fold.
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
// Tiles 13 and 14 are two small variations on this one: flip it over, and
// move the crease.
vec3 tileAbs(in vec2 tileUv, in vec2 tilePixel) {
  float x = tileUv.x;
  return drawGraph(tileUv, tilePixel, fAbs(x), fAbs(x + tilePixel.x));
}

// * TILE 13 — THE TENT, which is the V turned upside down.
//
// 1.0 - y is the flip you have met before: 0 becomes 1, 1 becomes 0, and
// everything between swaps ends. Do it to the V and the crease that was at
// the bottom is now a peak at the top:
//
//     fAbs  (tile 12)          fTent = 1.0 - fAbs
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
// cut off, and the border paints over what is left. The maths is fine, the
// point is just drawn on the frame. Scale by 0.9 and add 0.05 if you ever
// want the tips to sit clear of the edges.
vec3 tileTent(in vec2 tileUv, in vec2 tilePixel) {
  float x = tileUv.x;
  return drawGraph(tileUv, tilePixel, fTent(x), fTent(x + tilePixel.x));
}

// * TILE 14 — MOVING THE CREASE, and a value escaping its box.
//
// The crease is always where the inside of the abs() is zero, because that
// is the one place where there is no sign to throw away. So to move it, solve
// "inside = 0" for x:
//
//     x * 2.0 - 1.0 = 0    ->   x = 0.5     tile 12, crease in the middle
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
// as the un-divided mod on tile 10: every time you move or stretch a
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

// * TILE — NOT WRITTEN YET. Copy tileLinear, rename it, change the one line
// that computes y, and add it to drawTile below.
vec3 tileTodo(in vec2 tileUv, in vec2 tilePixel) {
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
vec3 drawTile(in int index, in vec2 tileUv, in vec2 tilePixel) {
  if (index == 0) return tileLinear(tileUv, tilePixel);
  if (index == 1) return tileSmoothstep(tileUv, tilePixel);
  if (index == 2) return tilePow(tileUv, tilePixel, 0.5);
  if (index == 3) return tilePow(tileUv, tilePixel, 1.0);
  if (index == 4) return tilePow(tileUv, tilePixel, 2.0);
  if (index == 5) return tileSine(tileUv, tilePixel);
  if (index == 6) return tileSinePhase(tileUv, tilePixel);
  if (index == 7) return tileSineAmplitude(tileUv, tilePixel);
  if (index == 8) return tileSineFrequency(tileUv, tilePixel);
  if (index == 9) return tileFract(tileUv, tilePixel);
  if (index == 10) return tileFMod(tileUv, tilePixel);
  if (index == 11) return tileSawShrink(tileUv, tilePixel);
  if (index == 12) return tileAbs(tileUv, tilePixel);
  if (index == 13) return tileTent(tileUv, tilePixel);
  if (index == 14) return tileAbsShift(tileUv, tilePixel);
  return tileTodo(tileUv, tilePixel);
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

  vec3 color = drawTile(index, tileUv, tilePixel);
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
// 5. FRACT AND MOD.  [done — tile 09]
//    y = fract(x * 3.0). Sawtooth: ramp up, fall off a cliff, repeat. The
//    jumps show why fract() tiles and why the seam always lands on the
//    integers, which is the same seam scene 01 draws when it uses fract as a
//    coordinate rather than plotting it.
//
//    mod(x * 3.0, 1.0) is identical in GLSL, because mod is x - y*floor(x/y)
//    and floor rounds down — tile 10 draws it and the two pictures match to
//    the bit. Changing the modulus is less of an escape than it sounds: any
//    mod ramp normalised back into 0..1 is mod(a, m) / m, and that is exactly
//    fract(a / m), so it is still a sawtooth with a different tooth count. The
//    real difference is in languages where % truncates toward zero instead of
//    flooring, which flips the sign for negative inputs. Both written up on
//    tile 10.
//
//    The unplanned lesson: this is the first DISCONTINUOUS function in the
//    gallery, and it walked straight into the slope correction added for
//    tile 08. A cliff looks like a slope of -118 pixels per pixel, so the band
//    widens by 118x and paints a vertical connector at each tooth. Not wrong,
//    but a decision rather than an accident — details in the tile's comment.
//
// 5b. ENVELOPES.  [done — tile 11]
//    y = fract(x * 4.0) * (1.0 - x). Teeth that shrink as they go, which no
//    parameter of fract or mod can produce, because a repeat has no memory of
//    where it is. Multiply the repeat by a second function of x instead and
//    the second one becomes its loudness. Same trick as tile 07's pulsing
//    amplitude, keyed to position rather than to time.
//
//    Once seen, it is everywhere: a texture fading out with distance, a wobble
//    that settles down, a ripple dying away from where it was dropped. Try
//    exp(-3.0 * x) in place of 1.0 - x for a decay rather than a straight fade.
//
// 6. ABS AND SIGN.  [done — tile 12]  y = abs(x * 2.0 - 1.0)
//    The V. Same fold you used in sdBox, one dimension down. Stretch, slide
//    so the middle is zero, then abs folds the negative half up. The sharp
//    crease at the bottom is the thing to remember: abs, min and max all
//    leave one, and smin is how you round it off.
//
//    Tiles 13 and 14 are its two variations. 1.0 - fAbs(x) flips it into a
//    tent, the everyday "strongest in the middle" falloff. Changing the
//    - 1.0 moves the crease to wherever the inside of abs() is zero, and
//    shows once more that a moved function can climb out of 0..1.
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
