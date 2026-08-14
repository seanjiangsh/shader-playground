import type { ShaderScene } from '../../engine/types';
import fragment from './frag.glsl?raw';

const scene: ShaderScene = {
  id: '02-shape-sdf',
  title: 'SDF shapes',
  level: 2,
  blurb:
    'Starter — the exercises are in frag.glsl. Draw shapes with math instead of geometry: distance to an edge, smoothstep anti-aliasing, then unions and repetition.',
  fragment,
};

export default scene;
