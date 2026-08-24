// Level 2 — signed distance fields. Exercises 1 and 2 done; 3 onward below.
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
// Where this is now: `distToEdge` is the union of a circle and a box, and
// `outsideMask` is built from its SIGN — 0 where distToEdge is negative
// (inside), 1 where it's positive (outside), with a one-pixel ramp across the
// crossing. Nothing is flipped on purpose, so the picture reads straight off
// the line above instead of asking you to invert it in your head. The palette
// keeps that reading by putting the dark color inside. The one consequence to
// hold on to: `outsideMask` really means "outside-ness", which is why
// shapeColor is the FIRST argument to mix().
//
// A worked solution is parked at src/_parked/02-shape-sdf-reference/ — it won't
// appear in the sidebar. Try not to open it until yours runs.

// The palette, at global scope. GLSL ES 1.00 permits that only because both
// initialisers are constant expressions; a global initialised from a uniform or
// a function call would not compile. Saying `const` states that intent and lets
// the compiler treat them as literals:
//    const vec3 shapeColor = vec3(0.0);
vec3 shapeColor = vec3(0.0, 0.0, 0.0);
vec3 bgColor = vec3(0.149,0.141,0.912);

float sdCircle(in vec2 pos, in float radius)
{
  // The easy one: distance from the origin, shifted so that 0 lands on the rim.
  // sdBox below is the same idea, only harder to see.
  return length(pos) - radius;
}

// halfSize is measured out from the CENTRE, so vec2(0.6, 0.4) is a box 1.2 wide
// and 0.8 tall in pos units — not 0.6 x 0.4. That catches everyone once, and
// it's why an over-large halfSize fills the whole screen.
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

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
  // Normalise by the SHORT axis, so it always spans -1..1 and radius reads
  // directly as a fraction of it: radius = 1.0 touches the short edges, 0.6
  // makes the circle 60% of the short side. Dividing by iResolution.y instead
  // would fit to the height only; min() here is CSS object-fit: contain, and
  // max() would be cover.
  float shortSide = min(iResolution.x, iResolution.y);
  vec2  pos       = (2.0 * fragCoord - iResolution.xy) / shortSide;
  // one screen pixel, in pos units; must use the same divisor as pos
  float onePixel  = 2.0 / shortSide;

  // TWO fields now, one per shape. Nothing downstream changes: the mask, the mix
  // and the contour rings all still read the single `distToEdge` below. That is
  // the payoff of having built the field into a variable back in exercise 1 —
  // adding a shape stays a local edit.

  // Offsetting a shape moves the COORDINATE SYSTEM, not the shape. sdCircle only
  // knows how to draw a circle at the origin, so what it wants handed to it is
  // "where am I relative to the circle's centre", which is pos - centre. Hence
  // MINUS to move right and PLUS to move left; one offset used both ways pushes
  // the pair apart symmetrically.
  vec2 shapeOffset = vec2(0.55, 0.0);

  float radius = 0.6;
  float circleDist = sdCircle(pos - shapeOffset, radius); // circle, to the right

  // halfSize is measured from the centre out, so this box is 1.2 x 0.8 in pos units.
  vec2 halfSize = vec2(0.6, 0.4);
  float boxDist = sdBox(pos + shapeOffset, halfSize);     // box, to the left

  // UNION. Not a convention to memorise: distToEdge answers "how far to the
  // nearest surface", and with two shapes the nearest surface is whichever is
  // closer — so the answer is the smaller of the two. Union is min() because
  // NEAREST is min().
  //
  // Worth looking at the contour rings where the shapes meet. The value is
  // continuous across the join but its SLOPE is not: the rings arrive as a V
  // rather than a smooth curve, because min() switches abruptly from one field
  // to the other. That crease is what exercise 6's smooth minimum rounds off.
  float distToEdge = min(circleDist, boxDist);

  // Three ways to turn the sign into a mask, cheapest last. All of them read
  // 0 inside and 1 outside, matching the convention at the top of the file.

  // step will have jagged edge
  // float outsideMask = step(0.0, distToEdge);

  // smoothstep in the +-pixel range to have antialiasing
  // float outsideMask = smoothstep(-onePixel, onePixel, distToEdge);

  // cheapest, and exactly right: a one-pixel ramp centred on the edge.
  // The 0.5 is what centres it — exercise 2 below has the derivation.
  float outsideMask = clamp(0.5 + distToEdge / onePixel, 0.0, 1.0);

  // mix(a, b, t) is a + (b - a) * t: t = 0 gives a, t = 1 gives b. Since
  // outsideMask is outside-ness, shapeColor takes the 0 end and bgColor the 1
  // end. The ramp pixels land in between, and that partial blend IS the
  // anti-aliasing — coverage turned into color by a linear interpolation.
  vec3 color = mix(shapeColor, bgColor, outsideMask);

  // Exercise 3: the field made visible. cos() of the distance draws a contour
  // every time distToEdge advances by 2*PI/10, so this is a topographic map of
  // the very number the mask above was built from.
  color += 0.06 * cos(distToEdge * 10.0);

  fragColor = vec4(color, 1.0);
}

// ---------------------------------------------------------------------------
// EXERCISES — roughly in order. Each builds on the last.
// ---------------------------------------------------------------------------
//
// 1. MAKE IT A CIRCLE.  [done]
//    `length(pos)` is distance from the centre; subtracting a radius gives the
//    signed distance to the circle's edge. The move that mattered: put the
//    subtraction in `distToEdge`, not in the color.
//
// 2. TURN THE SIGN INTO A MASK.  [done]
//    step() first, to see the staircase that comes of every pixel being fully
//    in or fully out, then a ramp about a pixel wide to soften it.
//
//    WHERE THE 0.5 COMES FROM. Work in pixels: let t = distToEdge / onePixel,
//    the signed distance measured in screen pixels. A pixel is SAMPLED at its
//    centre but COVERS the range t-0.5 .. t+0.5, so for a straight edge the
//    fraction of the pixel lying outside the shape is
//
//        t <= -0.5    pixel wholly inside    -> 0
//        t >= +0.5    pixel wholly outside   -> 1
//        in between   -> t + 0.5             (a straight line between the two)
//
//    Read that back as an expression and it is exactly
//      clamp(0.5 + distToEdge / onePixel, 0.0, 1.0)
//    a ramp one pixel wide, centred on the edge. Not an approximation that
//    happens to look right: it IS the coverage of a straight edge, and the best
//    a single sample per pixel can do. It's also cheaper than smoothstep.
//
//    Both ways of getting it wrong are about where the ramp SITS, not how wide
//    it is. Measured on the pixel that should read fully outside (255):
//      clamp(distToEdge / onePixel, ...)
//          ramp 0..1px, half a pixel outward. Gives 0 at the true edge where
//          0.5 is honest, and 128/255 here. Half a pixel of fat on every shape.
//      1.0 - smoothstep(0.0, 2*onePixel, distToEdge)
//          ramp entirely outside the shape: a full pixel of fat.
//    smoothstep(-onePixel, onePixel, distToEdge) is centred, so unbiased, but
//    spans two pixels rather than one — that extra pixel is why its edges look
//    slightly softer.
//
//    Done: greyscale became a two-color palette with
//      vec3 color = mix(shapeColor, bgColor, outsideMask);
//    shapeColor first, because outsideMask is outside-ness. Keeping the shape
//    dark preserves the "dark = negative = inside" reading the greyscale had, so the
//    picture is still a view of the field rather than just a picture of a disc.
//
// 3. SEE THE FIELD ITSELF.  [done]
//    `color += 0.06 * cos(distToEdge * 10.0);` turns the invisible field into
//    contour rings. Worth having done: from here on you are reasoning about a landscape
//    you can't otherwise see, and around a box those contours show you the
//    rounded corners the distance function produces.
//
// 4. ADD A SECOND SHAPE — A BOX.  [done]
//    Written out step by step in sdBox above: fold, overshoot, outside term,
//    inside term. The gotcha that cost time was not the maths but the argument:
//    `halfSize` is measured from the centre out, so vec2(2.0) reaches far past
//    the screen edge (pos only reaches 1.0 on the short axis), every pixel reads
//    as inside, and you get a flat fill with no visible box at all.
//
// 5. COMBINE THEM.  [union done]
//    Both shapes now live at once, each measured in its own frame, combined with
//    min(). One shapeOffset used as pos - offset for the circle and pos + offset
//    for the box pushes them apart symmetrically — nice, and cheaper than
//    carrying two separate offsets.
//
//    Three operators, and only the last line changes between them:
//      union         min(a, b)
//      intersection  max(a, b)
//      subtraction   max(a, -b)      <- b punches a hole in a
//    Still to try: the other two. Negating the OTHER argument swaps which shape
//    does the cutting.
//
//    Offsetting works by subtracting from pos first, because the shape function
//    only knows the origin: sdCircle(pos - centre, radius) hands it "where am I
//    relative to the circle's centre". MINUS to move in the PLUS direction —
//    you're moving the coordinate system, not the shape.
//
//    Honesty note for exercise 6: min() gives a true distance outside the
//    shapes, but the max()-based operators only give a bound near the join —
//    fine while you're thresholding it into a mask, but it matters the moment
//    you use the field for a glow.
//
// 6. SOFTEN THE JOIN.
//    Swap min() for a smooth minimum and the two shapes melt together instead
//    of creasing:
//      float smin(float a, float b, float k) {
//        float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
//        return mix(b, a, h) - k * h * (1.0 - h);
//      }
//    Animate k with iTime and watch them merge and separate.
//
// 7. REPEAT IT, free of charge.
//    The centred-repeat line from 01's notes works here unchanged (cellSize is
//    the spacing, cellPos is where you are inside one cell):
//      float cellSize = 0.7;
//      vec2 cellPos = pos - cellSize * floor(pos / cellSize + 0.5);
//    Compute your circle on `cellPos` instead of `pos` and one circle becomes a grid of
//    them. Same cost per pixel, however many you "draw".
//
// STUCK? `pnpm test:shaders` will tell you about syntax and type errors without
// you having to hunt for a blank screen in the browser.
