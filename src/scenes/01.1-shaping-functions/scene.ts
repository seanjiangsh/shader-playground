import type { ShaderScene } from '../../engine/types';
import fragment from './frag.glsl?raw';

const scene: ShaderScene = {
  id: '01.1-shaping-functions',
  title: 'Shaping functions',
  level: 1,
  blurb:
    'Starter — a 5x5 gallery of graphs. Plot y = f(x) inside a tile, colour the tile by the value, and build up the shaping functions from The Book of Shaders chapter 5 one tile at a time.',
  fragment,
};

export default scene;
