import React from 'react';
import { Pressable } from 'react-native';
import { type Priority } from 'react-native-fast-image';
import { SView } from '~components';
import SImage from '~components/Image/SImage';
import SText from '~components/SText/SText';
import { borderRadius, fontSize, spacing } from '~styles/utilities';
import { type BorderRadius, type FontSize, type TileSize } from '~types/components.types';

const tileSizeMap = {
  xxs: {
    height: 40,
    width: 40
  },
  xs: {
    height: 60,
    width: 60
  },
  sm: {
    height: 80,
    width: 80
  },
  md: {
    height: 100,
    width: 100
  },
  lg: {
    height: 120,
    width: 120
  },
  xl: {
    height: 140,
    width: 140
  },
  xxl: {
    height: 160,
    width: 160
  }
};
interface TileConfig {
  src: string;
  size?: TileSize;
  priority?: Priority;
  radius?: BorderRadius;
  titleFontSize?: FontSize;
  subtitleFontSize?: FontSize;
  onClick?: () => void;
}

const Tile: React.FC<TileConfig> = ({
  src,
  size = 'md',
  priority = 'normal',
  radius = 'xs',
  titleFontSize = 'sm',
  subtitleFontSize = 'xs',
  onClick = () => {}
}) => {
  return (
    <Pressable onPress={onClick}>
      <SView height={tileSizeMap[size].height} width={tileSizeMap[size].width}>
        <SImage
          src={src}
          priority={priority}
          borderRadius={borderRadius[radius]}
          height={'100%'}
          width={'100%'}
        />
        <SView>
          <SText
            paddingTop={spacing.xs}
            fontSize={fontSize[titleFontSize]}
            textConfig={{ ellipsizeMode: 'tail', numberOfLines: 1 }}
          >
            Hanuman Chalisa - Hanuman
          </SText>
          <SText
            paddingTop={spacing.none}
            fontSize={fontSize[subtitleFontSize]}
            textConfig={{ ellipsizeMode: 'tail', numberOfLines: 1 }}
          >
            GowraHari, Saicharan Bhaskaruni
          </SText>
        </SView>
      </SView>
    </Pressable>
  );
};

export default Tile;
