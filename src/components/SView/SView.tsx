import React from 'react';
import { View, type ViewStyle } from 'react-native';
import { type ViewColorType } from '~types/components.types';
import getViewStyles from './sView.style';

interface SViewProps {
  children: React.ReactElement;
  color?: ViewColorType;
}
const SView: React.FC<SViewProps & ViewStyle> = (props) => {
  const { children, color, ...rest } = props;
  const { styles } = getViewStyles('dark', color, rest);
  return <View style={styles.main}>{children}</View>;
};

export default SView;
