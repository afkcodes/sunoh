import React from 'react';
import { View } from 'react-native';
import useTheme from '~helpers/hooks/useTheme.hook';

interface MainProps {
  children: React.ReactElement;
}
const Main: React.FC<MainProps> = ({ children }) => {
  useTheme();
  return <View style={{ flex: 1 }}>{children}</View>;
};

export default Main;
