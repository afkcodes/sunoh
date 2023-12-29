import { ImageLoading } from "~types/common.types";

interface Image {
  src: string;
  alt: string | undefined;
  height?: number | string | undefined;
  loading?: ImageLoading;
  width?: number | string | undefined;
}

const Image: React.FC<Image> = ({
  src,
  alt,
  height = "100%",
  width = "100%",
  loading = "lazy",
}) => {
  return (
    <img src={src} alt={alt} height={height} width={width} loading={loading} />
  );
};

Image.displayName = "Image";

export default Image;
