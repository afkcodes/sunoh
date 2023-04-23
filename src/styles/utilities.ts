import { type BorderRadius } from '~types/components.types';

export const spacing = {
  none: 0,
  xs: 4,
  sm: 8,
  md: 12,
  lg: 16,
  xl: 20,
  xxl: 24,
  xxxl: 28,
  '4xl': 32
};

export const fontSize = {
  xxs: 8,
  xs: 12,
  sm: 16,
  md: 20,
  lg: 24,
  xl: 28,
  xxl: 32,
  xxxl: 36,
  '4xl': 40
};

export const fontWeight = {
  thin: 100,
  lightX: 200,
  light: 300,
  normal: 400,
  medium: 500,
  semiBold: 600,
  bold: 700,
  boldX: 800,
  black: 900,
  blackX: 950
};

export const borderRadius: { [key in BorderRadius]: number } = {
  none: 0,
  xs: 2,
  sm: 4,
  md: 6,
  lg: 8,
  xl: 10,
  xxl: 12,
  xxxl: 14,
  '4xl': 16,
  '5xl': 18,
  full: 100
};
