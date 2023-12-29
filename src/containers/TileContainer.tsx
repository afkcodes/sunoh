import Tile from "~components/Tile/Tile";
import { isValidArray } from "~helpers/common";
import { TileStyleProps } from "~types/component.types";

interface TileContainerProps {
  data: any[];
  config: any;
  tileStyleConfig: TileStyleProps;
  onClick: (item: any) => void;
}

const TileContainer: React.FC<TileContainerProps> = ({
  data,
  config,
  tileStyleConfig,
  onClick,
}) => {
  return (
    <>
      {isValidArray(data)
        ? data.map((item) => (
            <Tile
              config={config}
              styleConfig={tileStyleConfig}
              data={item}
              key={item._id}
              onClick={onClick}
            />
          ))
        : null}
    </>
  );
};

export default TileContainer;
