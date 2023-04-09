import React, { useContext } from 'react';
import { View, type ViewProps, type ViewStyle } from 'react-native';
import { ThemeContext } from '~contexts/theme.context';
import { type BaseColorType } from '~types/components.types';
import getViewStyles from './sView.style';

interface SViewProps {
  children: React.ReactElement | React.ReactElement[];
  color?: BaseColorType;
  viewConfig?: ViewProps;
}
const SView: React.FC<SViewProps & ViewStyle> = (props) => {
  const { theme } = useContext(ThemeContext);
  const { children, color, viewConfig, ...rest } = props;
  const { styles } = getViewStyles(theme, color, rest);
  return (
    <View style={styles.view} {...viewConfig}>
      {children}
    </View>
  );
};

export default SView;
