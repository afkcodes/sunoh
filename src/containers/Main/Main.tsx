import React, { useContext } from 'react';
import { View } from 'react-native';
import { ThemeContext } from '~contexts/theme.context';
import getStyles from './main.styles';

interface MainProps {
  children: React.ReactElement;
}
const Main: React.FC<MainProps> = ({ children }) => {
  const { theme } = useContext(ThemeContext);
  const { styles } = getStyles(theme);
  return <View style={styles.main}>{children}</View>;
};

export default Main;
