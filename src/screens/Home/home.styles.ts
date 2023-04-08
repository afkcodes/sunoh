import { StyleSheet } from 'react-native';
import { theme } from '~styles';

const getHomeStyles = (currentTheme: 'dark' | 'light' = 'light') => {
  const styles = StyleSheet.create({
    main: {
      backgroundColor: theme[currentTheme].background.primary,
      display: 'flex',
      flex: 1
    }
  });

  return { styles };
};

export default getHomeStyles;
