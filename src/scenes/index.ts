import type { Scene } from '../engine/types';

// Auto-discovery: every folder in src/scenes/ that contains a `scene.ts`
// exporting a default Scene is picked up automatically. To add a scene you
// drop in a folder — you never edit this file.
const modules = import.meta.glob('./*/scene.ts', { eager: true }) as Record<
  string,
  { default: Scene }
>;

export const scenes: Scene[] = Object.values(modules)
  .map((m) => m.default)
  .filter(Boolean)
  .sort((a, b) => a.level - b.level || a.id.localeCompare(b.id));

export function findScene(id: string): Scene | undefined {
  return scenes.find((s) => s.id === id);
}
