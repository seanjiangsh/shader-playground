import type { ShaderScene } from '../../engine/types';
import fragment from './frag.glsl?raw';

const scene: ShaderScene = {
  id: '01.2-colors',
  title: 'Colors',
  level: 1,
  blurb:
    'Starter — four panels on colour from The Book of Shaders chapter 6: blend two colours with a shaping function, give each of red, green and blue its own curve, then hue/saturation/brightness and a colour wheel.',
  fragment,
};

export default scene;
