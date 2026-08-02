import type { ShaderScene } from '../../engine/types';
import fragment from './frag.glsl?raw';

const scene: ShaderScene = {
  id: '01-gradient',
  title: 'Gradient & time',
  level: 1,
  blurb: 'Normalize pixel coords to 0..1 (uv), turn them into color, animate with iTime. The whole idea in six lines.',
  fragment,
};

export default scene;
