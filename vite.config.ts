import { defineConfig } from 'vite';

// No plugins needed: we import .glsl files as raw strings via `?raw`,
// which Vite supports natively (and hot-reloads on save).
export default defineConfig({
  // Relative asset paths, so the built site works from any folder. GitHub
  // Pages serves this repo at /shader-playground/, not at the domain root, and
  // './' makes the same build work there, locally and anywhere else. Scenes are
  // picked by the URL hash (#02-shape-sdf), so there are no other paths to fix.
  base: './',
  server: { open: true },
  build: { target: 'es2020' },
});
