// ---------------------------------------------------------------------------
// RenderTarget: an off-screen "screen" you can draw into, then read back as a
// texture. This is the one genuinely new WebGL object that Level 4 needs.
//
// Up to level 3 every draw went straight to the canvas. A framebuffer object
// (FBO) lets you point the GPU somewhere else: "render into this texture
// instead". Do that a few times in a row and you have a multi-pass pipeline —
// blur, bloom, feedback, and eventually simulations that live in a texture.
//
// The three pieces, and how they relate:
//   • texture      — the pixels themselves. A later pass samples this.
//   • framebuffer  — a small descriptor that says "draws go into that texture".
//   • renderbuffer — storage the GPU needs but you never sample; here, depth.
//                    Only allocated when a pass draws real 3D geometry.
// ---------------------------------------------------------------------------

export type TargetFilter = 'nearest' | 'linear';

/** Turn a framebuffer-status enum into something readable when things go wrong. */
function statusName(gl: WebGLRenderingContext, status: number): string {
  switch (status) {
    case gl.FRAMEBUFFER_INCOMPLETE_ATTACHMENT:
      return 'INCOMPLETE_ATTACHMENT';
    case gl.FRAMEBUFFER_INCOMPLETE_MISSING_ATTACHMENT:
      return 'INCOMPLETE_MISSING_ATTACHMENT';
    case gl.FRAMEBUFFER_INCOMPLETE_DIMENSIONS:
      return 'INCOMPLETE_DIMENSIONS';
    case gl.FRAMEBUFFER_UNSUPPORTED:
      return 'UNSUPPORTED';
    default:
      return `0x${status.toString(16)}`;
  }
}

export class RenderTarget {
  readonly framebuffer: WebGLFramebuffer;
  readonly texture: WebGLTexture;
  private depth: WebGLRenderbuffer | null = null;
  width = 0;
  height = 0;

  constructor(
    private gl: WebGLRenderingContext,
    filter: TargetFilter = 'linear',
    withDepth = false,
  ) {
    const framebuffer = gl.createFramebuffer();
    const texture = gl.createTexture();
    if (!framebuffer || !texture) throw new Error('could not create a render target');
    this.framebuffer = framebuffer;
    this.texture = texture;

    const f = filter === 'nearest' ? gl.NEAREST : gl.LINEAR;
    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, f);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, f);
    // WebGL 1 landmine: a texture whose size is not a power of two MUST use
    // CLAMP_TO_EDGE and MUST NOT use a mipmapping filter. Our targets are
    // canvas-sized, so they're almost never a power of two. Get this wrong and
    // you get a silently black texture — no error, no warning.
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.bindTexture(gl.TEXTURE_2D, null);

    if (withDepth) {
      const rb = gl.createRenderbuffer();
      if (!rb) throw new Error('could not create a depth renderbuffer');
      this.depth = rb;
    }
  }

  /**
   * (Re)allocate storage at this size. Cheap no-op when the size is unchanged,
   * so the render loop can just call it every frame.
   * Returns true if the storage was actually reallocated (contents are lost).
   */
  resize(width: number, height: number): boolean {
    if (width === this.width && height === this.height) return false;
    const gl = this.gl;
    this.width = width;
    this.height = height;

    // Passing `null` as the pixel source allocates the storage without
    // uploading anything — we're going to render into it, not fill it from JS.
    gl.bindTexture(gl.TEXTURE_2D, this.texture);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, width, height, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
    gl.bindTexture(gl.TEXTURE_2D, null);

    gl.bindFramebuffer(gl.FRAMEBUFFER, this.framebuffer);
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, this.texture, 0);

    if (this.depth) {
      gl.bindRenderbuffer(gl.RENDERBUFFER, this.depth);
      gl.renderbufferStorage(gl.RENDERBUFFER, gl.DEPTH_COMPONENT16, width, height);
      gl.framebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.RENDERBUFFER, this.depth);
      gl.bindRenderbuffer(gl.RENDERBUFFER, null);
    }

    const status = gl.checkFramebufferStatus(gl.FRAMEBUFFER);
    if (status !== gl.FRAMEBUFFER_COMPLETE) {
      gl.bindFramebuffer(gl.FRAMEBUFFER, null);
      throw new Error(
        `render target is incomplete (${statusName(gl, status)}) at ${width}x${height}`,
      );
    }

    // Fresh GPU storage holds garbage. Clear it, so a feedback pass reading its
    // own "previous frame" on frame 0 reads black instead of whatever was in
    // that memory.
    gl.viewport(0, 0, width, height);
    gl.clearColor(0, 0, 0, 1);
    gl.clear(gl.COLOR_BUFFER_BIT | (this.depth ? gl.DEPTH_BUFFER_BIT : 0));
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    return true;
  }

  /** Point all subsequent draws at this target. */
  bind(): void {
    const gl = this.gl;
    gl.bindFramebuffer(gl.FRAMEBUFFER, this.framebuffer);
    gl.viewport(0, 0, this.width, this.height);
  }

  dispose(): void {
    const gl = this.gl;
    gl.deleteFramebuffer(this.framebuffer);
    gl.deleteTexture(this.texture);
    if (this.depth) gl.deleteRenderbuffer(this.depth);
  }
}
