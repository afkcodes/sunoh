import React from 'react';
import { Text, type TextStyle } from 'react-native';
import { type BaseColorType, type FontFamilyWeightType } from '~types/components.types';
import getTextStyles from './sText.styles';

interface STextProps {
  children: string;
  color?: BaseColorType;
  family?: FontFamilyWeightType;
}
const SText: React.FC<STextProps & TextStyle> = (props) => {
  const { children, color, family, ...rest } = props;
  const { styles } = getTextStyles('dark', color, family, rest);
  return <Text style={styles.text}>{children}</Text>;
};

export default SText;
