import React, { useContext } from 'react';
import { View, type ViewStyle } from 'react-native';
import { ThemeContext } from '~contexts/theme.context';
import { type BaseColorType } from '~types/components.types';
import getViewStyles from './sView.style';

interface SViewProps {
  children: React.ReactElement | React.ReactElement[];
  color?: BaseColorType;
}
const SView: React.FC<SViewProps & ViewStyle> = (props) => {
  const { theme } = useContext(ThemeContext);
  const { children, color, ...rest } = props;
  const { styles } = getViewStyles(theme, color, rest);
  return <View style={styles.view}>{children}</View>;
};

export default SView;
