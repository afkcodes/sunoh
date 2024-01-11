import { Shape, TileSize } from '~types/common.types';

const tileSize: {
  [key in TileSize]: string;
} = {
  '3xs': 'w-8',
  '2.5xs': 'w-10',
  '2xs': 'w-12',
  xs: 'w-16',
  sm: 'w-20',
  md: 'w-24',
  lg: 'w-28',
  xl: 'w-32',
  '2xl': 'w-36',
  '3xl': 'w-40',
  '4xl': 'w-44',
  '5xl': 'w-64',
  '6xl': 'w-72',
  free: 'h-full w-full'
};

const tileShape: {
  [key in Shape]: string;
} = {
  default: 'overflow-hidden rounded-none',
  rounded_square: 'overflow-hidden rounded',
  circle: 'overflow-hidden rounded-full'
};

export { tileShape, tileSize };
