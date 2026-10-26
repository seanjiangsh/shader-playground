// * LEVEL 2 — SIGNED DISTANCE FIELDS. A gallery: one panel per exercise.
//
// House style, repo-wide: every SECTION heading starts with `// *`, and the
// lines under it are plain `//`. The Better Comments extension paints the
// starred line, so a long file skims as a list of headings. One star per
// topic; sub-notes and commented-out variants stay unstarred.
//
// The idea in one sentence: instead of asking "is this pixel inside the shape?",
// you compute HOW FAR this pixel is from the shape's edge.
//
//    negative = inside     0 = exactly on the edge     positive = outside
//
// That single number is far more useful than a yes/no. Distance lets you
// anti-alias the edge, thicken it into an outline, glow outward from it, round
// off corners where two shapes meet, and repeat a shape across the screen — all
// with arithmetic, and no extra geometry.
//
// * HOW THIS FILE IS ORGANISED
//
// It used to be one picture built up over exercises 1 to 8, each new idea
// layered on the last. It is now a 4 x 4 gallery like levels 1.1 and 1.2:
// one panel per exercise, so every idea can be seen on its own, beside the
// one before it. The finished picture from before still exists, whole, in
// panel 12.
//
//        +----------------+----------------+----------------+----------------+
//        | 0  the field   | 1  mask, AA    | 2  contours    | 3  box         |
//        +----------------+----------------+----------------+----------------+
//        | 4  union       | 5  intersect   | 6  circle-box  | 7  box-circle  |
//        +----------------+----------------+----------------+----------------+
//        | 8  morph       | 9  smooth      | 10 outline     | 11 glow        |
//        |                |    union       |                |                |
//        +----------------+----------------+----------------+----------------+
//        | 12 repeat, all | 13 per-cell    | 14 drop shadow | 15 transforms  |
//        |    together    |    identity    |    [your turn] |    [next]      |
//        |                |    [your turn] |                |                |
//        +----------------+----------------+----------------+----------------+
//
// Each panel's lessons live in that panel's own comment, right above its
// function. The shared machinery comes first, in the order a pixel uses it:
//
//    sdCircle / sdBox / smin      the shapes and the smooth join
//    panelPos / panelOnePixel     where am I in this panel, how big is a pixel
//    repeatDomain / fitToCell     fold the plane, fit the artwork to a cell
//    circleField / boxField / sceneField    the two-shape design, scaled
//    coverage / outlineField / glowFrom / contourRings    the masks
//    paintLayers                  stack colors using those masks
//
// The split between the masks and the painting is the one worth keeping. A
// mask says WHERE something is; painting says WHAT color goes there and IN
// WHAT ORDER. Both bugs in exercise 8 were painting bugs wearing a maths
// costume, so the file keeps them visibly apart.
//
// A worked solution is parked at src/_parked/02-shape-sdf-reference/ — it won't
// appear in the sidebar. Try not to open it until yours runs.

// * PALETTE, at global scope. GLSL ES 1.00 permits that only because all
// three initialisers are constant expressions; a global initialised from a
// uniform or a function call would not compile. Saying `const` states that
// intent and lets the compiler treat them as literals:
//    const vec3 shapeColor = vec3(0.0);
//
// outlineColor earns its place here rather than being a local: once the outline
// is PAINTED rather than erased, the ink is a third thing the picture is made
// of, on the same footing as the fill and the background.
vec3 shapeColor = vec3(0.0, 0.0, 0.0);
vec3 bgColor = vec3(0.05, 0.04, 0.35);
vec3 outlineColor = vec3(1.0, 1.0, 1.0);
vec3 borderColor  = vec3(0.35, 0.42, 0.62);   // the panel separator, same as levels 1.1 and 1.2
vec3 todoColor    = vec3(0.11, 0.10, 0.16);   // an empty panel waiting for its exercise

// * TUNING — every dial in the scene, in one place.
//
// They are up here because the functions below need them and GLSL has no
// closures; ALL_CAPS marks them as globals so a name inside a function is
// obviously either a parameter or one of these.
//
// The comment against each one is its SPACE, and that is the single most
// useful thing to know about any constant in this file. Mixing spaces is
// where every layout bug so far came from:
//
//   screen pixels   measured in onePixel — independent of zoom
//   pos units       -1..1 across the short axis of the window
//   design units    whatever reads nicely for the artwork itself
//
//   screen pixels   measured in onePixel, independent of zoom
//   pos units       -1..1 across the short axis of a PANEL
//   design units    whatever reads nicely for the artwork itself
//
// OUTLINE_PIXELS and GLOW_PIXELS were 5 and 16 when the scene filled the
// whole window. A panel is a quarter of the size, so they are scaled down to
// keep the same look; they are still in screen pixels, which is the point.
//
const float PANELS_ACROSS  = 4.0;              // count
const float PANELS_DOWN    = 4.0;              // count
const float BORDER_PIXELS  = 1.0;              // screen pixels: the panel separator
const float CELLS_ACROSS   = 3.0;              // count: repeat cells across panel 12's short axis
const float CELL_FILL      = 0.8;              // fraction of a cell (or a panel) the artwork spends
const vec2  SHAPE_OFFSET   = vec2(0.3, 0.0);   // design units
const float CIRCLE_RADIUS  = 0.6;              // design units (pos units in panels 0 to 3)
const vec2  BOX_HALF_SIZE  = vec2(0.6, 0.4);   // design units (pos units in panels 0 to 3)
const float OUTLINE_PIXELS = 2.0;              // screen pixels (half the line width)
const float GLOW_PIXELS    = 6.0;              // screen pixels
const float GLOW_INTENSITY = 0.3;              // brightness, unitless
const float CONTOUR_FREQ   = 10.0;             // 1 / pos units
const float CONTOUR_AMOUNT = 0.06;             // brightness, unitless

// * sdCircle — the easy one: distance from the origin, shifted so that 0
// lands on the rim. sdBox below is the same idea, only harder to see.
float sdCircle(in vec2 pos, in float radius)
{
  return length(pos) - radius;
}

// * sdBox — halfSize is measured out from the CENTRE, so vec2(0.6, 0.4) is a
// box 1.2 wide and 0.8 tall in pos units — not 0.6 x 0.4. That catches
// everyone once, and it's why an over-large halfSize fills the whole screen.
//
// The four regions the function has to handle, after folding:
//
//     corner | face  | corner
//     -------+-------+-------
//      face  |INSIDE |  face
//     -------+-------+-------
//     corner | face  | corner
//
float sdBox(in vec2 pos, in vec2 halfSize)
{
  // 1. FOLD the plane into the +x +y quadrant. A box is symmetric about both
  //    axes, so (-0.7, -0.2) is exactly as far from it as (0.7, 0.2). Mirroring
  //    is free and leaves the rest of the function reasoning about ONE corner
  //    rather than four.
  vec2 foldedPos = abs(pos);

  // 2. How far PAST the edge are we, on each axis independently?
  //    positive = outside the box on that axis, negative = still inside it.
  vec2 overshoot = foldedPos - halfSize;

  // 3. OUTSIDE distance. Zero out any axis we are still inside, then take the
  //    length of what remains:
  //      past one face  -> one component survives -> straight-line distance
  //                        to that face
  //      past a corner  -> both survive -> length() gives the diagonal
  //                        distance to the corner point itself
  //    That second case is what makes the field correct around corners, which
  //    is what later lets glows and smooth unions behave there.
  float outsideDist = length(max(overshoot, 0.0));

  // 4. INSIDE distance. In here both components are negative, and the one
  //    CLOSEST to zero is the nearest edge — max() picks it. It is already
  //    negative, which is the sign an SDF wants inside. min(..., 0.0) switches
  //    this term off whenever we are outside.
  float insideDist = min(max(overshoot.x, overshoot.y), 0.0);

  // At most one of the two is non-zero for any pixel, so adding them is just a
  // branchless way of saying "whichever case applies".
  return outsideDist + insideDist;
}

// * SMOOTH MINIMUM (the polynomial one). A union that fillets its own join
// instead of creasing it. Two halves, and they do different jobs.
//
// k is a DISTANCE, in the same units as the fields, and it sets how wide the
// blend band around the join is. Outside that band nothing happens at all.
//
// --- half one: h, a blend factor -------------------------------------------
//   float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
//
// (b - a) is how much the two fields disagree. Dividing by k measures that
// disagreement in units of k, and 0.5 + 0.5*x maps the range -1..1 onto 0..1.
// So h saturates the moment the fields differ by more than k:
//
//   b - a >= +k   ->  h = 1   ->  a is clearly the smaller, pick a
//   a - b >= +k   ->  h = 0   ->  b is clearly the smaller, pick b
//   a == b        ->  h = 0.5 ->  dead tie, right on the join
//
// --- half two: interpolate, then bulge --------------------------------------
//   return mix(b, a, h) - k * h * (1.0 - h);
//
// mix(b, a, h) slides between the two fields instead of snapping. At h = 0 or
// h = 1 it returns exactly b or a, which is exactly what min() would return —
// that is why the function is a no-op away from the join.
//
// The second term is the fillet. h*(1-h) is a parabola: zero at h = 0 and
// h = 1, peaking at 0.25 when h = 0.5. Multiplied by k and SUBTRACTED, it
// pushes the field more negative near the tie and not at all elsewhere. More
// negative means further inside, so the surface bulges outward exactly where
// the two shapes meet. The bulge peaks at k/4 of extra depth at the tie.
//
// Together: the mix removes the sudden hand-over, and the parabola adds the
// material that rounds the corner. Both terms vanish outside the band, so the
// result is exactly min() there, and the seam between blended and unblended is
// itself smooth.
//
// Symmetric in a and b, as a union should be: swapping them turns h into 1-h,
// and both terms are unchanged by that.
//
// Related, free: smax(a, b, k) = -smin(-a, -b, k), so smooth intersection and
// smooth subtraction come from the same function. Unused so far, kept because
// it costs one line and is the thing to reach for when a smooth intersection
// is wanted.
//
// Caveat: the result is no longer a true distance field near the join — it
// under-reports — which is the usual price for smoothness.
float smin(float a, float b, float blendWidth) {
  float h = clamp(0.5 + 0.5 * (b - a) / blendWidth, 0.0, 1.0);
  return mix(b, a, h) - blendWidth * h * (1.0 - h);
}
float smax(float a, float b, float blendWidth) {
  return -smin(-a, -b, blendWidth);
}

// * WHERE AM I IN THIS PANEL. Centred on the panel, and normalised by the
// panel's SHORT side, so pos always spans -1..1 across it and a radius reads
// directly as a fraction: radius = 1.0 touches the short edges, 0.6 makes the
// circle 60% of the short side. min() here is CSS object-fit: contain, and
// max() would be cover. Before the gallery this was centredPos(fragCoord),
// the same sum done for the whole window.
//
// tilePixel is one screen pixel in panel units, so 1.0 / tilePixel is the
// panel's size in pixels. Same short-side trick as the colour wheel in 1.2.
vec2 panelPos(in vec2 tileUv, in vec2 tilePixel) {
  vec2 panelSize = 1.0 / tilePixel;                        // the panel, in screen pixels
  return (2.0 * tileUv - 1.0) * panelSize / min(panelSize.x, panelSize.y);
}

// * ONE SCREEN PIXEL, measured in pos units. It must use the same divisor as
// panelPos or every "one pixel wide" thing in the file quietly lies. Kept as
// its own function so that pairing is impossible to break by editing one and
// not the other.
float panelOnePixel(in vec2 tilePixel) {
  vec2 panelSize = 1.0 / tilePixel;
  return 2.0 / min(panelSize.x, panelSize.y);
}

// * PANEL BORDER — the thin separator, the same as levels 1.1 and 1.2.
float panelBorder(in vec2 tileUv, in vec2 tilePixel) {
  vec2 toEdge = min(tileUv, 1.0 - tileUv) / tilePixel;   // in screen pixels
  float dist = min(toEdge.x, toEdge.y) - BORDER_PIXELS;
  return 1.0 - clamp(0.5 + dist, 0.0, 1.0);
}

// * REPEAT THE DOMAIN. The last of the coordinate tricks, and the same move as
// offsetting and folding: nothing is copied, the COORDINATE is wrapped.
//
//   floor(pos / cellSize + 0.5)   round-to-nearest — the index of the cell
//                                 centre nearest this pixel
//   * cellSize                    that centre's position
//   pos - (...)                   where I am RELATIVE to my own cell centre
//
// Following one axis through it, with cellSize = 0.5:
//
//   pos        -1.0    -0.5     0.0     0.5     1.0        the whole axis
//                |       |       |       |       |
//   nearest      |       |       |       |       |         each pixel picks
//   centre    -1.0    -0.5     0.0     0.5     1.0         the centre it is
//                |       |       |       |       |         closest to
//                v       v       v       v       v
//   cellPos      0       0       0       0       0         and reports its
//             -.25 +.25  -.25 +.25  -.25 +.25              offset from it
//
// so the result only ever spans -cellSize/2 .. +cellSize/2, no matter how far
// out `pos` goes. The whole plane gets folded into one cell. The + 0.5 is what
// centres a cell on the origin; a plain floor() would put a cell CORNER there
// instead. One fold, no loop: a thousand copies cost what one costs.
//
// COUNT cells rather than measure them. pos spans -1..1 on the short axis, so
// that axis is 2.0 units wide, which makes a hand-written cellSize confusing:
// 0.5 is not "half", it is a quarter of the short side. Deriving cellSize from
// CELLS_ACROSS puts the number you actually care about on the left.
//
// Odd counts end flush. Cell boundaries land at (k + 0.5) * cellSize, so they
// coincide with the screen edge at 1.0 only when CELLS_ACROSS is odd; an even
// count slices the top and bottom rows in half. 3 is odd. The long axis is a
// different width, so it gets sliced either way.
//
// The price: this is no longer a true distance field. A pixel measures only
// against its OWN cell's copy, never the neighbour that might be nearer. That
// is invisible in the fill mask (which only cares about the sign right beside
// the shape, nowhere near a seam) but it is plainly visible in the contour
// rings and in the glow, which read the field far from the shape.
vec2 repeatDomain(in vec2 pos, in float cellSize) {
  return pos - cellSize * floor(pos / cellSize + 0.5);
}

// * FIT THE ARTWORK TO THE CELL, instead of hand-tuning it to match. Returns
// the scale factor sceneField draws at.
//
// Repetition wraps the coordinate; it does not SHRINK anything. So the first
// attempt kept radius 0.6 and offset 0.3, which reach 0.9 from the design
// origin, and posted them into a cell with only cellSize/2 to spend. Every
// pixel came out inside something and the screen went solid. Nothing was wrong
// with the repeat line; the constants were simply written in the wrong space.
//
// designReach is how far the design reaches from its own origin: the radius of
// a bounding circle around everything in it. For the disc that is centre
// distance plus radius. For the box it is the far CORNER, which is why it is
// length(SHAPE_OFFSET + BOX_HALF_SIZE) and not SHAPE_OFFSET.x +
// BOX_HALF_SIZE.x — those happen to agree only because this offset is
// axis-aligned.
//
// A bounding circle is conservative for a square cell, since the cell's corners
// sit further out than its walls, so this packs slightly looser than it has to.
// It is one line, and it stays correct if the design ever rotates.
//
// Then it is simply budget over demand: half a cell is what there is,
// designReach is what was asked for, and CELL_FILL says how much of the budget
// to actually spend. CELL_FILL = 1.0 means neighbouring bounding circles touch.
//
// The test that this is wired up properly: change CELLS_ACROSS on its own and
// the picture should re-tile with every shape keeping its proportions and its
// share of the cell. Measured across three cell sizes, the fraction of each
// cell covered by the artwork stayed identical to three decimal places.
// What the numbers mean, drawn:
//
//     +-------------------------+  <- the cell, cellSize across
//     |         . - - .         |
//     |      ,'         `.      |  designReach = how far the artwork
//     |    /               \    |                reaches from its centre
//     |   |        +--------|---|  <- half a cell: the whole budget
//     |   |       (o)       |   |
//     |    \               /    |  CELL_FILL shrinks that reach to
//     |      `.         ,'      |  80% of the budget, leaving a gutter
//     |         ` - - '         |
//     +-------------------------+
//
//   shapeScale = (what there is) / (what was asked for)
//              = CELL_FILL * half a cell / designReach
float fitToCell(in float cellSize) {
  float designReach = max(length(SHAPE_OFFSET) + CIRCLE_RADIUS,
                          length(SHAPE_OFFSET + BOX_HALF_SIZE));
  return CELL_FILL * 0.5 * cellSize / designReach;
}
//
// The panels reuse it with a cellSize of 2.0: a whole panel is one big cell,
// 2.0 pos units across its short side, so fitToCell(2.0) is the scale that
// fits the two-shape design into a panel with the same gutter as a cell.

// * THE TWO-SHAPE DESIGN — the circle and the box every combining panel uses.
//
// SCALING AN SDF: divide the position going in, multiply the distance coming
// out.
//
//    d = sdShape(pos / s, params) * s
//
// The divide zooms the shape. The multiply puts the answer back into pos units,
// which is what keeps onePixel and the AA ramp meaningful. Forget the multiply
// and the shape is still the right shape, but the field's SLOPE is wrong by
// 1/s — so the "one pixel" ramp comes out 1/s pixels wide and the edges go
// mysteriously soft or hard.
//
// Offsetting a shape moves the COORDINATE SYSTEM, not the shape. sdCircle only
// knows how to draw a circle at the origin, so what it wants handed to it is
// "where am I relative to the circle's centre", which is pos - centre. Hence
// MINUS to move right and PLUS to move left; one offset used both ways pushes
// the pair apart symmetrically.
float circleField(in vec2 pos, in float shapeScale) {
  return sdCircle(pos / shapeScale - SHAPE_OFFSET, CIRCLE_RADIUS) * shapeScale;
}
float boxField(in vec2 pos, in float shapeScale) {
  return sdBox(pos / shapeScale + SHAPE_OFFSET, BOX_HALF_SIZE) * shapeScale;
}

// * THE SCENE FIELD — the smooth union, animated: the design panels 9 to 12
// draw. Two shapes in, ONE distance out; everything downstream reads only
// the number this returns.
//
//
// blendWidth is not a centre, it is the WIDTH of the blend band. It is a
// distance, so it has to live in the SAME space as the fields it is
// comparing — pos units, not design units. That is the whole job of the
// `* shapeScale`.
//
// The animated 0..1 factor is therefore read in DESIGN units: at 0 you get
// plain min() and the hard corner back; by 0.35 the join has a visible
// fillet; past about 0.6 the two shapes read as one blob. Drop the
// `* shapeScale` and blendWidth becomes several times the size of the whole
// shape, so smin never leaves the blob regime.
//
// Blending also GROWS the shape: smin pushes the surface out by up to
// blendWidth/4 beyond where min() would put it, which eats into the cell
// gutter. That bound is pessimistic — it only binds if the join sits on the
// outer boundary, and here it sits in the middle of the blob. Measured, the
// farthest reach grows about 3% at the peak of the cycle, which CELL_FILL =
// 0.8 absorbs without the copies ever touching.
//
// Animating it is the point — the shapes melt together and separate again,
// and nothing about either shape changes, only how their fields are joined.
//
// One edge to know about: this reaches exactly 0.0 once per cycle, and a
// blendWidth of 0 divides by zero inside smin. GLSL gives infinity rather
// than crashing, the clamp swallows it, and the result degrades to plain
// min() — so it looks fine. If it ever needs to be airtight, floor it:
// max(blendWidth, 1e-4).
float sceneField(in vec2 pos, in float shapeScale) {
  float blendWidth = (0.5 + 0.5 * sin(iTime)) * shapeScale;
  return smin(circleField(pos, shapeScale), boxField(pos, shapeScale), blendWidth);
}

// * COVERAGE — turn any distance field into a mask, with one pixel of
// anti-aliasing. 0 inside the thing, 1 outside it, a straight ramp across the
// crossing. Used for BOTH the fill and the outline, which is the point: if a
// new field ever needs its own bespoke masking formula, it is not really a
// distance field.
//
// What the ramp looks like across the edge, one pixel wide:
//
//   mask  1 |             ,-------------   fully outside
//           |           ,'
//        0.5|         ,'                   exactly on the edge
//           |       ,'
//         0 |-------'                      fully inside
//           +-------+---+-------
//              -0.5  0  +0.5   <- dist, measured in pixels
//
// Three ways to do this, cheapest last:
//   step(0.0, dist)                        jagged, no anti-aliasing at all
//   smoothstep(-onePixel, onePixel, dist)  centred, but two pixels wide
//   clamp(0.5 + dist / onePixel, 0., 1.)   one pixel, centred, and exact
//
// The 0.5 is what centres it, and panel 1's comment has the
// derivation: it IS the coverage of a straight edge, not an approximation that
// happens to look right.
float coverage(in float dist, in float onePixel) {
  return clamp(0.5 + dist / onePixel, 0.0, 1.0);
}

// * OUTLINE FIELD — exercise 8a. Note what this returns: a FIELD, not a mask.
// It is handed to coverage() like any other distance, and that is the whole
// lesson made structural.
//
// abs() on the FIELD is the sibling of abs() on the POSITION in sdBox. There it
// folded four corners into one; here it folds the field about its own zero, so
// every value becomes "how far from the edge", either side. The zero set does
// not move, which means abs(dist) is still a distance field, and the shape it
// describes is the original outline: a curve with no interior.
//
// Reading a slice straight through the shape, and plotting the field's value
// along the way. Three steps, three pictures:
//
//   dist            \                       /      positive outside
//                    \                     /
//        0  ----------\-------------------/------  zero ON the edge
//                      \                 /
//                       \_______________/          negative inside
//
//   abs(dist)       \       _________       /      the fold. The inside
//                    \    _/         \_    /       comes back up as
//        0  ----------V--/-------------\--V------  positive, and the two
//                                                   zeros are the two sides
//                                                   of the outline
//
//   abs(dist)       \      _________      /        the whole shape drops by
//   - thickness      \   _/         \_   /         the thickness, so it now
//        0  ----------\-/-------------\-/-------   crosses zero TWICE
//                      V               V
//                     [=]             [=]          below zero = ON the line
//
// Subtracting a thickness then inflates that curve into a band. The new zero
// set is where abs(dist) == thickness, one contour either side of the original
// edge, so the band is 2 * OUTLINE_PIXELS wide — the name undersells it by
// half. 5 pixels here draws a 10 pixel line.
//
// The thickness is in SCREEN space, so the line keeps its weight when
// CELLS_ACROSS changes and the shapes shrink underneath it — the same choice
// GLOW_PIXELS makes, for the same reason. The alternative is design space,
// multiplying by shapeScale, which keeps the line proportional to the artwork
// and lets it thin out as cells are added. Two different intentions; worth
// flipping between them once while changing CELLS_ACROSS.
float outlineField(in float dist, in float onePixel) {
  return abs(dist) - OUTLINE_PIXELS * onePixel;
}

// * GLOW — exercise 8b. Light that is brightest at the edge and fades with
// distance, which is just "turn a distance into a brightness".
//
// exp(-x) is the fade. It needs no more theory than four values:
//
//     x = 0  ->  1.00        x = 2  ->  0.14
//     x = 1  ->  0.37        x = 3  ->  0.05
//
// Starts at full, shrinks fast, never quite reaches zero — which is exactly
// why a glow looks soft instead of ending at a rim.
//
// The falloff sets how fast. It is ONE OVER A DISTANCE, so it is the units
// table read backwards: exp(-x) is about a third when x is 1, so
//
//     falloff = 1 / (the distance where you want a third left)
//
// Writing it as 1.0 / (GLOW_PIXELS * onePixel) puts that distance in SCREEN
// PIXELS, so the glow keeps its size in pixels whatever the window size and
// whatever CELLS_ACROSS is doing. GLOW_PIXELS is the dial; nothing else here
// needs touching.
//
// Getting this wrong the first time was instructive. `0.01 / onePixel` is the
// same formula — rewrite 0.01 as 1/100 and it reads "fade over 100 pixels" —
// but the gap between a shape's edge and its cell wall is only about 26 pixels
// here. A fade that needs 100 pixels in a space 26 pixels wide never gets
// going, so it came out as a flat wash rather than a glow. The formula was
// right; there was no room for the number. When a falloff seems to do nothing,
// measure the space it has before you change the maths.
//
// max(dist, 0.0) is not optional. Inside the shape the distance is NEGATIVE,
// the two minus signs cancel, and exp() of a big positive number explodes.
// Clamping says "treat everything inside as if it were on the edge".
//
// The consequence of that clamp is the thing to remember: this returns exactly
// 1.0 across the WHOLE INTERIOR, not just near the edge. It is only safe
// because paintLayers puts it down BEFORE the fill and lets the fill cover it.
// Painted after the fill instead, it adds GLOW_INTENSITY on top of shapeColor
// and the black interior reads as mid grey — measured 0.300 against 0.000.
// Same number, same field, different order.
float glowFrom(in float dist, in float onePixel) {
  float falloff = 1.0 / (GLOW_PIXELS * onePixel);
  return exp(-falloff * max(dist, 0.0));
}

// * CONTOUR RINGS (exercise 3) — the field made visible. cos() of the distance
// draws a contour every time the distance advances by 2*PI/CONTOUR_FREQ, so
// this is a topographic map of the very number every mask was built from.
//
// Since exercise 7 it also draws the SEAMS. The faint grid in the background is
// the contours failing to line up across a cell boundary, because the distance
// jumps there — each pixel only ever measured its own cell's copy. That is the
// "no longer a true distance" note made visible.
//
// CONTOUR_FREQ is in 1 / pos units, so the rings keep their spacing while the
// shapes shrink: more cells across means fewer rings on each shape. Divide it
// by shapeScale if you'd rather the rings belonged to the artwork than to the
// screen.
//
// Comment the call out in paintLayers whenever the rings fight the glow —
// they draw the same information, and the glow says it more loudly. They stay
// the cheapest debugging tool in the file for the moments you want to SEE the
// field rather than use it.
float contourRings(in float dist) {
  return CONTOUR_AMOUNT * cos(dist * CONTOUR_FREQ);
}

// * PAINT — masks first, then layers, back to front. Used whole by panel 12.
//
//
//   1. background   bgColor, the ground everything sits on
//   2. glow         light added around the shape              (add)
//   3. fill         the shape painted over the glow           (mix, by sign)
//   4. outline      ink painted over both                     (mix, by band)
//   5. contours     the field itself, drawn on top            (add)
//
// Stacked, with the viewer looking down from the top:
//
//        you
//         |
//         v
//     ~~~~~~~~~~~~~~~~~~~~~~~~   5. contours   drawn last, so on top
//     ========================   4. outline
//     ########################   3. fill
//     ::::::::::::::::::::::::   2. glow
//     ------------------------   1. background  painted first, so underneath
//
// Each layer can only cover what is already below it, never what comes after.
// That is why the glow sits UNDER the fill: the glow is 1.0 everywhere inside
// the shape, and letting the fill cover it is simpler than masking it out.
//
// Each step takes the picture so far and puts something on top of it. Read the
// mix() arguments off what each mask MEANS and the order writes itself: a mask
// here is always OUTSIDE-ness, 0 on the thing and 1 away from it, and
// mix(a, b, t) returns a at t = 0, so the thing being drawn is always the
// FIRST argument and "the picture so far" is the second.
//
// anything; every line is built out of the one distance handed in.
vec3 paintLayers(in float distToEdge, in float onePixel) {
  float fillMask = coverage(distToEdge, onePixel);
  float inkMask  = coverage(outlineField(distToEdge, onePixel), onePixel);
  float glow     = glowFrom(distToEdge, onePixel);

  // Start from the background and build upwards.
  vec3 color = bgColor;

  // Light, ADDED rather than mixed, because light adds. Before the fill on
  // purpose: glow is 1.0 everywhere inside the shape, and letting the fill
  // paint over it is cheaper and clearer than masking the glow.
  color += glow * outlineColor * GLOW_INTENSITY;

  // The shape itself. fillMask is outside-ness, so shapeColor takes the 0 end
  // and "everything painted so far" takes the 1 end — note that second
  // argument is `color`, not bgColor, which is what makes this a layer rather
  // than a fresh start. The ramp pixels land in between, and that partial blend
  // IS the anti-aliasing: coverage turned into color by a linear interpolation.
  color = mix(shapeColor, color, fillMask);

  // The ink, last, so it covers both the fill and the glow. That is what makes
  // a crisp line read against a soft halo; move it above the glow line and the
  // halo would wash over the ink instead.
  //
  // The first attempt at this line, kept because the mistake is instructive:
  //   color = mix(color, bgColor, inkMask);
  // Same mask, arguments the other way round, so it keeps the picture ON the
  // band and paints bgColor over everything else. That ERASES the fill instead
  // of painting ink, and the visible line is the leftover shapeColor from the
  // band's inner half — the outer half was already bgColor, which is why it
  // read as OUTLINE_PIXELS wide rather than twice that. It looks correct, and
  // its anti-aliasing genuinely is correct on both sides, but the line's color
  // stops being a choice and the fill cannot survive, because destroying the
  // fill is what draws the line. Worth switching between them once: same field,
  // same mask, two different pictures.
  color = mix(outlineColor, color, inkMask);

  // The field drawn on top of the picture. Comment out when it fights the glow.
  color += contourRings(distToEdge);

  return color;
}

// * SMALL PAINTERS shared by the panels. Each takes a distance and returns a
// colour, so a panel is "build a field, then paint it".
//
// paintFill is exercise 2's line: shapeColor on the inside, bgColor outside,
// one pixel of anti-aliased edge between. paintFillAndRings adds exercise 3's
// contours on top, so every combining panel also shows its field.
vec3 paintFill(in float dist, in float onePixel) {
  return mix(shapeColor, bgColor, coverage(dist, onePixel));
}
vec3 paintFillAndRings(in float dist, in float onePixel) {
  return paintFill(dist, onePixel) + contourRings(dist);
}

// The border goes on last, over everything, in every panel.
vec3 finishPanel(in vec3 color, in vec2 tileUv, in vec2 tilePixel) {
  return mix(color, borderColor, panelBorder(tileUv, tilePixel));
}

// * PANEL 0 — THE FIELD ITSELF (exercise 1).
//
// length(pos) is distance from the centre; subtracting a radius gives the
// signed distance to the circle's edge. The move that mattered: put the
// subtraction in the distance, not in the colour.
//
// Drawn raw, as grey: 0.5 + 0.5 * dist, so the edge is mid grey, the inside
// darker (negative) and the outside lighter (positive). Dark = negative =
// inside, the reading every later panel keeps.
vec3 panelField(in vec2 tileUv, in vec2 tilePixel) {
  vec2  pos  = panelPos(tileUv, tilePixel);
  float dist = sdCircle(pos, CIRCLE_RADIUS);
  return finishPanel(vec3(0.5 + 0.5 * dist), tileUv, tilePixel);
}

// * PANEL 1 — TURN THE SIGN INTO A MASK (exercise 2).
//
// step() first, to see the staircase that comes of every pixel being fully
// in or fully out, then a ramp about a pixel wide to soften it.
//
// WHERE THE 0.5 COMES FROM. Work in pixels: let t = distToEdge / onePixel,
// the signed distance measured in screen pixels. A pixel is SAMPLED at its
// centre but COVERS the range t-0.5 .. t+0.5, so for a straight edge the
// fraction of the pixel lying outside the shape is
//
//     t <= -0.5    pixel wholly inside    -> 0
//     t >= +0.5    pixel wholly outside   -> 1
//     in between   -> t + 0.5             (a straight line between the two)
//
// Read that back as an expression and it is exactly
//   clamp(0.5 + distToEdge / onePixel, 0.0, 1.0)
// a ramp one pixel wide, centred on the edge. Not an approximation that
// happens to look right: it IS the coverage of a straight edge, and the best
// a single sample per pixel can do. It's also cheaper than smoothstep.
//
// Both ways of getting it wrong are about where the ramp SITS, not how wide
// it is. Measured on the pixel that should read fully outside (255):
//   clamp(distToEdge / onePixel, ...)
//       ramp 0..1px, half a pixel outward. Gives 0 at the true edge where
//       0.5 is honest, and 128/255 here. Half a pixel of fat on every shape.
//   1.0 - smoothstep(0.0, 2*onePixel, distToEdge)
//       ramp entirely outside the shape: a full pixel of fat.
// smoothstep(-onePixel, onePixel, distToEdge) is centred, so unbiased, but
// spans two pixels rather than one — that extra pixel is why its edges look
// slightly softer.
//
// Done: greyscale became a two-color palette with
//   vec3 color = mix(shapeColor, bgColor, outsideMask);
// shapeColor first, because outsideMask is outside-ness. Keeping the shape
// dark preserves the "dark = negative = inside" reading the greyscale had, so the
// picture is still a view of the field rather than just a picture of a disc.
vec3 panelMask(in vec2 tileUv, in vec2 tilePixel) {
  vec2  pos      = panelPos(tileUv, tilePixel);
  float onePixel = panelOnePixel(tilePixel);
  float dist     = sdCircle(pos, CIRCLE_RADIUS);
  return finishPanel(paintFill(dist, onePixel), tileUv, tilePixel);
}

// * PANEL 2 — SEE THE FIELD (exercise 3).
//
// `color += 0.06 * cos(distToEdge * 10.0);` turns the invisible field into
// contour rings. Worth having done: from here on you are reasoning about a landscape
// you can't otherwise see, and around a box those contours show you the
// rounded corners the distance function produces.
//
// The details of the rings, and the seams they reveal once the domain is
// repeated, are written up at contourRings above.
vec3 panelContours(in vec2 tileUv, in vec2 tilePixel) {
  vec2  pos      = panelPos(tileUv, tilePixel);
  float onePixel = panelOnePixel(tilePixel);
  float dist     = sdCircle(pos, CIRCLE_RADIUS);
  return finishPanel(paintFillAndRings(dist, onePixel), tileUv, tilePixel);
}

// * PANEL 3 — A SECOND SHAPE, THE BOX (exercise 4).
//
// Written out step by step in sdBox above: fold, overshoot, outside term,
// inside term. The gotcha that cost time was not the maths but the argument:
// `halfSize` is measured from the centre out, so vec2(2.0) reaches far past
// the screen edge (pos only reaches 1.0 on the short axis), every pixel reads
// as inside, and you get a flat fill with no visible box at all.
//
// The rings show the field is NOT box-shaped outside the corners: they
// round off, because past a corner the nearest point of the box IS the
// corner. sdBox above explains why.
vec3 panelBox(in vec2 tileUv, in vec2 tilePixel) {
  vec2  pos      = panelPos(tileUv, tilePixel);
  float onePixel = panelOnePixel(tilePixel);
  float dist     = sdBox(pos, BOX_HALF_SIZE);
  return finishPanel(paintFillAndRings(dist, onePixel), tileUv, tilePixel);
}

// * PANEL 4 — UNION (exercise 5).
//
// Panels 4 to 7 put the same two fields through one combining operator
// each; only the one line that joins them changes.
//
//   union         min(a, b)    inside EITHER — the nearer surface wins
//   intersection  max(a, b)    inside BOTH   — the binding constraint wins
//   subtraction   max(a, -b)   inside a, outside b — negating b turns its
//                              inside into outside, then intersect with that
//
// Neither is a convention to memorise. distToEdge answers "how far to the
// nearest surface". For a UNION the nearest surface is whichever is closer,
// so the answer is the smaller number — min(). For an INTERSECTION you have
// to be inside both, and inside means negative, so the one that decides the
// answer is the LARGER (least negative) of the two — max(). Same question,
// run the other way round: union asks "nearest", intersection asks "worst".
//
// Both shapes live at once, each measured in its own frame. One SHAPE_OFFSET
// used as pos - offset for the circle and pos + offset for the box pushes
// them apart symmetrically — nicer than carrying two separate centres.
//
// Offsetting works by subtracting from pos first, because the shape function
// only knows the origin: sdCircle(pos - centre, radius) hands it "where am I
// relative to the circle's centre". MINUS to move in the PLUS direction —
// you're moving the coordinate system, not the shape.
vec3 panelUnion(in vec2 tileUv, in vec2 tilePixel) {
  vec2  pos        = panelPos(tileUv, tilePixel);
  float onePixel   = panelOnePixel(tilePixel);
  float shapeScale = fitToCell(2.0);            // the panel as one big cell
  float circleDist = circleField(pos, shapeScale);
  float boxDist    = boxField(pos, shapeScale);
  float dist       = min(circleDist, boxDist);
  return finishPanel(paintFillAndRings(dist, onePixel), tileUv, tilePixel);
}

// * PANEL 5 — INTERSECTION.
//
// INTERSECTION — the overlap only, so SHAPE_OFFSET now does double duty: it
// places the shapes AND decides how much of them survives. At 0.3 you get a
// rounded slab: the box's straight right edge, the circle's arc bulging out to
// the left, and the box's flat top and bottom in between. Every stretch of
// that outline belongs to whichever shape was the binding constraint there —
// max() choosing, made visible.
//
// Push the offset far enough apart and the intersection becomes EMPTY: no
// pixel is inside both, distToEdge is positive everywhere, and you get a
// blank background. That's a correct answer, not a bug — worth doing once so
// a blank screen doesn't read as breakage later.
//
// Honesty note for exercise 6: min() gives a true distance outside the
// shapes, but the max()-based operators only give a bound near the join —
// fine while you're thresholding it into a mask, but it matters the moment
// you use the field for a glow.
vec3 panelIntersection(in vec2 tileUv, in vec2 tilePixel) {
  vec2  pos        = panelPos(tileUv, tilePixel);
  float onePixel   = panelOnePixel(tilePixel);
  float shapeScale = fitToCell(2.0);            // the panel as one big cell
  float circleDist = circleField(pos, shapeScale);
  float boxDist    = boxField(pos, shapeScale);
  float dist       = max(circleDist, boxDist);
  return finishPanel(paintFillAndRings(dist, onePixel), tileUv, tilePixel);
}

// * PANEL 6 — SUBTRACTION, CIRCLE MINUS BOX.
//
// SUBTRACTION — a minus b, and it is intersection wearing a disguise.
//
// Negating a distance field turns the shape inside out. The boundary itself
// doesn't move (it's where the value is 0, and -0 is still 0); only the SIGN
// flips, so what was inside reads as outside. -boxDist therefore describes
// "everywhere except the box", with the box's own outline as its edge.
//
// Intersect a shape with that and you get "inside a, but outside b" — which
// is subtraction. Same max() as intersection, one sign flipped; there are
// really only two operators here, not three.
//
// The argument you DON'T negate is the one that survives. The negated one
// becomes the cutter, and the cut always carries the cutter's own edges,
// which is how you can read the result back:
//
//   max(circleDist, -boxDist)   circle survives, box cuts
//                               -> a disc with a square notch bitten out of
//                                  its left side; straight cut edges
//   max(-circleDist, boxDist)   box survives, circle cuts
//                               -> a slab with a round bite out of its right
//                                  side; curved cut edge
//
// Both were tried. The straight-vs-curved cut is the tell for which shape did
// the cutting.
vec3 panelCircleMinusBox(in vec2 tileUv, in vec2 tilePixel) {
  vec2  pos        = panelPos(tileUv, tilePixel);
  float onePixel   = panelOnePixel(tilePixel);
  float shapeScale = fitToCell(2.0);            // the panel as one big cell
  float circleDist = circleField(pos, shapeScale);
  float boxDist    = boxField(pos, shapeScale);
  float dist       = max(circleDist, -boxDist);   // circle survives, box cuts
  return finishPanel(paintFillAndRings(dist, onePixel), tileUv, tilePixel);
}

// * PANEL 7 — SUBTRACTION, BOX MINUS CIRCLE.
//
// The other order, so the two can be read side by side: here the box
// survives and the circle cuts, so the bite is ROUND, carrying the cutter's
// edge. Panel 6's comment has the full story.
vec3 panelBoxMinusCircle(in vec2 tileUv, in vec2 tilePixel) {
  vec2  pos        = panelPos(tileUv, tilePixel);
  float onePixel   = panelOnePixel(tilePixel);
  float shapeScale = fitToCell(2.0);            // the panel as one big cell
  float circleDist = circleField(pos, shapeScale);
  float boxDist    = boxField(pos, shapeScale);
  float dist       = max(-circleDist, boxDist);   // box survives, circle cuts
  return finishPanel(paintFillAndRings(dist, onePixel), tileUv, tilePixel);
}

// * PANEL 8 — MORPH, animated.
//
// MORPH — not a boolean, but worth knowing, and worth keeping around.
// mix() AVERAGES the two fields instead of choosing between them, so it
// MORPHS one shape into the other rather than combining them — the result is
// part circle, part box, sitting between the two positions. Animate the t and
// the circle flows into the box.
//
// Averaging two distance fields keeps the result well behaved enough to draw
// (neither field changes faster than 1 unit per unit of space, so the average
// doesn't either), which is why it looks plausible rather than broken.
//
// Detour worth recording: mix(a, b, 0.5) was tried here for intersection and
// is NOT one. It averages the fields rather than choosing between them, so
// it morphs the two shapes into a hybrid instead of intersecting them. A
// good accident — animate the t and you have shape tweening, which no
// boolean gives you.
vec3 panelMorph(in vec2 tileUv, in vec2 tilePixel) {
  vec2  pos        = panelPos(tileUv, tilePixel);
  float onePixel   = panelOnePixel(tilePixel);
  float shapeScale = fitToCell(2.0);            // the panel as one big cell
  float circleDist = circleField(pos, shapeScale);
  float boxDist    = boxField(pos, shapeScale);
  float dist       = mix(circleDist, boxDist, 0.5 + 0.5 * sin(iTime));
  return finishPanel(paintFillAndRings(dist, onePixel), tileUv, tilePixel);
}

// * PANEL 9 — SMOOTH UNION, animated (exercise 6).
//
// Worth looking at the contour rings wherever two shapes meet under any of
// the hard operators above. The value is continuous across the join but its
// SLOPE is not: the rings arrive as a V rather than a smooth curve, because
// min()/max() switch abruptly from one field to the other. That crease is
// what the smooth minimum below rounds off — and it is also why max() is only
// a distance BOUND near the join, not a true distance.
//
// This panel is the fix: sceneField above joins the two with smin, and the
// blend width breathes with time, so the hard crease of panel 4 appears and
// melts away once per cycle. The derivation is above smin, and what the
// blend width means is above sceneField.
vec3 panelSmoothUnion(in vec2 tileUv, in vec2 tilePixel) {
  vec2  pos        = panelPos(tileUv, tilePixel);
  float onePixel   = panelOnePixel(tilePixel);
  float dist       = sceneField(pos, fitToCell(2.0));
  return finishPanel(paintFillAndRings(dist, onePixel), tileUv, tilePixel);
}

// * PANEL 10 — OUTLINE (exercise 8a).
//
// abs(distToEdge) - thickness, through the same clamp ramp as the fill.
// An outline is just a shape whose SDF is built out of another shape's
// SDF, and abs() on the field is the same fold as abs() on the position
// back in sdBox.
//
// The part that was actually new: building the field and COMPOSING it
// into the picture are two separate decisions, and only the first one is
// maths. The field came out right first try; the compose line then said
// "erase everything off the band" rather than "paint ink on the band",
// which produces a correct-looking outline for the wrong reason and
// quietly costs you the choice of ink color and the option of keeping the
// fill. Fixed by swapping the mix() arguments and giving the ink its own
// palette entry; the erase version is kept commented beside it, because
// comparing the two is the lesson.
//
// The reusable habit: read mix()'s argument order off what the mask
// MEANS. Both masks in this file are outside-ness, so in both cases the
// thing being drawn goes first. Getting a plausible picture is not
// evidence that the reasoning was right.
//
// Also worth having hit: thickness is a distance, so it has a space, and
// screen space and design space behave differently the moment CELLS_ACROSS
// changes.
vec3 panelOutline(in vec2 tileUv, in vec2 tilePixel) {
  vec2  pos      = panelPos(tileUv, tilePixel);
  float onePixel = panelOnePixel(tilePixel);
  float dist     = sceneField(pos, fitToCell(2.0));
  float inkMask  = coverage(outlineField(dist, onePixel), onePixel);

  vec3 color = paintFill(dist, onePixel);         // the shape on the background
  color = mix(outlineColor, color, inkMask);      // ink painted over it
  return finishPanel(color, tileUv, tilePixel);
}

// * PANEL 11 — GLOW (exercise 8b).
//
// exp(-falloff * max(distToEdge, 0.0)), added rather than mixed so it
// reads as light. exp() is the fade; the clamp keeps the inside from
// exploding.
//
// The thing worth remembering is about UNITS, not about glows.
// The falloff is one over a distance, so a raw number is meaningless
// until you say what distance you mean. Written as
// 1.0 / (GLOW_PIXELS * onePixel) it becomes "fade over this many screen
// pixels", which is both readable and resolution-independent. The first
// attempt, 0.01 / onePixel, is the SAME formula asking for 100 pixels of
// fade in a gap only about 26 pixels wide — right idea, no room. When a
// falloff looks like it does nothing, check the space it has to work in
// before changing the formula.
//
// Second thing, and it cost a grey fill to notice: the clamp makes glow
// equal 1 across the whole interior, so adding it after the fill lifted
// the shape's color to GLOW_INTENSITY — a measured 0.300 where 0.000 was
// meant. Fixed by painting the glow onto the background BEFORE the fill
// and letting the fill cover what wasn't wanted. Ordering the layers is
// part of the design, not an afterthought, which is why paintLayers now
// separates computing the masks from painting them.
vec3 panelGlow(in vec2 tileUv, in vec2 tilePixel) {
  vec2  pos      = panelPos(tileUv, tilePixel);
  float onePixel = panelOnePixel(tilePixel);
  float dist     = sceneField(pos, fitToCell(2.0));

  vec3 color = bgColor;
  color += glowFrom(dist, onePixel) * outlineColor * GLOW_INTENSITY;   // light first
  color  = mix(shapeColor, color, coverage(dist, onePixel));           // fill covers it
  return finishPanel(color, tileUv, tilePixel);
}

// * PANEL 12 — REPEAT IT, AND EVERYTHING TOGETHER (exercise 7).
//
// The picture this scene used to be, whole: the domain folded into
// CELLS_ACROSS cells, the design fitted to each cell, the smooth union, and
// all the layers of paintLayers (glow, fill, outline, contours) at once.
//
// cellPos = pos - cellSize * floor(pos / cellSize + 0.5), then compute the
// shapes on cellPos. One fold turns one pair of shapes into a whole grid at
// no extra cost per pixel.
//
// What actually cost time was not the repeat line, which worked first try.
// Repetition WRAPS the coordinate; it does not scale anything. The shape
// constants still meant what they always meant, they were just now being
// measured against a cell instead of the screen — reach 0.9 into a budget of
// 0.35 — so every pixel landed inside something and the screen went solid.
// A correct picture of the wrong request.
//
// The fix was to stop writing the constants twice. designReach measures what
// the design asks for, fill says how much of the cell to spend, and
// shapeScale is the ratio; the shapes are then drawn with the scaling idiom
// sdShape(pos / s) * s. Now CELLS_ACROSS is a zoom control that cannot break
// the layout, which is the property to aim for whenever one number is
// derived from another.
//
// Two smaller things worth keeping:
//   - count cells, don't measure them. pos is 2.0 wide, so cellSize = 0.5 is
//     a quarter of the short side, not a half. CELLS_ACROSS says what it
//     means, and odd values end flush against the screen edge because
//     boundaries land at (k + 0.5) * cellSize.
//   - the result is not a true distance any more. Each pixel only knows its
//     own cell. Fine for a mask, visible in the contours at every seam, and
//     it would break a glow or a raymarch.
//
// THEN the point of putting these after exercise 7: the glow draws hard
// seams along every cell boundary. That is not a bug in the glow, it is the
// repetition caveat cashing out. A mask only looks at the sign right next to
// the shape; a glow looks at the value far from it, out where the field is
// lying about which copy is nearest. The contour rings were already telling
// you this quietly. Two honest responses: lower fill so the glow has decayed
// to nothing before it reaches the wall, or raise the falloff. Neither is a
// fix, they just keep the lie below the noise floor. Worth knowing which one
// you are doing.
vec3 panelEverything(in vec2 tileUv, in vec2 tilePixel) {
  vec2  pos        = panelPos(tileUv, tilePixel);
  float onePixel   = panelOnePixel(tilePixel);

  float cellSize   = 2.0 / CELLS_ACROSS;
  vec2  cellPos    = repeatDomain(pos, cellSize);
  float shapeScale = fitToCell(cellSize);
  float distToEdge = sceneField(cellPos, shapeScale);

  return finishPanel(paintLayers(distToEdge, onePixel), tileUv, tilePixel);
}

// * PANEL 13 — GIVE EACH CELL AN IDENTITY (exercise 9).  [your turn]
//
// Start from a copy of panel 12.
//
// Right now every cell is identical, which is the giveaway that it is a
// tiling rather than a drawing. The fix is already sitting inside the repeat
// line: floor(pos / cellSize + 0.5) IS the integer coordinate of the cell,
// so pull it out into a `cellId` and you have a per-cell value for free.
//
// Turn it into a number to vary things with:
//   float rnd = fract(sin(dot(cellId, vec2(127.1, 311.7))) * 43758.5453);
// Not real randomness — a hash. Same cell, same value, every frame, which is
// what you want; a per-cell rand() that flickered would be useless.
//
// Then spend it. Easiest first: offset the blend phase per cell so the
// shapes melt out of step with each other (rnd * 6.283 added inside the
// sin in sceneField, which means giving sceneField a phase parameter).
// Then rotation, which needs a 2x2:
//   float a = rnd * 6.283;
//   mat2 rot = mat2(cos(a), -sin(a), sin(a), cos(a));
// and rotate cellPos before handing it to sceneField. That second half is
// really the first step of transforms, panel 15's subject.
//
// Two things to notice when you do. A rotation is orthonormal, so it does
// not change distances: unlike shapeScale, there is nothing to multiply back
// on the way out. And rotating cannot break the packing, because designReach
// is a bounding CIRCLE and a circle is the one bound rotation leaves alone.
// That was luck at the time; it is a reason now.
vec3 panelCellIdentity(in vec2 tileUv, in vec2 tilePixel) {
  return finishPanel(todoColor, tileUv, tilePixel);
}

// * PANEL 14 — DROP SHADOW (exercise 10).  [your turn]
//
// Start from a copy of panel 11, the glow: a shadow is its dark, offset
// twin.
//
// A shadow is the glow with three deliberate changes: it is DARK instead of
// light, it is OFFSET instead of centred, and it goes UNDERNEATH instead of
// on top. Dark and underneath are easy. The offset is the interesting part.
//
// distToEdge says how far you are from the edge but not WHICH WAY, so there
// is no way to nudge a glow sideways by editing that number. Direction has
// to come from asking the question from somewhere else — the same move as
// SHAPE_OFFSET. Measure the field at a shifted position:
//
//   vec2  shadowOffset  = vec2(10.0, -10.0) * onePixel;  // right and DOWN
//   float shadowPixels  = 8.0;
//   float shadowFalloff = 1.0 / (shadowPixels * onePixel);
//   float shadowDist    = sceneField(pos - shadowOffset, shapeScale);
//   float shadow = exp(-shadowFalloff * max(shadowDist, 0.0));
//
// (Before the gallery this needed the circle, the box and smin written out
// a second time. sceneField now wraps all three, so the second question is
// one call with a shifted position.)
//
// Minus to move plus, as always. y is up in this space, so a negative y
// throws the shadow downward.
//
// Then it goes in FIRST, before the fill, and it multiplies instead of adds:
//   vec3 color = bgColor;
//   color *= 1.0 - shadowStrength * shadow;
// That one character, *= instead of +=, is the whole difference between a
// shadow and a glow: multiplying by less than 1 takes light away, adding
// puts light in.
//
// One honest cost: the field is evaluated twice per pixel, because a second
// question genuinely was asked — that is the price of direction. (In a
// repeated version, like panel 12, each cell would also cast its own shadow
// and clip it at the seam like everything else does.)
vec3 panelDropShadow(in vec2 tileUv, in vec2 tilePixel) {
  return finishPanel(todoColor, tileUv, tilePixel);
}

// * PANEL 15 — TRANSFORMS.  [next subject]
//
// Moving, scaling and rotating space before a shape is drawn, The Book of
// Shaders chapter 8. Saved for after exercises 9 and 10: exercise 9's
// rotation already needs it, so it may well start there.
vec3 panelTransforms(in vec2 tileUv, in vec2 tilePixel) {
  return finishPanel(todoColor, tileUv, tilePixel);
}

// * DISPATCH — panel index in, colour out.
vec3 drawPanel(in int index, in vec2 tileUv, in vec2 tilePixel) {
  if (index == 0)  return panelField(tileUv, tilePixel);
  if (index == 1)  return panelMask(tileUv, tilePixel);
  if (index == 2)  return panelContours(tileUv, tilePixel);
  if (index == 3)  return panelBox(tileUv, tilePixel);
  if (index == 4)  return panelUnion(tileUv, tilePixel);
  if (index == 5)  return panelIntersection(tileUv, tilePixel);
  if (index == 6)  return panelCircleMinusBox(tileUv, tilePixel);
  if (index == 7)  return panelBoxMinusCircle(tileUv, tilePixel);
  if (index == 8)  return panelMorph(tileUv, tilePixel);
  if (index == 9)  return panelSmoothUnion(tileUv, tilePixel);
  if (index == 10) return panelOutline(tileUv, tilePixel);
  if (index == 11) return panelGlow(tileUv, tilePixel);
  if (index == 12) return panelEverything(tileUv, tilePixel);
  if (index == 13) return panelCellIdentity(tileUv, tilePixel);
  if (index == 14) return panelDropShadow(tileUv, tilePixel);
  return panelTransforms(tileUv, tilePixel);
}

// * THE GRID — the same as levels 1.1 and 1.2, just 4 x 4.
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
  vec2 uv        = fragCoord / iResolution.xy;          // 0..1 across the window
  vec2 grid      = vec2(PANELS_ACROSS, PANELS_DOWN);
  vec2 cell      = uv * grid;
  vec2 tileId    = floor(cell);                         // which panel
  vec2 tileUv    = fract(cell);                         // where inside it, 0..1
  vec2 tilePixel = grid / iResolution.xy;               // one screen pixel, in panel units

  // Reading order, 0 top-left: GL's y points up, so the row is flipped.
  int index = int(tileId.x) + int((PANELS_DOWN - 1.0) - tileId.y) * int(PANELS_ACROSS);

  fragColor = vec4(drawPanel(index, tileUv, tilePixel), 1.0);
}

// STUCK? `pnpm test:shaders` will tell you about syntax and type errors without
// you having to hunt for a blank screen in the browser.
