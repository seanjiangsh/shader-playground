import type { ShaderScene } from '../../engine/types';
import fragment from './frag.glsl?raw';

const scene: ShaderScene = {
  id: '02-shape-sdf',
  title: 'SDF shapes',
  level: 2,
  blurb:
    'A 4x4 gallery, one panel per exercise: the distance field, anti-aliased masks, contours, boolean operators, smooth union, outline, glow and repetition, with per-cell identity, drop shadow and transforms still to come.',
  fragment,
};

export default scene;
