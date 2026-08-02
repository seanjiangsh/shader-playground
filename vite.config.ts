import { defineConfig } from 'vite';

// No plugins needed: we import .glsl files as raw strings via `?raw`,
// which Vite supports natively (and hot-reloads on save).
export default defineConfig({
  server: { open: true },
  build: { target: 'es2020' },
});
