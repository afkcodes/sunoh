import { dataExtractor } from '~helpers/common';

import FigureTitle from '~components/FigureTitle/FigureTitle';
import { TileStyleProps } from '~types/component.types';
import { tileSize } from './tile.styles';

interface TileProps {
  data: any;
  config: any;
  styleConfig: TileStyleProps;
  onClick: (params: any) => void;
}

const Tile: React.FC<TileProps> = ({ data, config, styleConfig, onClick }) => {
  const src = dataExtractor(data, config.posterImage);
  const title = dataExtractor(data, config.name);
  const subTitle = dataExtractor(data, config.city);
  const dominantColor = dataExtractor(data, config.dominantColor);

  const onTileClick = () => {
    onClick(data);
  };

  return (
    <button
      className={`flex flex-col p-0 m-0 
      overflow-hidden
      ${styleConfig.shape === 'circle' ? 'text-center' : 'text-start'}
      ${tileSize[styleConfig.size]}
    `}
      onClick={onTileClick}>
      <FigureTitle
        figureConfig={{
          src: src,
          alt: `${title} poster`,
          dominantColor: dominantColor,
          fit: styleConfig.fit,
          shape: styleConfig.shape,
          size: styleConfig.size,
        }}
        titleConfig={{
          title,
          subTitle,
        }}
        gap='xs'
        orientation='vertical'
      />
    </button>
  );
};

export default Tile;
