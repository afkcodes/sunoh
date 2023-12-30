import { Fragment } from "react";
import SnapCarousel from "~components/Carousel/Carousel";
import Tile from "~components/Tile/Tile";
import { isValidArray } from "~helpers/common";
import { TileContainerProps } from "~types/component.types";

const TileContainer: React.FC<TileContainerProps> = ({
  data,
  config,
  tileStyleConfig,
  onClick,
  displayType = "default",
}) => {
  const Tiles = isValidArray(data)
    ? data.map((item) => (
        <Fragment key={item._id}>
          {displayType === "carousel" ? (
            <li key={item._id}>
              <Tile
                config={config}
                styleConfig={tileStyleConfig}
                data={item}
                onClick={onClick}
              />
            </li>
          ) : (
            <Tile
              config={config}
              styleConfig={tileStyleConfig}
              data={item}
              key={item._id}
              onClick={onClick}
            />
          )}
        </Fragment>
      ))
    : null;

  return (
    <>
      {displayType === "carousel" ? (
        <SnapCarousel type="DEFAULT">{Tiles}</SnapCarousel>
      ) : (
        Tiles
      )}
    </>
  );
};

export default TileContainer;
