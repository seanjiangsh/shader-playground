// * LEVEL 1.2 — COLOURS. Four panels, each one idea about colour.
//
// Follows https://thebookofshaders.com/06/. Level 1.1 drew shaping functions
// as graphs; this level puts them to work on colour.
//
// * WHAT A COLOUR IS, TO A SHADER
//
// A colour is a vec3: three numbers, red, green and blue, each 0..1.
//
//     vec3(1.0, 0.0, 0.0)   pure red        vec3(0.0, 0.0, 0.0)   black
//     vec3(1.0, 1.0, 0.0)   yellow          vec3(1.0, 1.0, 1.0)   white
//
// Every pixel's job is to hand back one of these. A vec3 also lets you read
// its parts by name: color.r, color.g, color.b (or .x .y .z, the same thing).
//
// * THE ONE NEW IDEA: mix() WITH A vec3 AMOUNT
//
// Level 1.1 always blended with a single number: mix(lowColor, highColor, y).
// One amount, applied to all three channels at once. But mix() also accepts
// a vec3 as the amount, and then each channel gets its OWN blend:
//
//     mix(a, b, vec3(0.2, 0.9, 0.5))
//         red   is 20% of the way from a.r to b.r
//         green is 90% of the way from a.g to b.g
//         blue  is 50% of the way from a.b to b.b
//
// That is what panel 1 is about: three shaping functions, one per channel,
// so red can ease in while green waves and blue rushes up early.
//
// * THE FOUR PANELS, in reading order
//
//        +-------------------+-------------------+
//        | 0  TWO COLOURS,   | 1  ONE CURVE PER  |
//        |    ONE CURVE      |    CHANNEL        |
//        |    [done]         |    [done]         |
//        +-------------------+-------------------+
//        | 2  HUE, SATURATION| 3  COLOUR WHEEL   |
//        |    BRIGHTNESS     |                   |
//        |    [done]         |    [done]         |
//        +-------------------+-------------------+
//
// Each panel is one function, panelXxx(tileUv, tilePixel), and drawPanel
// below picks which one runs. The grid, plot() and the border are copied
// from level 1.1 (GLSL has no #include here), so they behave identically.

// * TUNING — each dial labelled with its space.
const float PANELS_ACROSS      = 2.0;  // count
const float PANELS_DOWN        = 2.0;  // count
const float LINE_PIXELS        = 2.0;  // screen pixels: a graph line's width
const float BORDER_PIXELS      = 1.0;  // screen pixels: the panel separator
const float CHANNEL_GAP_PIXELS = 4.0;  // screen pixels: how far apart panel 2 nudges its three curves
const float CHART_LOW          = 0.02; // panel units: where a curve's 0 is drawn in panel 2
const float CHART_HIGH         = 0.98; // panel units: where a curve's 1 is drawn in panel 2
const float SPIN_SPEED         = 0.1;  // turns per second: panel 3's wheel, one turn every 10 s

// * PALETTE
//
// colorA and colorB are The Book of Shaders' own pair, a deep blue and a
// warm yellow: far apart in every channel, so a blend between them passes
// through a lot of different colours on the way.
//
// curveColor is plain black, and it won a measured comparison against white
// and magenta. Checked at every point along the blue-to-yellow blend, black
// stays the furthest from the background, both in plain RGB distance
// (never closer than 0.88, where white gets to 0.73 and magenta to 0.56)
// and in brightness. White fades into the yellow end; magenta matches the
// brightness of the blend a third of the way along, where it turns violet,
// and blurs into it there. A line has to be readable on EVERY colour it
// crosses, not just the ends.
vec3 colorA      = vec3(0.149, 0.141, 0.912);  // deep blue
vec3 colorB      = vec3(1.000, 0.833, 0.224);  // warm yellow
vec3 curveColor  = vec3(0.000, 0.000, 0.000);  // black, for panel 0's line
vec3 borderColor = vec3(0.35, 0.42, 0.62);

// One line colour per channel, shared by panels 1 and 2 so "the red line
// is the red channel" means the same thing everywhere.
vec3 redLine     = vec3(1.0, 0.0, 0.0);
vec3 greenLine   = vec3(0.0, 1.0, 0.0);
vec3 blueLine    = vec3(0.0, 0.0, 1.0);
vec3 todoColor   = vec3(0.11, 0.10, 0.16);

// * CONSTANTS
const float PI     = 3.14159265;
const float TWO_PI = 6.28318531;

// * PLOT — how much of this pixel a graph line covers, 0..1.
//
// The same plot() as level 1.1, measured across the curve rather than
// straight up, with the same guard that refuses to draw across a cliff.
// Give it the curve's value here (y) and one screen pixel to the right
// (yNext); see level 1.1 for the full story of why it needs both.
float plot(in vec2 tileUv, in vec2 tilePixel, in float y, in float yNext) {
  float slope = (yNext - y) / tilePixel.y;
  float widen = sqrt(1.0 + slope * slope);
  if (abs(slope) > 20.0) return 0.0;                    // a cliff: leave a gap
  float distPixels = abs(tileUv.y - y) / tilePixel.y;   // straight up, in pixels
  float perpPixels = distPixels / widen;                // across the curve
  float band = perpPixels - 0.5 * LINE_PIXELS;
  return 1.0 - clamp(0.5 + band, 0.0, 1.0);
}

// * PANEL BORDER — the thin separator, same as level 1.1.
float panelBorder(in vec2 tileUv, in vec2 tilePixel) {
  vec2 toEdge = min(tileUv, 1.0 - tileUv) / tilePixel;   // in screen pixels
  float dist = min(toEdge.x, toEdge.y) - BORDER_PIXELS;
  return 1.0 - clamp(0.5 + dist, 0.0, 1.0);
}

// * PANEL 0 — TWO COLOURS, ONE CURVE.
//
// Level 1.1's gradient with real colours: one shaping function decides how
// far from colorA towards colorB each column is, and the same number is
// drawn as a line so you can see the curve that made the colour.
//
//     pct = smoothstep(0, 1, x)          0 at the left, 1 at the right, eased
//     colour = mix(colorA, colorB, pct)  blue -> yellow, following the S
//
// The layers are the same as level 1.1: colour first, then the border, then
// the line on top so it is never hidden.
//
// Things to try here before moving on: swap smoothstep for any function from
// the 1.1 gallery (pow(x, 5.0) is a good one) and watch how much longer the
// blue holds on. The colour follows the curve exactly; the curve is the
// colour, drawn sideways.
vec3 panelTwoColors(in vec2 tileUv, in vec2 tilePixel) {
  float x       = tileUv.x;
  float pct     = smoothstep(0.0, 1.0, x);
  float pctNext = smoothstep(0.0, 1.0, x + tilePixel.x);

  vec3 color = mix(colorA, colorB, pct);                                // 1. colour
  color = mix(color, borderColor, panelBorder(tileUv, tilePixel));      // 2. border
  color = mix(color, curveColor, plot(tileUv, tilePixel, pct, pctNext)); // 3. line
  return color;
}

// * PANEL 1 — ONE CURVE PER CHANNEL.  [done]
//
// Panel 0 with pct turned into a vec3: one shaping function per channel,
// and mix() blending each channel by its own amount.
//
//     red     smoothstep(0, 1, x)   eases in and out
//     green   sin(x * PI)           up and back down, an arch
//     blue    pow(x, 0.5)           rushes up early
//
// The three curves live in one helper, channelCurves(), called twice: at x
// for the colour, and one pixel to the right for plot(). Same lesson as the
// f-functions in 1.1: write it once, so the two copies cannot drift apart.
//
// * WHAT THE COLOURS SAY, measured from a render
//
// Read any column straight down: the three lines' heights ARE the three
// blend amounts, and the background is what mix() made of them.
//
//     x = 0      amounts (0, 0, 0)        deep blue, all colorA
//     x = 0.5    amounts (0.5, 1, 0.71)   (0.57, 0.83, 0.43): light green
//     x = 1      amounts (1, 0, 1)        (1.00, 0.14, 0.22): RED
//
// Two surprises worth keeping. The middle is greener than either end colour,
// because green's arch is at the top there and colorB is the greener of the
// two. And the right edge is not yellow at all: the arch has come back down
// to 0, so green takes colorA's 0.14 while red and blue take colorB's. A
// per-channel blend can make colours that are nowhere "between" a and b.
//
// LINE COLOURS. Pure red, green and blue, so each line says which channel
// it steers. Each one only fades where it crosses a background close to its
// own colour: the blue line at the far left (deep blue there) and the red
// line at the far right (red there), about 2% of the width each, measured.
// Fine for a picture you read by its middle; a dark outline under each line
// would fix it if it ever matters.
vec3 channelCurves(in float x) {
  return vec3(
    smoothstep(0.0, 1.0, x),   // red:   eases in and out
    sin(x * PI),                        // green: up and back down, an arch
    pow(x, 0.5)                          // blue:  rushes up early
  );
}

vec3 panelPerChannel(in vec2 tileUv, in vec2 tilePixel) {
  float x      = tileUv.x;
  vec3 pct     = channelCurves(x);
  vec3 pctNext = channelCurves(x + tilePixel.x);

  vec3 color = mix(colorA, colorB, pct);                                       // 1. colour
  color = mix(color, borderColor, panelBorder(tileUv, tilePixel));             // 2. border
  color = mix(color, redLine,   plot(tileUv, tilePixel, pct.r, pctNext.r));    // 3. red line
  color = mix(color, greenLine, plot(tileUv, tilePixel, pct.g, pctNext.g));    //    green line
  color = mix(color, blueLine,  plot(tileUv, tilePixel, pct.b, pctNext.b));    //    blue line
  return color;
}

// * PANEL 2 — HUE, SATURATION, BRIGHTNESS.  [done]
//
// RGB says how much of each light to mix. HSB describes a colour the way
// people talk about it:
//
//     hue          which colour, as a position around the rainbow, 0..1
//                  (0 red, 1/3 green, 2/3 blue, and 1 is red again)
//     saturation   how vivid: 0 is no colour at all (white, or grey once
//                  brightness drops), 1 is the purest version
//     brightness   how light: 0 is black, 1 is full
//
// The panel: hue left to right, brightness bottom to top, saturation fixed
// at 1. So the full rainbow runs along the top and fades to black at the
// bottom.
//
// * READING hsb2rgb, from The Book of Shaders
//
// The first line builds the rainbow out of four things you drew in 1.1,
// worked from the inside out, for all three channels at once:
//
//     c.x * 6.0 + vec3(0, 4, 2)   hue stretched to 0..6, each channel
//                                 given its own head start
//     mod(..., 6.0)               wrap around past the end   (tile 14)
//     abs(... - 3.0)              slide and fold into a V    (tiles 16-18)
//     ... - 1.0, clamp to 0..1    lower it, flatten the rest (tile 03)
//
// The result is ONE flat-topped bump per channel, the same shape shifted
// by a third of the rainbow each time. Traced by hand: hue 0 gives
// (1, 0, 0), red; hue 1/3 gives (0, 1, 0), green. The second line is
// smoothstep's t * t * (3 - 2t) from tile 02, rounding the bumps' corners.
// The third mixes from white towards that colour by the saturation, then
// multiplies by the brightness.
//
// * THE THREE CURVES ON TOP
//
// The red, green and blue lines are the three channels of
// hsb2rgb(vec3(x, 1.0, 1.0)): the rainbow drawn as three shifted
// flat-topped bumps, each a third of the way along from the last.
//
//     hue     0    1/6   1/3   1/2   2/3   5/6    1
//     red     1     1     0     0     0     1     1
//     green   0     1     1     1     0     0     0
//     blue    0     0     0     1     1     1     0
//             red yellow green cyan blue magenta red
//
// Read any column down and you get that hue: yellow is red 1 + green 1.
//
// WHY THE FIRST VERSION DID NOT LOOK LIKE THIS, even though its maths was
// right. Two things hid the flat parts, which are the whole shape:
//
//   1. Every flat run sits at exactly 0 or 1, ON the panel's frame, and two
//      channels are often flat together, so their lines lay on top of each
//      other and only the last one drawn showed.
//   2. Each channel is at 1 exactly where the background contains that
//      colour: a red line at the top over red, a blue line over blue. A
//      line the colour of its background disappears.
//
// What was left visible was mostly the slopes, which read as three humps
// in mixed colours rather than three plateaus. The fix is all display, not
// maths: the chart is squeezed into CHART_LOW..CHART_HIGH (0.02..0.98) to
// lift it just off the frame, and
// the three curves are nudged a few pixels apart so shared flat runs sit
// side by side. The lines are now a picture of the curves' SHAPES; their
// height is no longer the exact value, which is fine for a chart.
//
// Point 2 is still partly there, on purpose: the lines keep panel 1's plain
// look, with no outline. Measured, each line sits on a background close to
// its own colour for about 12% of the width, the far ends of the red top
// run and the middles of the green and blue ones, where it gets faint.
// Moving the chart into the darker lower half of the panel (CHART_LOW 0.05,
// CHART_HIGH 0.5) brings that to 0%, if it ever bothers you. (Measured at
// 0.1..0.9 first; the current 0.02..0.98 gives the same 12%.)
vec3 hsb2rgb(in vec3 c) {
  vec3 rgb = clamp(abs(mod(c.x * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
  rgb = rgb * rgb * (3.0 - 2.0 * rgb);       // soften the corners: smoothstep's curve
  return c.z * mix(vec3(1.0), rgb, c.y);     // saturation from white, then brightness
}

vec3 panelHSB(in vec2 tileUv, in vec2 tilePixel) {
  float hue        = tileUv.x;   // left to right: around the rainbow
  float saturation = 1.0;        // fully vivid
  float brightness = tileUv.y;   // bottom to top: black to full

  vec3 color = hsb2rgb(vec3(hue, saturation, brightness));            // 1. colour
  color = mix(color, borderColor, panelBorder(tileUv, tilePixel));    // 2. border

  // 3. The rainbow's three channel curves, drawn as a chart on top. Full
  // saturation and brightness here, whatever the background is doing.
  vec3 rgb     = hsb2rgb(vec3(hue,               1.0, 1.0));
  vec3 rgbNext = hsb2rgb(vec3(hue + tilePixel.x, 1.0, 1.0));

  // Squeeze 0..1 into CHART_LOW..CHART_HIGH so the flat runs come off the
  // frame, then nudge the three curves apart (red up, blue down) so where
  // two channels are flat together their lines sit side by side instead
  // of on top of each other.
  vec3 nudge     = vec3(1.0, 0.0, -1.0) * CHANNEL_GAP_PIXELS * tilePixel.y;
  vec3 lineY     = mix(vec3(CHART_LOW), vec3(CHART_HIGH), rgb)     + nudge;
  vec3 lineYNext = mix(vec3(CHART_LOW), vec3(CHART_HIGH), rgbNext) + nudge;

  color = mix(color, redLine,   plot(tileUv, tilePixel, lineY.r, lineYNext.r));
  color = mix(color, greenLine, plot(tileUv, tilePixel, lineY.g, lineYNext.g));
  color = mix(color, blueLine,  plot(tileUv, tilePixel, lineY.b, lineYNext.b));
  return color;
}

// * PANEL 3 — COLOUR WHEEL.  [done]
//
// The same HSB colours, wrapped into a circle: hue becomes the ANGLE around
// the centre, and saturation the DISTANCE from it, so the middle is white
// and the rim is the pure rainbow.
//
//     p        tileUv - 0.5   measured from the panel's centre, not its
//                             corner, so the angle can go all the way round
//     hue      atan(p.y, p.x) / TWO_PI   the direction, in turns, -0.5..0.5
//     radius   length(p) * 2             0 at the centre, 1 at the wheel's edge
//
// * atan, AND WHERE THE COLOURS LAND
//
// atan(y, x) answers "which direction is this point from the centre?" as
// an angle in radians, starting from the right and counting anticlockwise:
//
//                    up   PI/2  (90 degrees)
//                          |
//     left  PI or -PI -----+----- 0  right
//                          |
//                  down  -PI/2  (-90 degrees)
//
// Above the centre the angle is positive, below it negative. It takes y and
// x separately, not y / x, because the signs say which side the point is
// on: (1, 1) and (-1, -1) have the same y / x but opposite directions.
// Dividing by TWO_PI turns radians into fractions of a turn, -0.5..0.5.
//
// That puts the colours where the standard hue wheel has them:
//
//     0 degrees    right          hue 0      red
//     120 degrees  upper left     hue 1/3    green
//     240 degrees  lower left     hue -1/3   blue (the same spot as 2/3)
//
// THE NEGATIVE HALF NEEDS NO FIX. Below the centre hue is negative, but a
// hue is a position on a circle, so -1/3 and 2/3 are the same spot, a third
// of a turn back from red or two thirds forward. hsb2rgb starts with
// mod(hue * 6.0 + ..., 6.0), which folds any hue back into one turn, and
// GLSL's mod rounds down, so negatives come out positive (the tile 14 note
// about C and JavaScript's % working differently). Checked: with or without
// fract() around the hue, every colour matches to 8.9e-16.
//
// fract(hue) would only matter if the hue went somewhere that does NOT wrap
// by itself: plotted as a line, compared ("above 0.5?"), or handed to a
// different colour function. Then -1/3 would show up as wrong.
//
// An earlier version added 0.5 to make the hue 0..1. That works too, but it
// turns the wheel half a turn, putting red on the left instead of the right.
//
// * TWO FIXES ON TOP OF THE FIRST VERSION
//
// ROUND, NOT OVAL, ON ANY SCREEN. Panels stretch with the window, so one
// step in tileUv is a different number of pixels across than up, and a
// circle in tileUv units comes out as an oval. The fix is to measure both
// axes in the same unit: the panel's SHORT side.
//
//     panelSize = 1.0 / tilePixel     the panel in pixels: tilePixel is one
//                                     pixel in panel units, so flip it
//     p *= panelSize / min(panelSize.x, panelSize.y)
//
// The short side is multiplied by 1 and keeps its -0.5..0.5. The long side
// is stretched past that, and the extra is the spare space beside (or
// above and below) the wheel. So the wheel's diameter is always the short
// side, and the whole rim always fits.
//
//     wide panel (450 x 300)   short side is the height: wheel 300 across
//     tall panel (300 x 600)   short side is the width:  wheel 300 across
//
// THE BUG THIS REPLACED. The first fix scaled only p.x, by width / height,
// which measures in panel HEIGHTS. Fine while the panel is wider than it
// is tall. On a tall phone-shaped panel the height is the LONG side, so
// the wheel came out wider than the panel and its rim fell off the left
// and right: at the middle of the right edge, with width / height = 0.5,
// radius was only 0.5, a half-white red that read as pink. Checked after
// the fix: saturation is 1.0 at the middle of the right edge and the top
// edge for a wide, a tall and a square window. The same "anchor to the
// short edge" idea as the centred pos in scene 01.
//
// THE CORNERS. Outside the wheel, length(p) * 2 passes 1, and a saturation
// above 1 pushes mix(white, rainbow, s) PAST the rainbow. Measured in the
// first version, channels went as low as -0.41. The screen quietly clamps
// that to 0, so the picture did not look broken, but the numbers were
// outside 0..1, and that bites as soon as the colour feeds into anything
// else (another mix, lighting, adding glows). min(radius, 1.0) holds the
// saturation at the pure rainbow from the rim outwards, so the corners
// carry the rim's colour on and every channel stays in 0..1. Same "does it
// still fit 0..1?" reflex as level 1.1.
//
// * FROM WHITE TO COLOUR, WITHOUT A RING
//
// With saturation = radius, two things showed. A ring at the rim: the
// saturation climbs at a steady rate and then min() stops it dead, and the
// eye is very good at spotting a gradient that suddenly changes speed even
// with no jump in colour. It is the crease that clamp, min and max leave
// (tiles 03, 19, 20), drawn as a circle. And a pale inside: a straight ramp
// is only half saturated at half the radius.
//
// The fix is a different shaping curve between radius and saturation, one
// that rises fast near the centre and arrives at 1 FLAT. The parabola from
// tile 07, flipped so its flat end lands at the rim:
//
//     saturation = 1 - (1 - radius)^3
//
//     curve             at half radius   slope at the rim   slope at centre
//     straight ramp         0.50              1 (ring)            1
//     1 - (1 - r)^2         0.75              0                   2
//     1 - (1 - r)^3         0.88              0                   3    <- used
//     1 - (1 - r)^5         0.97              0                   5
//     smoothstep            0.50              0                   0
//
// The power is a taste dial, and every power above 1 lands flat, so none of
// them brings the ring back: 2 is gentle, 5 makes colour arrive almost at
// once and leaves only a pinprick of white, and 3 sits between, keeping a
// soft white centre. smoothstep removes the ring too but starts flat as
// well, so the white centre grows instead of shrinking.
//
// TWO THINGS THE FIRST TRY GOT WRONG, worth knowing:
//
//   1. It used 1 - pow(1 - length(p), 5) directly. Without the * 2 the
//      rim sits at length 0.5, where the curve is still climbing (0.97,
//      slope 0.31), so a faint ring stays. Worse, without the min() the
//      corners of a stretched panel go past length 1, and pow() gets a
//      negative base, which GLSL leaves undefined (NaN or garbage,
//      depending on the GPU). Measured: corners reach length 1.12 on a
//      600 x 1200 window and 1.42 on 1600 x 600. Clamping radius first
//      keeps 1 - radius at 0 or above everywhere.
//   2. smoothstep(0.0, 1.0, 1.0) was given the number 1 as its input, not
//      the radius, so every pixel got saturation 1 and the white centre
//      vanished. The third argument is the thing being eased:
//      smoothstep(0.0, 1.0, length(p) * 2.0). It clamps by itself, so no
//      min() is needed there.
//
// * SPINNING
//
// Rotating the wheel is just shifting the hue with time, the same move as
// tile 10's phase made the sine wave slide:
//
//     hue -= iTime * SPIN_SPEED
//
// The hue is already measured in TURNS (it was divided by TWO_PI), so the
// speed reads directly as turns per second: 0.1 is one turn every 10 s.
// And it needs no wrapping, even though the hue now grows forever: the mod
// inside hsb2rgb folds it back into one turn every frame, the same reason
// the negative half of atan needed no fract().
//
// WHICH WAY IT TURNS. Pick one colour, red at hue 0. It shows wherever
// direction - time comes out as a whole turn, so as time grows the
// direction that shows red has to grow with it, and a growing angle goes
// anticlockwise (atan counts anticlockwise from the right). So minus turns
// the colours anticlockwise and plus turns them clockwise, which is easy to
// guess the wrong way round: "adding" sounds like "forwards".
//
// ADD, DON'T MULTIPLY. The first try wrote hue *= iTime * SPIN_SPEED. At
// the start that multiplies every hue by 0, a solid red wheel; after that
// the multiplier keeps growing, so one trip round the wheel passes through
// more and more rainbows (two after 20 s, ten after 100) until it blurs.
// The same three knobs as the sine tiles:
//
//     add to the input        phase       the colours rotate
//     multiply the input      frequency   more rainbows per turn
//
// One quiet detail: atan(0, 0) has no proper answer, and it would be asked
// at the exact centre. No pixel centre lands there (pixel centres sit at
// half-pixel positions), and the centre is white whatever the hue anyway,
// because saturation is 0 there.
vec3 panelWheel(in vec2 tileUv, in vec2 tilePixel) {
  vec2  panelSize = 1.0 / tilePixel;                         // the panel, in screen pixels

  vec2  p      = tileUv - 0.5;                               // from the centre, -0.5..0.5
  p           *= panelSize / min(panelSize.x, panelSize.y);  // measured in the SHORT side: round, and fits
  float hue    = atan(p.y, p.x) / TWO_PI;                    // direction in turns, -0.5..0.5; hsb2rgb wraps it
  hue         -= iTime * SPIN_SPEED;                         // spin: minus turns the colours anticlockwise
  float radius = min(length(p) * 2.0, 1.0);                  // 0 at the centre, 1 at the rim and beyond

  // Saturation from the radius through an ease-out curve: colour arrives
  // fast, and lands at 1 with zero slope, so no ring shows at the rim.
  float saturation = 1.0 - pow(1.0 - radius, 3.0);
  // float saturation = radius;                                // straight ramp: pale inside, ring at the rim
  // float saturation = smoothstep(0.0, 1.0, length(p) * 2.0); // no ring, but a big white centre

  vec3  color  = hsb2rgb(vec3(hue, saturation, 1.0));              // 1. colour
  return mix(color, borderColor, panelBorder(tileUv, tilePixel));  // 2. border
}

// * DISPATCH — panel index in, colour out.
vec3 drawPanel(in int index, in vec2 tileUv, in vec2 tilePixel) {
  if (index == 0) return panelTwoColors(tileUv, tilePixel);
  if (index == 1) return panelPerChannel(tileUv, tilePixel);
  if (index == 2) return panelHSB(tileUv, tilePixel);
  return panelWheel(tileUv, tilePixel);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
  // The same grid as level 1.1, just 2 x 2 instead of 5 x 5.
  vec2 uv        = fragCoord / iResolution.xy;          // 0..1 across the window
  vec2 grid      = vec2(PANELS_ACROSS, PANELS_DOWN);
  vec2 cell      = uv * grid;                           // 0..2 on each axis
  vec2 tileId    = floor(cell);                         // which panel
  vec2 tileUv    = fract(cell);                         // where inside it, 0..1
  vec2 tilePixel = grid / iResolution.xy;               // one screen pixel, in panel units

  // Reading order, 0 top-left: GL's y points up, so the row is flipped.
  int index = int(tileId.x) + int((PANELS_DOWN - 1.0) - tileId.y) * int(PANELS_ACROSS);

  fragColor = vec4(drawPanel(index, tileUv, tilePixel), 1.0);
}
