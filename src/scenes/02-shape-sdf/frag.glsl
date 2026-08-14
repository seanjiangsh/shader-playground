// Level 2 — signed distance fields. STARTER: the exercises are yours to fill in.
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
// Right now this draws the rawest distance field there is: distance from the
// centre, straight to the screen. Black at the middle, brighter as you move
// out, clipped to white past 1.0. Not a shape yet. Work down the exercises and
// it becomes one.
//
// A worked solution is parked at src/_parked/02-shape-sdf-reference/ — it won't
// appear in the sidebar. Try not to open it until yours runs.

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
  // Centred, aspect-corrected coordinates: the `p` you met in 01. Both axes are
  // divided by the height, so distances mean the same thing in x and y and a
  // circle comes out round. p.y runs -1..1; p.x runs -aspect..+aspect.
  vec2 p = (2.0 * fragCoord - iResolution.xy) / iResolution.y;

  // One screen pixel, measured in p units. Handy for edge widths that stay
  // crisp at any canvas size — see exercise 2.
  float px = 2.0 / iResolution.y;

  // The field. Distance from p to the origin, and nothing else yet.
  float d = length(p);

  vec3 color = vec3(d);

  fragColor = vec4(color, 1.0);
}

// ---------------------------------------------------------------------------
// EXERCISES — roughly in order. Each builds on the last.
// ---------------------------------------------------------------------------
//
// 1. MAKE IT A CIRCLE.
//    `length(p)` is distance from the centre. Subtract a radius and you have
//    the signed distance to a circle's edge: zero ON the circle, negative
//    inside, positive outside. Try r = 0.4.
//    Everything inside now goes negative, and negative colours clamp to black —
//    so a black disc appears. That black disc IS the inside of your shape.
//
// 2. TURN THE SIGN INTO A FILL.
//    You want "1.0 where d < 0, 0.0 where d > 0".
//      float fill = step(0.0, -d);              <- try this first
//    Look closely at the edge: it's jagged, because every pixel is fully in or
//    fully out. Now soften it across roughly two pixels:
//      float fill = 1.0 - smoothstep(0.0, 2.0 * px, d);
//    Then mix a background and a shape colour by `fill`. Compare the two edges
//    side by side — this is anti-aliasing, and it's why the distance is worth
//    more than a boolean.
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
