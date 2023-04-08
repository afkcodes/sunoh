import { StyleSheet, type TextStyle } from 'react-native';
import { fonts, theme } from '~styles/theme';
import {
  type BaseColorType,
  type FontFamilyWeightType,
  type ThemeType
} from '~types/components.types';

const getTextStyles = (
  currentTheme: ThemeType = 'light',
  color: BaseColorType = 'primary',
  family: FontFamilyWeightType = 'regular',
  rest: TextStyle
) => {
  const styles = StyleSheet.create({
    text: {
      color: theme[currentTheme].text[color],
      fontFamily: fonts[family],
      ...rest
    }
  });

  return { styles };
};

export default getTextStyles;
