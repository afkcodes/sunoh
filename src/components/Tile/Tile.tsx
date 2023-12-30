import Figure from "~components/Figure/Figure";
import TitleSubtitle from "~components/TitleSubtitle/TitleSubtitle";
import { dataExtractor } from "~helpers/common";

import { TileStyleProps } from "~types/component.types";
import { tileSize } from "./tile.styles";

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
      className={`flex flex-col gap-1 p-0 m-0 
      overflow-hidden
      ${styleConfig.shape === "circle" ? "text-center" : "text-start"}
      ${tileSize[styleConfig.size]}
    `}
      onClick={onTileClick}
    >
      <Figure
        src={src}
        alt={`${title} poster`}
        size={styleConfig.size}
        shape={styleConfig.shape}
        fit={styleConfig.fit}
        dominantColor={dominantColor}
      />
      <TitleSubtitle title={title} subTitle={subTitle} />
    </button>
  );
};

export default Tile;
