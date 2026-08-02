// ---------------------------------------------------------------------------
// Shader validation: compile and LINK every scene's GLSL, without a browser.
//
//   pnpm test:shaders     (also runs as part of `pnpm build`)
//
// Why this exists. A shader that compiles can still fail to link, because some
// rules are about the RELATIONSHIP between the vertex and fragment stage rather
// than either one alone. The bug that prompted this file: `uniform int iFrame`
// picked up a different default precision in each stage, which the GLSL ES spec
// forbids. Chrome's ANGLE ran it anyway; Firefox refused. Testing in one browser
// told us nothing.
//
// glslangValidator is Khronos's reference GLSL compiler — the front-end shipped
// with the Vulkan SDK. Given `-l` and both stages it links them and enforces the
// spec's cross-stage rules, which is exactly the class of bug a single browser
// hides. The `glslang-validator-prebuilt-predownloaded` devDependency carries
// the macOS/Linux/Windows binaries, so there's nothing to install system-wide.
//
// How the shaders get here. The scenes are loaded through Vite's SSR loader, so
// `?raw` glsl imports resolve and any source composed at runtime (06's
// `#define DIRECTION` blur variants) is included exactly as the engine builds
// it. Assembly then goes through src/engine/shaderSource.ts — the same module
// the engine uses — so what gets validated is byte-for-byte what WebGL sees.
//
// Caveat worth remembering: this enforces the SPEC. Browsers each add their own
// quirks on top, and Chrome is the lenient one. Passing here is necessary, not
// sufficient — still open Firefox now and then.
// ---------------------------------------------------------------------------

import { spawnSync } from 'node:child_process';
import {
  chmodSync,
  mkdtempSync,
  readdirSync,
  rmSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { createServer } from 'vite';

const require = createRequire(import.meta.url);
const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');

// WebGL 1 shaders carry no #version line and default to ESSL 1.00. glslang
// defaults to desktop GLSL instead, so we say it explicitly — that's what makes
// it apply the ES rules the browser will apply.
const VERSION_DIRECTIVE = '#version 100\n';

function glslangPath() {
  try {
    const bin = require('glslang-validator-prebuilt-predownloaded').path;
    // npm tarballs don't reliably preserve the executable bit, so the extracted
    // binary can land unrunnable. Harmless to set every time; irrelevant on
    // Windows, where .exe needs no permission bit.
    if (process.platform !== 'win32') {
      try {
        chmodSync(bin, 0o755);
      } catch {
        /* read-only store, already executable, etc. — let spawn report it */
      }
    }
    return bin;
  } catch (err) {
    console.error(
      '\n  Could not locate glslangValidator.\n' +
        '  It ships as a devDependency — try `pnpm install`.\n' +
        '  (The package only publishes x64 binaries; on an arm64 machine,\n' +
        '   install glslang yourself and point GLSLANG at it.)\n',
    );
    throw err;
  }
}

/** Every (vertex, fragment) pair a scene will ask the driver to link. */
function programsOf(scene, glsl) {
  const programs = [];
  const add = (label, spec) => {
    const geometry = spec.geometry ?? 'quad';
    const defaultVert = geometry === 'grid' ? glsl.DEFAULT_VERT_GRID : glsl.DEFAULT_VERT_QUAD;
    programs.push({
      label,
      vertex: glsl.assembleVertex(spec.vertex ?? defaultVert),
      fragment: glsl.assembleFragment(spec.fragment),
    });
  };
  for (const pass of scene.passes ?? []) add(`${scene.id} · pass "${pass.id}"`, pass);
  add(`${scene.id} · image`, scene);
  return programs;
}

/** Run glslang over one program. Returns null when it links cleanly. */
function validate(bin, dir, index, program) {
  const vertPath = join(dir, `p${index}.vert`);
  const fragPath = join(dir, `p${index}.frag`);
  writeFileSync(vertPath, VERSION_DIRECTIVE + program.vertex);
  writeFileSync(fragPath, VERSION_DIRECTIVE + program.fragment);

  // -l links the two stages together; without it each is only checked alone,
  // and cross-stage problems slip straight through.
  const run = spawnSync(bin, ['-l', vertPath, fragPath], { encoding: 'utf8' });
  if (run.error) throw run.error;
  if (run.status === 0) return null;

  // glslang echoes each filename on its own line before reporting, and prefixes
  // every diagnostic with the full path. Drop the bare echoes, and rewrite the
  // temp paths to say which stage they were — the line numbers are already
  // yours, because assembleFragment emits `#line 1` ahead of your source.
  return (run.stdout + run.stderr)
    .split('\n')
    .map((line) => line.trimEnd())
    .filter((line) => line.trim() && line.trim() !== vertPath && line.trim() !== fragPath)
    .map((line) => line.split(vertPath).join('vertex').split(fragPath).join('fragment'))
    .join('\n');
}

/** Scene folders sitting outside src/scenes (see src/_parked/README.md). */
function parkedScenePaths() {
  const parked = join(ROOT, 'src', '_parked');
  try {
    statSync(parked);
  } catch {
    return [];
  }
  return readdirSync(parked, { withFileTypes: true })
    .filter((e) => e.isDirectory())
    .map((e) => `/src/_parked/${e.name}/scene.ts`)
    .filter((p) => {
      try {
        statSync(join(ROOT, p));
        return true;
      } catch {
        return false;
      }
    });
}

const bin = glslangPath();
const server = await createServer({
  root: ROOT,
  server: { middlewareMode: true },
  appType: 'custom',
  logLevel: 'error',
});

const dir = mkdtempSync(join(tmpdir(), 'shader-check-'));
let checked = 0;
const failures = [];

try {
  const glsl = await server.ssrLoadModule('/src/engine/shaderSource.ts');

  const active = (await server.ssrLoadModule('/src/scenes/index.ts')).scenes;
  const parked = [];
  for (const path of parkedScenePaths()) {
    parked.push((await server.ssrLoadModule(path)).default);
  }

  for (const [scenes, group] of [
    [active, 'active'],
    [parked, 'parked'],
  ]) {
    for (const scene of scenes) {
      // A CustomScene owns its own canvas and brings no GLSL of its own.
      if (scene.kind === 'custom' || !scene.fragment) continue;
      for (const program of programsOf(scene, glsl)) {
        const problem = validate(bin, dir, checked++, program);
        const tag = group === 'parked' ? ' (parked)' : '';
        if (problem) {
          failures.push({ label: program.label + tag, problem });
          console.log(`  FAIL  ${program.label}${tag}`);
        } else {
          console.log(`  ok    ${program.label}${tag}`);
        }
      }
    }
  }
} finally {
  await server.close();
  rmSync(dir, { recursive: true, force: true });
}

console.log('');
if (failures.length === 0) {
  console.log(`${checked} shader program${checked === 1 ? '' : 's'} compiled and linked cleanly.`);
  process.exit(0);
}

for (const { label, problem } of failures) {
  console.error(`\n${label}\n${problem}`);
}
console.error(`\n${failures.length} of ${checked} shader programs failed to build.`);
process.exit(1);
