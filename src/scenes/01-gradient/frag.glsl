// Your first shader — the "hello world" of GLSL.
// This function runs ONCE PER PIXEL, in parallel, for every pixel on screen.
// fragCoord = this pixel's position in pixels (origin at bottom-left).
//
// The uniforms iResolution / iTime are provided for you (see the engine).

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
  // Normalize pixel coords to the 0..1 range. This is your "uv".
  vec2 uv = fragCoord / iResolution.xy;

  // uv.x -> red across the screen, uv.y -> green up the screen,
  // and a blue channel that breathes over time with iTime.
  vec3 col = vec3(uv.x, uv.y, 0.5 + 0.5 * sin(iTime));

  // Output: red, green, blue, alpha.
  fragColor = vec4(col, 1.0);
}

// TRY THIS:
//  • swap uv.x and uv.y
//  • multiply uv by 5.0 and wrap it: uv = fract(uv * 5.0);  -> tiling
//  • replace col with vec3(uv, 1.0) and see what changes
