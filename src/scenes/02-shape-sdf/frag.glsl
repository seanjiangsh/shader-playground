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
// Where this is now: `d` is a real circle SDF and `fill` is a mask built from
// the SIGN of d — 0 where d is negative (inside), 1 where it's positive
// (outside), with a one-pixel ramp across the crossing. Nothing is flipped on
// purpose, so the picture reads straight off the line above instead of asking
// you to invert it in your head. The palette keeps that reading by putting the
// dark color inside. The one consequence to hold on to: `fill` really means
// "outside-ness", which is why shapeColor is the FIRST argument to mix().
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

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
  // Normalise by the SHORT axis, so it always spans -1..1 and r reads directly
  // as a fraction of it: r = 1.0 touches the short edges, r = 0.6 makes the
  // circle 60% of the short side. Dividing by iResolution.y instead would fit
  // to the height only; min() here is CSS object-fit: contain, max() is cover.
  float minAxis = min(iResolution.x, iResolution.y);
  vec2  p  = (2.0 * fragCoord - iResolution.xy) / minAxis;
  float px = 2.0 / minAxis; // one screen pixel in p units; must use the same divisor as p

  // The field: distance to the circle's edge, signed. Built into d itself, not
  // into the color, because everything downstream reads d and nothing reads
  // the color line.
  float r = 0.6;
  float d = length(p) - r;

  // Three ways to turn the sign into a mask, cheapest last. All of them read
  // 0 inside and 1 outside, matching the convention at the top of the file.

  // step will have jagged edge
  // float fill = step(0.0, d);

  // smoothstep in the +-pixel range to have antialiasing
  // float fill = smoothstep(-px, px, d);

  // cheapest, and exactly right: a one-pixel ramp centred on the edge.
  // The 0.5 is what centres it — exercise 2 below has the derivation.
  float fill = clamp(0.5 + d / px, 0.0, 1.0);

  // mix(a, b, t) is a + (b - a) * t: t = 0 gives a, t = 1 gives b. Since fill is
  // outside-ness, shapeColor takes the 0 end and bgColor the 1 end. The ramp
  // pixels land in between, and that partial blend IS the anti-aliasing —
  // coverage turned into color by a linear interpolation.
  vec3 color = mix(shapeColor, bgColor, fill);

  fragColor = vec4(color, 1.0);
}

// ---------------------------------------------------------------------------
// EXERCISES — roughly in order. Each builds on the last.
// ---------------------------------------------------------------------------
//
// 1. MAKE IT A CIRCLE.  [done]
//    `length(p)` is distance from the centre; subtracting a radius gives the
//    signed distance to the circle's edge. The move that mattered: put the
//    subtraction in `d`, not in the color.
//
// 2. TURN THE SIGN INTO A MASK.  [done]
//    step() first, to see the staircase that comes of every pixel being fully in
//    or fully out, then a ramp about a pixel wide to soften it.
//
//    WHERE THE 0.5 COMES FROM. Work in pixels: let t = d / px, the signed
//    distance measured in screen pixels. A pixel is SAMPLED at its centre but
//    COVERS the range t-0.5 .. t+0.5, so for a straight edge the fraction of the
//    pixel lying outside the shape is
//
//        t <= -0.5    pixel wholly inside    -> 0
//        t >= +0.5    pixel wholly outside   -> 1
//        in between   -> t + 0.5             (a straight line between the two)
//
//    Read that back as an expression and it is exactly
//      clamp(0.5 + d / px, 0.0, 1.0)
//    a ramp one pixel wide, centred on the edge. Not an approximation that
//    happens to look right: it IS the coverage of a straight edge, and the best
//    a single sample per pixel can do. It's also cheaper than smoothstep.
//
//    Both ways of getting it wrong are about where the ramp SITS, not how wide
//    it is. Measured on the pixel that should read fully outside (255):
//      clamp(d / px, ...)               ramp 0..1px, half a pixel outward.
//                                       Gives 0 at the true edge where 0.5 is
//                                       honest, and 128/255 here. Half a pixel
//                                       of fat on every shape.
//      1.0 - smoothstep(0.0, 2*px, d)   ramp entirely outside the shape:
//                                       a full pixel of fat.
//    smoothstep(-px, px, d) is centred, so unbiased, but spans two pixels rather
//    than one — that extra pixel is why its edges look slightly softer.
//
//    Done: greyscale became a two-color palette with
//      vec3 color = mix(shapeColor, bgColor, fill);
//    shapeColor first, because fill is outside-ness. Keeping the shape dark
//    preserves the "dark = negative = inside" reading the greyscale had, so the
//    picture is still a view of the field rather than just a picture of a disc.
//
// 3. SEE THE FIELD ITSELF.
//    Add `color += 0.06 * cos(d * 50.0);` and the invisible field turns into
//    contour rings, like a topographic map. Very worth doing once: from here on
//    you'll be reasoning about a landscape you can't normally see. Drag the
//    50.0 around to change the ring spacing.
//
// 4. ADD A SECOND SHAPE — A BOX.
//    A box is the one people can't derive from scratch, so here's the shape of
//    the trick rather than the answer: fold the plane into one quadrant with
//    abs(p), subtract the box's half-size, and you're left with a vector of
//    per-axis overshoots. Outside distance is the length of the positive part
//    of that vector; inside distance is the largest (least negative) component.
//    `max(v, 0.0)` and `min(max(v.x, v.y), 0.0)` are the two pieces, and they
//    add together. Inigo Quilez's 2D distance functions page has the canonical
//    version if you'd rather read it than derive it.
//
// 5. COMBINE THEM. This is where SDFs get fun, and it's three operators:
//      union         min(a, b)
//      intersection  max(a, b)
//      subtraction   max(a, -b)      <- b punches a hole in a
//    Offset a shape by subtracting from p first: sdCircle(p - vec2(0.4, 0.0), r)
//    moves it right. Note it's MINUS to move in the PLUS direction — you're
//    moving the coordinate system, not the shape.
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
//    The centred-repeat line from 01's notes works here unchanged:
//      float s = 0.7;
//      vec2 q = p - s * floor(p / s + 0.5);
//    Compute your circle on `q` instead of `p` and one circle becomes a grid of
//    them. Same cost per pixel, however many you "draw".
//
// STUCK? `pnpm test:shaders` will tell you about syntax and type errors without
// you having to hunt for a blank screen in the browser.
