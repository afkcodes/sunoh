import React from 'react';
import { View } from 'react-native';
import getStyles from './main.styles';

interface MainProps {
  children: React.ReactElement;
}
const Main: React.FC<MainProps> = ({ children }) => {
  const { styles } = getStyles('dark');
  return <View style={styles.main}>{children}</View>;
};

export default Main;
