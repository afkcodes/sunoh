import { FontSize, FontWeight, LineCount, Radius, Spacing } from '../types/common.types';

const radiusStyle: { [key in Radius]: string } = {
  xs: 'rounded-sm',
  sm: 'rounded-sm',
  md: 'rounded-sm',
  xl: 'rounded-xl',
  lg: 'rounded-lg',
  full: 'rounded-full',
  none: 'radius-none'
};

const fontSizeStyle: { [key in FontSize]: string } = {
  xs: 'text-xs',
  sm: 'text-sm',
  base: 'text-base',
  md: 'text-md',
  lg: 'text-lg',
  xl: 'text-xl',
  '2xl': 'text-2xl',
  '3xl': 'text-3xl',
  '4xl': 'text-4xl'
};

const FontWeightStyle: { [key in FontWeight]: string } = {
  normal: 'font-normal',
  bold: 'font-bold',
  medium: 'font-medium',
  semibold: 'font-semibold'
};

const LineCountStyle: { [key in LineCount]: string } = {
  1: 'line-clamp-1',
  2: 'line-clamp-2',
  3: 'line-clamp-3',
  4: 'line-clamp-4'
};

const gapStyle: { [key in Spacing]: string } = {
  '3xs': 'gap-0.5',
  '2xs': 'gap-1',
  xs: 'gap-2',
  sm: 'gap-4',
  md: 'gap-6',
  lg: 'gap-8',
  xl: 'gap-10',
  '2xl': 'gap-12',
  '3xl': 'gap-14',
  '4xl': 'gap-16'
};

const paddingStyle: { [key in Spacing]: string } = {
  '3xs': 'p-0.5',
  '2xs': 'p-1',
  xs: 'p-2',
  sm: 'p-4',
  md: 'p-6',
  lg: 'p-8',
  xl: 'p-10',
  '2xl': 'p-12',
  '3xl': 'p-14',
  '4xl': 'p-16'
};

export { FontWeightStyle, LineCountStyle, fontSizeStyle, gapStyle, paddingStyle, radiusStyle };
