import type { Geometry, Pass, ShaderScene } from './types';
import { RenderTarget } from './RenderTarget';
import {
  assembleFragment,
  assembleVertex,
  DEFAULT_VERT_GRID,
  DEFAULT_VERT_QUAD,
} from './shaderSource';

// ---------------------------------------------------------------------------
// Renderer: a tiny raw-WebGL harness. This is the whole "engine".
//
// It does exactly what ShaderToy does under the hood:
//   • create a WebGL context on a canvas
//   • put some geometry in front of the camera (a fullscreen quad, or a grid)
//   • compile your GLSL, feed it standard uniforms, and draw every frame
//   • (level 4) run off-screen passes first and hand them to you as textures
//
// Nothing here is hidden from you — read it top to bottom and you'll understand
// what Pixi and Three.js are doing for you when you use them later.
// ---------------------------------------------------------------------------

/** How many iChannel slots a pass (or the final image) can read. */
const MAX_CHANNELS = 4;

function compile(gl: WebGLRenderingContext, type: number, src: string): WebGLShader {
  const shader = gl.createShader(type);
  if (!shader) throw new Error('createShader failed');
  gl.shaderSource(shader, src);
  gl.compileShader(shader);
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
    const log = gl.getShaderInfoLog(shader) ?? 'unknown error';
    gl.deleteShader(shader);
    const kind = type === gl.VERTEX_SHADER ? 'vertex' : 'fragment';
    throw new Error(`${kind} shader failed to compile:\n${log}`);
  }
  return shader;
}

function link(gl: WebGLRenderingContext, vs: WebGLShader, fs: WebGLShader): WebGLProgram {
  const program = gl.createProgram();
  if (!program) throw new Error('createProgram failed');
  gl.attachShader(program, vs);
  gl.attachShader(program, fs);
  gl.linkProgram(program);
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
    const log = gl.getProgramInfoLog(program) ?? 'unknown error';
    throw new Error(`program failed to link:\n${log}`);
  }
  return program;
}

interface Geo {
  buffer: WebGLBuffer;
  index: WebGLBuffer | null;
  drawCount: number;
  stride: number;
  // attribute name -> { size, offset }
  attribs: Record<string, { size: number; offset: number }>;
  mode: number; // gl.TRIANGLES
}

/** Fullscreen quad: two triangles, positions only. */
function makeQuad(gl: WebGLRenderingContext): Geo {
  // prettier-ignore
  const verts = new Float32Array([
    -1, -1,  1, -1,  -1, 1,
    -1,  1,  1, -1,   1, 1,
  ]);
  const buffer = gl.createBuffer()!;
  gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
  gl.bufferData(gl.ARRAY_BUFFER, verts, gl.STATIC_DRAW);
  return {
    buffer,
    index: null,
    drawCount: 6,
    stride: 2 * 4,
    attribs: { aPosition: { size: 2, offset: 0 } },
    mode: gl.TRIANGLES,
  };
}

/** Subdivided plane in the XY range [-1, 1]. Interleaved: x,y,z,u,v. */
function makeGrid(gl: WebGLRenderingContext, n: number): Geo {
  const verts: number[] = [];
  for (let j = 0; j <= n; j++) {
    for (let i = 0; i <= n; i++) {
      const u = i / n;
      const v = j / n;
      verts.push(u * 2 - 1, v * 2 - 1, 0, u, v);
    }
  }
  const indices: number[] = [];
  const row = n + 1;
  for (let j = 0; j < n; j++) {
    for (let i = 0; i < n; i++) {
      const a = j * row + i;
      const b = a + 1;
      const c = a + row;
      const d = c + 1;
      indices.push(a, b, c, b, d, c);
    }
  }
  const buffer = gl.createBuffer()!;
  gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(verts), gl.STATIC_DRAW);

  const index = gl.createBuffer()!;
  gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, index);
  const use32 = verts.length / 5 > 65535;
  gl.bufferData(
    gl.ELEMENT_ARRAY_BUFFER,
    use32 ? new Uint32Array(indices) : new Uint16Array(indices),
    gl.STATIC_DRAW,
  );
  (index as WebGLBuffer & { __type?: number }).__type = use32
    ? gl.UNSIGNED_INT
    : gl.UNSIGNED_SHORT;

  return {
    buffer,
    index,
    drawCount: indices.length,
    stride: 5 * 4,
    attribs: {
      aPosition: { size: 3, offset: 0 },
      aUv: { size: 2, offset: 3 * 4 },
    },
    mode: gl.TRIANGLES,
  };
}

/** Uniform locations, looked up once per program instead of every frame. */
interface UniformSet {
  iResolution: WebGLUniformLocation | null;
  iTime: WebGLUniformLocation | null;
  iTimeDelta: WebGLUniformLocation | null;
  iFrame: WebGLUniformLocation | null;
  iMouse: WebGLUniformLocation | null;
  channels: (WebGLUniformLocation | null)[];
  channelResolution: WebGLUniformLocation | null;
}

/**
 * One compiled pass, ready to draw. The final on-screen image is a DrawStep
 * too — it just owns no render targets and draws to the canvas instead.
 */
interface DrawStep {
  id: string;
  program: WebGLProgram;
  geo: Geo;
  uni: UniformSet;
  inputs: string[];
  scale: number;
  usesDepth: boolean;
  /** [target] normally; [a, b] for a feedback pass that reads its own output. */
  targets: RenderTarget[];
  /** Index of the target written this frame (the other holds last frame). */
  write: number;
}

interface StepSpec {
  id: string;
  fragment: string;
  vertex?: string;
  geometry?: Geometry;
  gridResolution?: number;
  inputs?: string[];
  scale?: number;
  filter?: 'nearest' | 'linear';
  /** true = renders into a texture, false = renders to the canvas */
  offscreen: boolean;
  /** true = reads its own previous frame, so it needs two textures */
  feedback: boolean;
}

export interface RendererStats {
  fps: number;
  frame: number;
  width: number;
  height: number;
}

export class Renderer {
  readonly gl: WebGLRenderingContext;
  private steps: DrawStep[] = []; // off-screen passes, in order
  private image: DrawStep | null = null; // the final pass, drawn to the canvas
  private raf = 0;
  private startTime = 0;
  private lastTime = 0;
  private frame = 0;
  private mouse = { x: 0, y: 0, downX: 0, downY: 0, down: false };
  private ro: ResizeObserver;
  private dpr = Math.min(window.devicePixelRatio || 1, 2);
  private disposed = false;
  /** Scratch buffer for the iChannelResolution[4] array uniform (4 × vec3). */
  private channelRes = new Float32Array(MAX_CHANNELS * 3);

  // FPS smoothing
  private fpsAccum = 0;
  private fpsFrames = 0;
  private fps = 0;

  onStats?: (s: RendererStats) => void;

  constructor(private canvas: HTMLCanvasElement) {
    const gl = canvas.getContext('webgl', { antialias: true, alpha: false });
    if (!gl) throw new Error('WebGL is not available in this browser.');
    this.gl = gl;

    // mouse (ShaderToy semantics: y is up, origin bottom-left)
    canvas.addEventListener('pointermove', this.onPointerMove);
    canvas.addEventListener('pointerdown', this.onPointerDown);
    window.addEventListener('pointerup', this.onPointerUp);

    this.ro = new ResizeObserver(() => this.resize());
    this.ro.observe(canvas);
  }

  /** Compile one pass (or the final image) into something we can draw. */
  private buildStep(spec: StepSpec): DrawStep {
    const gl = this.gl;
    const geometry = spec.geometry ?? 'quad';
    const defaultVert = geometry === 'grid' ? DEFAULT_VERT_GRID : DEFAULT_VERT_QUAD;

    const vs = compile(gl, gl.VERTEX_SHADER, assembleVertex(spec.vertex ?? defaultVert));
    const fs = compile(gl, gl.FRAGMENT_SHADER, assembleFragment(spec.fragment));
    const program = link(gl, vs, fs);
    gl.deleteShader(vs);
    gl.deleteShader(fs);

    const channels: (WebGLUniformLocation | null)[] = [];
    for (let i = 0; i < MAX_CHANNELS; i++) {
      channels.push(gl.getUniformLocation(program, `iChannel${i}`));
    }

    const uni: UniformSet = {
      iResolution: gl.getUniformLocation(program, 'iResolution'),
      iTime: gl.getUniformLocation(program, 'iTime'),
      iTimeDelta: gl.getUniformLocation(program, 'iTimeDelta'),
      iFrame: gl.getUniformLocation(program, 'iFrame'),
      iMouse: gl.getUniformLocation(program, 'iMouse'),
      channels,
      // An array uniform is addressed through its first element; one uniform3fv
      // with 12 floats then fills all four vec3s.
      channelResolution:
        gl.getUniformLocation(program, 'iChannelResolution[0]') ??
        gl.getUniformLocation(program, 'iChannelResolution'),
    };

    const usesDepth = geometry === 'grid';
    const targets: RenderTarget[] = [];
    if (spec.offscreen) {
      // A feedback pass needs TWO textures. Sampling a texture while rendering
      // into it is undefined behaviour, so we read one and write the other,
      // then swap at the end of the frame. That's "ping-pong".
      const count = spec.feedback ? 2 : 1;
      for (let i = 0; i < count; i++) {
        targets.push(new RenderTarget(gl, spec.filter ?? 'linear', usesDepth));
      }
    }

    return {
      id: spec.id,
      program,
      geo: geometry === 'grid' ? makeGrid(gl, spec.gridResolution ?? 128) : makeQuad(gl),
      uni,
      inputs: spec.inputs ?? [],
      scale: spec.scale ?? 1,
      usesDepth,
      targets,
      write: 0,
    };
  }

  /** Compile a shader scene and start (or restart) the render loop. */
  setScene(scene: ShaderScene): void {
    this.releaseSteps();

    const passes: Pass[] = scene.passes ?? [];
    this.steps = passes.map((p) =>
      this.buildStep({
        ...p,
        offscreen: true,
        // A pass listing its OWN id as an input is what marks it as feedback.
        feedback: (p.inputs ?? []).includes(p.id),
      }),
    );

    this.image = this.buildStep({
      id: '__image',
      fragment: scene.fragment,
      vertex: scene.vertex,
      geometry: scene.geometry,
      gridResolution: scene.gridResolution,
      inputs: scene.inputs,
      offscreen: false,
      feedback: false,
    });

    // Fail loudly on a typo'd pass id instead of silently sampling black.
    const known = new Set(this.steps.map((s) => s.id));
    for (const step of [...this.steps, this.image]) {
      for (const input of step.inputs) {
        if (!known.has(input)) {
          const list = [...known].join(', ') || '(none)';
          throw new Error(`pass "${step.id}" reads unknown input "${input}". Known passes: ${list}`);
        }
      }
    }

    this.startTime = performance.now();
    this.lastTime = this.startTime;
    this.frame = 0;
    this.resize();

    if (!this.raf) this.loop();
  }

  private bindAttribs(step: DrawStep): void {
    const gl = this.gl;
    gl.bindBuffer(gl.ARRAY_BUFFER, step.geo.buffer);
    for (const [name, a] of Object.entries(step.geo.attribs)) {
      const loc = gl.getAttribLocation(step.program, name);
      if (loc < 0) continue; // shader doesn't use this attribute
      gl.enableVertexAttribArray(loc);
      gl.vertexAttribPointer(loc, a.size, gl.FLOAT, false, step.geo.stride, a.offset);
    }
    if (step.geo.index) gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, step.geo.index);
  }

  /**
   * Which texture a step should read when it names `id` as an input.
   * If a step names ITSELF it wants last frame's texture — the one we are not
   * currently writing into.
   */
  private textureFor(id: string, self: DrawStep): RenderTarget | null {
    const src = this.steps.find((s) => s.id === id);
    if (!src) return null;
    const index = src === self ? 1 - src.write : src.write;
    return src.targets[index] ?? src.targets[0] ?? null;
  }

  private drawStep(step: DrawStep, time: number, delta: number, w: number, h: number): void {
    const gl = this.gl;
    gl.useProgram(step.program);

    if (step.uni.iResolution) gl.uniform3f(step.uni.iResolution, w, h, 1);
    if (step.uni.iTime) gl.uniform1f(step.uni.iTime, time);
    if (step.uni.iTimeDelta) gl.uniform1f(step.uni.iTimeDelta, delta);
    if (step.uni.iFrame) gl.uniform1i(step.uni.iFrame, this.frame);
    if (step.uni.iMouse) {
      gl.uniform4f(
        step.uni.iMouse,
        this.mouse.x,
        this.mouse.y,
        this.mouse.down ? this.mouse.downX : -Math.abs(this.mouse.downX),
        this.mouse.down ? this.mouse.downY : -Math.abs(this.mouse.downY),
      );
    }

    // Bind each input pass's texture to a texture unit, then tell the sampler
    // uniform which UNIT to look at. A sampler holds a unit number, not a
    // texture — that trips up everyone exactly once.
    this.channelRes.fill(0);
    for (let i = 0; i < MAX_CHANNELS; i++) {
      const id: string | undefined = step.inputs[i];
      const target = id ? this.textureFor(id, step) : null;
      gl.activeTexture(gl.TEXTURE0 + i);
      gl.bindTexture(gl.TEXTURE_2D, target ? target.texture : null);
      if (step.uni.channels[i]) gl.uniform1i(step.uni.channels[i], i);
      if (target) {
        this.channelRes[i * 3 + 0] = target.width;
        this.channelRes[i * 3 + 1] = target.height;
        this.channelRes[i * 3 + 2] = 1;
      }
    }
    if (step.uni.channelResolution) {
      gl.uniform3fv(step.uni.channelResolution, this.channelRes);
    }

    if (step.usesDepth) gl.enable(gl.DEPTH_TEST);
    else gl.disable(gl.DEPTH_TEST);

    gl.clearColor(0, 0, 0, 1);
    gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

    this.bindAttribs(step);
    if (step.geo.index) {
      const type =
        (step.geo.index as WebGLBuffer & { __type?: number }).__type ?? gl.UNSIGNED_SHORT;
      gl.drawElements(step.geo.mode, step.geo.drawCount, type, 0);
    } else {
      gl.drawArrays(step.geo.mode, 0, step.geo.drawCount);
    }
  }

  private loop = (): void => {
    if (this.disposed) return;
    this.raf = requestAnimationFrame(this.loop);
    if (!this.image) return;

    const gl = this.gl;
    const now = performance.now();
    const time = (now - this.startTime) / 1000;
    const delta = (now - this.lastTime) / 1000;
    this.lastTime = now;

    const { drawingBufferWidth: w, drawingBufferHeight: h } = gl;

    // 1. Off-screen passes, in declaration order. Each renders into its own
    //    texture, which any later pass can sample.
    for (const step of this.steps) {
      const target = step.targets[step.write];
      target.resize(
        Math.max(1, Math.round(w * step.scale)),
        Math.max(1, Math.round(h * step.scale)),
      );
      target.bind();
      this.drawStep(step, time, delta, target.width, target.height);
    }

    // 2. The final pass, straight to the canvas (framebuffer null = the screen).
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    gl.viewport(0, 0, w, h);
    this.drawStep(this.image, time, delta, w, h);

    // 3. Swap the ping-pong buffers, AFTER everything has drawn — so a pass
    //    later in the chain still reads the texture written this frame.
    for (const step of this.steps) {
      if (step.targets.length > 1) step.write = 1 - step.write;
    }

    this.frame++;
    this.fpsAccum += delta;
    this.fpsFrames++;
    if (this.fpsAccum >= 0.5) {
      this.fps = this.fpsFrames / this.fpsAccum;
      this.fpsAccum = 0;
      this.fpsFrames = 0;
      this.onStats?.({ fps: this.fps, frame: this.frame, width: w, height: h });
    }
  };

  private resize(): void {
    const gl = this.gl;
    const w = Math.max(1, Math.floor(this.canvas.clientWidth * this.dpr));
    const h = Math.max(1, Math.floor(this.canvas.clientHeight * this.dpr));
    if (this.canvas.width !== w || this.canvas.height !== h) {
      this.canvas.width = w;
      this.canvas.height = h;
    }
    gl.viewport(0, 0, gl.drawingBufferWidth, gl.drawingBufferHeight);
    // Off-screen targets follow the canvas and reallocate on the next frame.
    // Reallocating wipes a feedback buffer's history — that's why trails vanish
    // when you drag the window edge.
  }

  private onPointerMove = (e: PointerEvent): void => {
    const r = this.canvas.getBoundingClientRect();
    this.mouse.x = (e.clientX - r.left) * this.dpr;
    this.mouse.y = (r.height - (e.clientY - r.top)) * this.dpr; // flip y
    if (this.mouse.down) {
      this.mouse.downX = this.mouse.x;
      this.mouse.downY = this.mouse.y;
    }
  };
  private onPointerDown = (): void => {
    this.mouse.down = true;
    this.mouse.downX = this.mouse.x;
    this.mouse.downY = this.mouse.y;
  };
  private onPointerUp = (): void => {
    this.mouse.down = false;
  };

  /** Free every GPU object owned by the current scene. */
  private releaseSteps(): void {
    const gl = this.gl;
    const all = this.image ? [...this.steps, this.image] : this.steps;
    for (const step of all) {
      gl.deleteProgram(step.program);
      gl.deleteBuffer(step.geo.buffer);
      if (step.geo.index) gl.deleteBuffer(step.geo.index);
      for (const t of step.targets) t.dispose();
    }
    this.steps = [];
    this.image = null;
  }

  dispose(): void {
    this.disposed = true;
    cancelAnimationFrame(this.raf);
    this.raf = 0;
    this.ro.disconnect();
    this.canvas.removeEventListener('pointermove', this.onPointerMove);
    this.canvas.removeEventListener('pointerdown', this.onPointerDown);
    window.removeEventListener('pointerup', this.onPointerUp);
    this.releaseSteps();
    const lose = this.gl.getExtension('WEBGL_lose_context');
    lose?.loseContext();
  }
}
