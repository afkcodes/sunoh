import { StyleSheet, type ViewStyle } from 'react-native';
import { theme } from '~styles/theme';
import { type ViewColorType, type themeType } from '~types/components.types';

const getViewStyles = (
  currentTheme: themeType = 'light',
  color: ViewColorType = 'primary',
  rest: ViewStyle
) => {
  const styles = StyleSheet.create({
    main: {
      backgroundColor: theme[currentTheme].background[color],
      ...rest
    }
  });

  return { styles };
};

export default getViewStyles;
