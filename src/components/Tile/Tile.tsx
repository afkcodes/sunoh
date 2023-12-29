import Figure from "~components/Figure/Figure";
import TitleSubtitle from "~components/TitleSubtitle/TitleSubtitle";
import { Shape, TileSize } from "~types/common.types";
import { FigureProps, TitleSubtitleProps } from "~types/component.types";
import { tileShape, tileSize } from "./tile.styles";

interface TileProps {
  figureConfig: FigureProps;
  titleSubtitleConfig: TitleSubtitleProps;
  tileConfig: {
    size: TileSize;
    shape: Shape;
  };
}

const Tile: React.FC<TileProps> = ({
  tileConfig = { size: "2xl", shape: "rounded_square" },
  figureConfig = {
    src: "",
    size: "2xl",
    alt: "",
    shape: "rounded_square",
    fit: "contain",
  },
  titleSubtitleConfig = {
    title: "",
    subTitle: "",
  },
}) => {
  return (
    <div
      className={`flex flex-col gap-1
      ${tileShape[tileConfig.shape]}
      ${tileSize[tileConfig.size]}
    `}
    >
      <Figure
        src={figureConfig.src}
        alt={figureConfig.alt}
        size={figureConfig.size}
        shape={figureConfig.shape}
        fit={figureConfig.fit}
      />
      <TitleSubtitle
        title={titleSubtitleConfig.title}
        subTitle={titleSubtitleConfig.subTitle}
      />
    </div>
  );
};

export default Tile;
