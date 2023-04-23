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
      primary: colors.amoled[800],
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
      background: colors.black[800],
      inactiveColor: colors.black[200]
    }
  }
};

// export const fonts = {
//   regular: 'Gilroy-Regular',
//   medium: 'Gilroy-Medium',
//   semibold: 'Gilroy-Semibold',
//   bold: 'Gilroy-Bold'
// };

// export const fonts = {
//   regular: 'Mont-Regular',
//   medium: 'Mont-Book',
//   semibold: 'Mont-SemiBold',
//   heavy: 'Mont-Heavy',
//   bold: 'Mont-Bold'
// };

export const fonts = {
  regular: 'Nexa-Regular',
  medium: 'Nexa-Book',
  semibold: 'Nexa-Bold',
  bold: 'Nexa-XBold',
  heavy: 'Nexa-Heavy'
};
