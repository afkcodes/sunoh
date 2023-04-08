import { colors } from './colors';

export const theme = {
  base: {
    primary: colors.red[500],
    navBarIcons: colors.red[600]
  },
  light: {
    background: {
      primary: colors.white[500],
      secondary: colors.gray[500]
    },
    text: {
      primary: colors.black[800],
      secondary: colors.gray[900]
    },
    button: {
      primary: colors.red[600],
      active: colors.red[700]
    },
    navigation: {
      background: colors.gray[300],
      inactiveColor: colors.black[800]
    }
  },
  dark: {
    background: {
      primary: colors.amoled[500],
      secondary: colors.black[500]
    },
    text: {
      primary: colors.gray[50],
      secondary: colors.black[200]
    },
    button: {
      primary: colors.red[700],
      active: colors.red[600]
    },
    navigation: {
      background: colors.black[700],
      inactiveColor: colors.black[200]
    }
  }
};

export const FONTS = {
  regular: 'Gilroy-Regular',
  medium: 'Gilroy-Medium',
  semiB: 'Gilroy-Semibold',
  bold: 'Gilroy-Bold',
  sizeXS: 8,
  sizeS: 12,
  sizeSR: 14,
  sizeR: 16,
  sizeXR: 20,
  sizeM: 24,
  sizeXM: 28,
  sizeL: 32,
  sizeXL: 36
};
