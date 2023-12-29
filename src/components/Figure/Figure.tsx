import Image from "~components/Image/Image";

import { FigureProps } from "~types/component.types";
import { figureShape, figureSize } from "./figure.styles";

const Figure: React.FC<FigureProps> = ({
  src,
  alt,
  shape = "default",
  size = "md",
  loading = "lazy",
  mode = "single",
  fit = "cover",
  onLoad = () => {},
}) => {
  return (
    <figure
      className={`
        ${figureSize[size]}
        ${figureShape[shape]}
        group pointer-events-none relative
      `}
      tabIndex={0}
    >
      {mode === "single" ? (
        <Image src={src} alt={alt} loading={loading} />
      ) : null}
    </figure>
  );
};

export default Figure;
