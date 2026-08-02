import { Renderer } from './engine/Renderer';
import { isCustomScene, type Scene, type SceneInstance } from './engine/types';
import { scenes, findScene } from './scenes';
import { buildSidebar, setActive } from './ui/gallery';

// ---------------------------------------------------------------------------
// App shell: owns the canvas host, swaps scenes, wires the sidebar + routing.
// Each scene switch gets a FRESH <canvas> so raw-WebGL scenes and future
// Pixi/Three scenes never fight over one GL context.
// ---------------------------------------------------------------------------

const host = document.getElementById('canvas-host')!;
const hudTitle = document.getElementById('hud-title')!;
const hudStats = document.getElementById('hud-stats')!;
const blurbEl = document.getElementById('scene-blurb')!;

let renderer: Renderer | null = null;
let custom: SceneInstance | null = null;

function teardown(): void {
  renderer?.dispose();
  renderer = null;
  custom?.dispose();
  custom = null;
  host.innerHTML = '';
}

function freshCanvas(): HTMLCanvasElement {
  const canvas = document.createElement('canvas');
  canvas.className = 'gl';
  host.appendChild(canvas);
  return canvas;
}

function showError(message: string): void {
  const pre = document.createElement('pre');
  pre.className = 'error';
  pre.textContent = message;
  host.appendChild(pre);
}

function activate(scene: Scene): void {
  teardown();
  hudTitle.textContent = scene.title;
  blurbEl.textContent = scene.blurb ?? '';
  hudStats.textContent = '';
  setActive(scene.id);
  if (location.hash.slice(1) !== scene.id) {
    history.replaceState(null, '', `#${scene.id}`);
  }

  const canvas = freshCanvas();
  try {
    if (isCustomScene(scene)) {
      custom = scene.mount(canvas);
    } else {
      const r = new Renderer(canvas);
      r.onStats = (s) => {
        hudStats.textContent = `${s.fps.toFixed(0)} fps · ${s.width}×${s.height} · frame ${s.frame}`;
      };
      r.setScene(scene);
      renderer = r;
    }
  } catch (err) {
    host.innerHTML = '';
    showError(err instanceof Error ? err.message : String(err));
  }
}

function currentFromHash(): Scene {
  return findScene(location.hash.slice(1)) ?? scenes[0];
}

// --- boot ---
if (scenes.length === 0) {
  showError('No scenes found. Add a folder under src/scenes/ with a scene.ts.');
} else {
  buildSidebar(scenes, (scene) => activate(scene));
  activate(currentFromHash());

  window.addEventListener('hashchange', () => {
    const scene = currentFromHash();
    if (scene) activate(scene);
  });

  // arrow-key navigation between scenes
  window.addEventListener('keydown', (e) => {
    if (e.key !== 'ArrowDown' && e.key !== 'ArrowUp') return;
    const idx = scenes.findIndex((s) => s.id === location.hash.slice(1));
    const next = (idx + (e.key === 'ArrowDown' ? 1 : -1) + scenes.length) % scenes.length;
    location.hash = scenes[next].id;
  });
}
