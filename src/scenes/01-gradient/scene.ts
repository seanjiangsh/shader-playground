import type { ShaderScene } from '../../engine/types';
import fragment from './frag.glsl?raw';

const scene: ShaderScene = {
  id: '01-gradient',
  title: 'Gradient & time',
  level: 1,
  blurb:
    'One pixel, two coordinate spaces: 0..1 uv for position across the image, centred square units for geometry. Tiled with fract, animated with iTime.',
  fragment,
};

export default scene;
