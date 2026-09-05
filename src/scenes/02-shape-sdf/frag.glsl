// Level 2 — signed distance fields. Exercises 1 to 7 done.
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
// Where this is now: `distToEdge` combines a circle and a box — currently a
// SMOOTH union with an animated blend width — and the whole pair is REPEATED
// across the screen by folding the coordinate into a cell. The hard union,
// intersection, both subtraction orders and a morph all sit commented beside
// it, and exactly ONE of them may be live at a time: they all declare
// `float distToEdge`, so uncommenting a second one is a redefinition error and
// the shader doesn't compile at all. That shows up as a blank canvas rather
// than a wrong picture, which is easy to misread as "the operator broke".
// `pnpm test:shaders` names the line.
// `outsideMask` is built from its SIGN, 0 where distToEdge is negative
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

// SMOOTH MINIMUM (the polynomial one). A union that fillets its own join
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
// smooth subtraction come from the same function.
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

  // REPEAT THE DOMAIN. The last of the coordinate tricks, and the same move as
  // offsetting and folding: nothing is copied, the COORDINATE is wrapped.
  //
  //   floor(pos / cellSize + 0.5)   round-to-nearest — the index of the cell
  //                                 centre nearest this pixel
  //   * cellSize                    that centre's position
  //   pos - (...)                   where I am RELATIVE to my own cell centre
  //
  // so cellPos only ever spans -cellSize/2 .. +cellSize/2. The + 0.5 is what
  // centres a cell on the origin; a plain floor() would put a cell CORNER
  // there instead. One fold, no loop: a thousand copies cost what one costs.
  //
  // COUNT cells rather than measure them. pos spans -1..1 on the short axis, so
  // that axis is 2.0 units wide, which makes a hand-written cellSize confusing:
  // 0.5 is not "half", it is a quarter of the short side. Deriving it from
  // cellsAcross puts the number you actually care about on the left.
  //
  // Odd counts end flush. Cell boundaries land at (k + 0.5) * cellSize, so they
  // coincide with the screen edge at 1.0 only when cellsAcross is odd; an even
  // count slices the top and bottom rows in half. 3 is odd. The long axis is a
  // different width, so it gets sliced either way.
  //
  // The price: this is no longer a true distance field. A pixel measures only
  // against its OWN cell's copy, never the neighbour that might be nearer. That
  // is invisible in the mask (which only cares about the sign near the shape,
  // and the shape is nowhere near the seam) but it is visible in the contour
  // rings, and it would break a glow. See the note by the cos() line below.
  float cellsAcross = 3.0;
  float cellSize = 2.0 / cellsAcross;   // pos spans -1..1, so 2.0 wide
  vec2 cellPos = pos - cellSize * floor(pos / cellSize + 0.5);

  // FIT THE ARTWORK TO THE CELL, instead of hand-tuning it to match.
  //
  // Repetition wraps the coordinate; it does not SHRINK anything. So the first
  // attempt kept radius 0.6 and offset 0.3, which reach 0.9 from the design
  // origin, and posted them into a cell with only cellSize/2 to spend. Every
  // pixel came out inside something and the screen went solid. Nothing was
  // wrong with the repeat line; the constants were simply written in the wrong
  // space.
  //
  // Which is the general lesson: every constant here lives in exactly ONE
  // space, and mixing them is where the bugs are.
  //
  //   screen pixels   onePixel                 must never follow cellSize
  //   pos units       cellSize, distToEdge     -1..1 on the short axis
  //   design units    the three below          whatever reads nicely
  //
  // The design, in its own units. These are the same numbers from exercises 4
  // and 5, untouched — that is the point. They still say "a circle 0.6 from its
  // centre"; they just no longer need to know how big a cell is.
  vec2 shapeOffset = vec2(0.3, 0.0);
  float circleRadius = 0.6;
  vec2 boxHalfSize = vec2(0.6, 0.4);

  // How far the design reaches from its own origin: the radius of a bounding
  // circle around everything in it. For the disc that is centre distance plus
  // radius. For the box it is the far CORNER, which is why it is
  // length(shapeOffset + boxHalfSize) and not shapeOffset.x + boxHalfSize.x —
  // those happen to agree only because this offset is axis-aligned.
  //
  // A bounding circle is conservative for a square cell, since the cell's
  // corners sit further out than its walls, so this packs slightly looser than
  // it has to. It is one line, and it stays correct if the design ever rotates.
  float designReach = max(length(shapeOffset) + circleRadius,
                          length(shapeOffset + boxHalfSize));

  // The only layout knob. 1.0 means the bounding circles of neighbouring copies
  // exactly touch; 0.8 spends 80% of the budget and leaves a gutter.
  float fill = 0.8;

  // Budget over demand: half a cell is what there is, designReach is what was
  // asked for.
  float shapeScale = fill * 0.5 * cellSize / designReach;

  // SCALING AN SDF: divide the position going in, multiply the distance coming
  // out.
  //
  //    d = sdShape(pos / s, params) * s
  //
  // The divide zooms the shape. The multiply puts the answer back into pos
  // units, which is what keeps onePixel and the AA ramp meaningful. Forget the
  // multiply and the shape is still the right shape, but the field's SLOPE is
  // wrong by 1/s — so the "one pixel" ramp comes out 1/s pixels wide and the
  // edges go mysteriously soft or hard.
  vec2 scaledPos = cellPos / shapeScale;

  float circleDist = sdCircle(scaledPos - shapeOffset, circleRadius) * shapeScale;
  float boxDist    = sdBox(scaledPos + shapeOffset, boxHalfSize)   * shapeScale;

  // The test that this is wired up properly: change cellsAcross on its own and
  // the picture should re-tile with every shape keeping its proportions and its
  // share of the cell. Measured across three cell sizes, the fraction of each
  // cell covered by the artwork stayed identical to three decimal places.


  // * COMBINE. Only one line changes between the three booleans; both fields
  // above stay exactly as they are. Only ONE `float distToEdge = ...` may be
  // uncommented at a time — two is a redefinition error, not a picture.
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

  // float distToEdge = min(circleDist, boxDist);   // union

  // * INTERSECTION — the overlap only, so shapeOffset now does double duty: it
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
  
  // float distToEdge = max(circleDist, boxDist);

  // * SUBTRACTION — a minus b, and it is intersection wearing a disguise.
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

  // float distToEdge = max(circleDist, -boxDist);
  // float distToEdge = max(-circleDist, boxDist);

  // * NOT a boolean, but worth knowing, and worth keeping around:
  // mix() AVERAGES the two fields instead of choosing between them, so it
  // MORPHS one shape into the other rather than combining them — the result is
  // part circle, part box, sitting between the two positions. Animate the t and
  // the circle flows into the box:

  // float distToEdge = mix(circleDist, boxDist, 0.5);

  // Averaging two distance fields keeps the result well behaved enough to draw
  // (neither field changes faster than 1 unit per unit of space, so the average
  // doesn't either), which is why it looks plausible rather than broken.
  
  // float distToEdge = mix(circleDist, boxDist, 0.5 + 0.5 * sin(iTime));

  // Worth looking at the contour rings wherever two shapes meet. The value is
  // continuous across the join but its SLOPE is not: the rings arrive as a V
  // rather than a smooth curve, because min()/max() switch abruptly from one
  // field to the other. That crease is what exercise 6's smooth minimum rounds
  // off — and it is also why max() is only a distance BOUND near the join,
  // not a true distance.

  // * SOFTEN THE JOIN — a union whose seam is filleted rather than creased.
  //
  // Renamed from softenCentre: k isn't a centre, it's the WIDTH of the blend
  // band. It is a distance, so it has to live in the SAME space as the fields
  // it is comparing — which since exercise 7 means pos units, not design
  // units. That is the whole job of the `* shapeScale` below.
  //
  // The animated 0..1 factor is therefore read in DESIGN units: at 0 you get
  // plain min() and the hard corner back; by 0.35 the join has a visible
  // fillet; past about 0.6 the two shapes read as one blob. Drop the
  // `* shapeScale` and k becomes several times the size of the whole shape, so
  // smin never leaves the blob regime.
  //
  // Blending also GROWS the shape: smin pushes the surface out by up to k/4
  // beyond where min() would put it, which eats into the cell gutter. That
  // bound is pessimistic — it only binds if the join sits on the outer
  // boundary, and here it sits in the middle of the blob. Measured, the
  // farthest reach grows about 3% at the peak of the cycle, which fill = 0.8
  // absorbs without the copies ever touching.
  //
  // Animating it is the point — the shapes melt together and separate again,
  // and nothing about either shape changes, only how their fields are joined.
  //
  // Watch the contour rings while it moves: the V-shaped kink at the join
  // rounds off as blendWidth grows. That kink is what this whole exercise was
  // about.
  //
  // One edge to know about: this reaches exactly 0.0 once per cycle, and k = 0
  // divides by zero inside smin. GLSL gives infinity rather than crashing, the
  // clamp swallows it, and the result degrades to plain min() — so it looks
  // fine. If it ever needs to be airtight, floor it: max(blendWidth, 1e-4).
  float blendWidth = (0.5 + 0.5 * sin(iTime)) * shapeScale;
  float distToEdge = smin(circleDist, boxDist, blendWidth);

  // * Three ways to turn the sign into a mask, cheapest last. All of them read
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
  //
  // Since exercise 7 it also draws the SEAMS. That faint grid in the background
  // is the contours failing to line up across a cell boundary, because the
  // distance jumps there — each pixel only ever measured its own cell's copy.
  // It is the "no longer a true distance" note made visible, and it is exactly
  // the artifact a glow would turn into a hard line.
  //
  // The 10.0 is in pos units, so the rings keep their spacing while the shapes
  // shrink: more cells across means fewer rings on each shape. Divide it by
  // shapeScale if you'd rather the rings belonged to the artwork than to the
  // screen. Worth deciding on purpose — it is the last constant in the file
  // that hasn't been assigned to a space.
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
// 5. COMBINE THEM.  [done]
//    Both shapes live at once, each measured in its own frame. One shapeOffset
//    used as pos - offset for the circle and pos + offset for the box pushes
//    them apart symmetrically — nicer than carrying two separate centres.
//
//    Detour worth recording: mix(a, b, 0.5) was tried here for intersection and
//    is NOT one. It averages the fields rather than choosing between them, so
//    it morphs the two shapes into a hybrid instead of intersecting them. A
//    good accident — animate the t and you have shape tweening, which no
//    boolean gives you.
//
//    Subtraction done too, both orders. Negating a field flips inside and
//    outside without moving the boundary, so max(a, -b) reads as "inside a,
//    outside b". The argument left un-negated survives; the negated one cuts,
//    and the cut carries the cutter's edges — a square notch when the box cuts,
//    a round bite when the circle does. Subtraction is intersection with one
//    sign flipped, so the three operators are really two.
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
// 6. SOFTEN THE JOIN.  [done]
//    smin() replaces min(), and k is animated with iTime so the shapes melt
//    together and apart. Full derivation lives above the function; the short
//    version is that it is two terms — mix() to stop the sudden hand-over
//    between fields, and a -k*h*(1-h) parabola that adds material only near
//    the tie, rounding the corner. Both vanish more than k away from the join,
//    so it is exactly min() elsewhere.
//
//    The reusable idea: k is a distance in the same units as the field, so a
//    blend width is something you can reason about in the same space as radii
//    and offsets. And smax(a,b,k) = -smin(-a,-b,k) gives smooth intersection
//    and subtraction for free.
//
// 7. REPEAT IT, free of charge.  [done]
//    cellPos = pos - cellSize * floor(pos / cellSize + 0.5), then compute the
//    shapes on cellPos. One fold turns one pair of shapes into a whole grid at
//    no extra cost per pixel.
//
//    What actually cost time was not the repeat line, which worked first try.
//    Repetition WRAPS the coordinate; it does not scale anything. The shape
//    constants still meant what they always meant, they were just now being
//    measured against a cell instead of the screen — reach 0.9 into a budget of
//    0.35 — so every pixel landed inside something and the screen went solid.
//    A correct picture of the wrong request.
//
//    The fix was to stop writing the constants twice. designReach measures what
//    the design asks for, fill says how much of the cell to spend, and
//    shapeScale is the ratio; the shapes are then drawn with the scaling idiom
//    sdShape(pos / s) * s. Now cellsAcross is a zoom control that cannot break
//    the layout, which is the property to aim for whenever one number is
//    derived from another.
//
//    Two smaller things worth keeping:
//      - count cells, don't measure them. pos is 2.0 wide, so cellSize = 0.5 is
//        a quarter of the short side, not a half. cellsAcross says what it
//        means, and odd values end flush against the screen edge because
//        boundaries land at (k + 0.5) * cellSize.
//      - the result is not a true distance any more. Each pixel only knows its
//        own cell. Fine for a mask, visible in the contours at every seam, and
//        it would break a glow or a raymarch.
//
// STUCK? `pnpm test:shaders` will tell you about syntax and type errors without
// you having to hunt for a blank screen in the browser.
