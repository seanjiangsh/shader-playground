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
//        |    [your turn]    |    [your turn]    |
//        +-------------------+-------------------+
//
// Each panel is one function, panelXxx(tileUv, tilePixel), and drawPanel
// below picks which one runs. The grid, plot() and the border are copied
// from level 1.1 (GLSL has no #include here), so they behave identically.

// * TUNING — each dial labelled with its space.
const float PANELS_ACROSS = 2.0;   // count
const float PANELS_DOWN   = 2.0;   // count
const float LINE_PIXELS   = 2.0;   // screen pixels: a graph line's width
const float BORDER_PIXELS = 1.0;   // screen pixels: the panel separator

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

  vec3 red   = vec3(1.0, 0.0, 0.0);
  vec3 green = vec3(0.0, 1.0, 0.0);
  vec3 blue  = vec3(0.0, 0.0, 1.0);

  vec3 color = mix(colorA, colorB, pct);                                   // 1. colour
  color = mix(color, borderColor, panelBorder(tileUv, tilePixel));         // 2. border
  color = mix(color, red,   plot(tileUv, tilePixel, pct.r, pctNext.r));    // 3. red line
  color = mix(color, green, plot(tileUv, tilePixel, pct.g, pctNext.g));    //    green line
  color = mix(color, blue,  plot(tileUv, tilePixel, pct.b, pctNext.b));    //    blue line
  return color;
}

// * PANEL 2 — HUE, SATURATION, BRIGHTNESS.  [your turn]
//
// RGB says how much of each light to mix. HSB describes a colour the way
// people talk about it:
//
//     hue          which colour, as a position around the rainbow, 0..1
//                  (0 red, 1/3 green, 2/3 blue, and 1 is red again)
//     saturation   how vivid: 0 is grey, 1 is the purest version
//     brightness   how light: 0 is black, 1 is full
//
// The panel: hue going left to right, brightness going bottom to top, so
// the whole rainbow fades to black towards the bottom.
//
// You need a function hsb2rgb(vec3 c) that turns (hue, sat, bright) into a
// vec3 RGB colour. The Book of Shaders gives a short one; it is made of
// abs, mod and clamp, all three of which you have drawn as graphs in 1.1.
// Try to read it as three shaping functions of hue, one per channel: that
// is exactly what it is.
vec3 panelHSB(in vec2 tileUv, in vec2 tilePixel) {
  return mix(todoColor, borderColor, panelBorder(tileUv, tilePixel));
}

// * PANEL 3 — COLOUR WHEEL.  [your turn]
//
// The same HSB colours, wrapped into a circle: hue becomes the ANGLE around
// the centre, and saturation the DISTANCE from it, so the middle is white
// and the rim is the pure rainbow.
//
//     angle:    atan(p.y, p.x) gives -PI..PI; divide by TWO_PI and add 0.5
//               to turn it into 0..1, a hue
//     distance: length(p), how far from the centre
//
// where p is this pixel measured from the panel's centre. One catch: the
// panels stretch with the window, so a circle in tileUv units comes out as
// an oval. Scale p.x by the panel's width-to-height ratio first, which you
// can get from tilePixel (it already holds one pixel's size on each axis).
vec3 panelWheel(in vec2 tileUv, in vec2 tilePixel) {
  return mix(todoColor, borderColor, panelBorder(tileUv, tilePixel));
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
