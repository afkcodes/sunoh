import { StyleSheet, type ViewStyle } from 'react-native';
import { theme } from '~styles/theme';
import { type BaseColorType, type ThemeType } from '~types/components.types';

const getViewStyles = (
  currentTheme: ThemeType = 'light',
  color: BaseColorType = 'primary',
  rest: ViewStyle
) => {
  const styles = StyleSheet.create({
    view: {
      backgroundColor: theme[currentTheme].background[color],
      ...rest
    }
  });

  return { styles };
};

export default getViewStyles;
