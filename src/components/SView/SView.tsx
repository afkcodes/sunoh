import React from 'react';
import { View, type ViewStyle } from 'react-native';
import { type BaseColorType } from '~types/components.types';
import getViewStyles from './sView.style';

interface SViewProps {
  children: React.ReactElement;
  color?: BaseColorType;
}
const SView: React.FC<SViewProps & ViewStyle> = (props) => {
  const { children, color, ...rest } = props;
  const { styles } = getViewStyles('dark', color, rest);
  return <View style={styles.view}>{children}</View>;
};

export default SView;
