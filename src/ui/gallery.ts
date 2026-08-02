import type { Scene } from '../engine/types';

// Sidebar scene switcher, grouped by level.
const LEVEL_LABELS: Record<number, string> = {
  1: 'Level 1 · Fragment basics',
  2: 'Level 2 · Inputs & patterns',
  3: 'Level 3 · Vertex shaders',
  4: 'Level 4 · Multi-pass',
};

const links = new Map<string, HTMLElement>();

export function buildSidebar(scenes: Scene[], onPick: (s: Scene) => void): void {
  const nav = document.getElementById('scene-list')!;
  nav.innerHTML = '';
  links.clear();

  const byLevel = new Map<number, Scene[]>();
  for (const s of scenes) {
    const arr = byLevel.get(s.level) ?? [];
    arr.push(s);
    byLevel.set(s.level, arr);
  }

  for (const level of [...byLevel.keys()].sort((a, b) => a - b)) {
    const group = document.createElement('div');
    group.className = 'group';

    const label = document.createElement('div');
    label.className = 'group-label';
    label.textContent = LEVEL_LABELS[level] ?? `Level ${level}`;
    group.appendChild(label);

    for (const scene of byLevel.get(level)!) {
      const a = document.createElement('a');
      a.className = 'scene-link';
      a.href = `#${scene.id}`;
      if (scene.kind === 'custom') a.dataset.custom = 'true';

      const dot = document.createElement('span');
      dot.className = 'dot';
      const title = document.createElement('span');
      title.className = 'scene-title';
      title.textContent = scene.title;

      a.append(dot, title);
      a.addEventListener('click', (e) => {
        e.preventDefault();
        onPick(scene);
      });
      links.set(scene.id, a);
      group.appendChild(a);
    }
    nav.appendChild(group);
  }

  const foot = document.getElementById('sidebar-foot');
  if (foot) {
    const count = `${scenes.length} scene${scenes.length === 1 ? '' : 's'}`;
    foot.innerHTML = `${count} · <kbd>↑</kbd><kbd>↓</kbd> to switch · drag on canvas for <code>iMouse</code>`;
  }
}

export function setActive(id: string): void {
  for (const [linkId, el] of links) {
    el.classList.toggle('active', linkId === id);
  }
}
