import React, { useContext } from 'react';
import { Text, type TextStyle } from 'react-native';
import { ThemeContext } from '~contexts/theme.context';
import { type BaseColorType, type FontFamilyWeightType } from '~types/components.types';
import getTextStyles from './sText.styles';

interface STextProps {
  children: string;
  color?: BaseColorType;

  family?: FontFamilyWeightType;
}
const SText: React.FC<STextProps & TextStyle> = (props) => {
  const { theme } = useContext(ThemeContext);
  const { children, color, family, ...rest } = props;
  const { styles } = getTextStyles(theme, color, family, rest);
  return <Text style={styles.text}>{children}</Text>;
};

export default SText;
