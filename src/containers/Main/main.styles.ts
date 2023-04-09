import { StyleSheet } from 'react-native';
import { theme } from '~styles/theme';

const getStyles = (currentTheme: 'dark' | 'light' = 'light') => {
  const styles = StyleSheet.create({
    main: {
      backgroundColor: theme[currentTheme].background.primary,
      display: 'flex',
      flex: 1,
      paddingHorizontal: 8
    }
  });

  return { styles };
};

export default getStyles;
