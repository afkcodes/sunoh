import { colors } from './colors';

export const theme: any = {
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
      primary: colors.teal[600],
      active: colors.teal[700]
    }
  },
  dark: {
    background: {
      primary: colors.black[800],
      secondary: colors.black[500]
    },
    text: {
      primary: colors.gray[50],
      secondary: colors.black[200]
    },
    button: {
      primary: colors.teal[800],
      active: colors.teal[700]
    }
  }
};
