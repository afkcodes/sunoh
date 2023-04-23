import React, { useContext } from 'react';
import { Text, type TextProps, type TextStyle } from 'react-native';
import { ThemeContext } from '~contexts/theme.context';
import { type BaseColorType, type FontFamilyWeightType } from '~types/components.types';
import getTextStyles from './sText.styles';

interface STextProps {
  children: string;
  color?: BaseColorType;
  family?: FontFamilyWeightType;
  textConfig?: TextProps;
}
const SText: React.FC<STextProps & TextStyle> = (props) => {
  const { theme } = useContext(ThemeContext);
  const { children, color, family, textConfig, ...rest } = props;
  const { styles } = getTextStyles(theme, color, family, rest);
  return (
    <Text style={styles.text} {...textConfig}>
      {children}
    </Text>
  );
};

export default SText;
