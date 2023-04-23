import { StyleSheet } from 'react-native';
import { type ImageStyle } from 'react-native-fast-image';

const getImagesStyles = (imageStyle: ImageStyle) => {
  const styles = StyleSheet.create({
    image: {
      height: 120,
      width: 120,
      ...imageStyle
    }
  });

  return { styles };
};

export default getImagesStyles;
