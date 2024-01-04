import { fitStrategy } from '~components/Figure/figure.styles';
import { FitStrategy, ImageLoading } from '~types/common.types';

interface Image {
  src: string;
  alt: string | undefined;
  height?: number | string | undefined;
  loading?: ImageLoading;
  width?: number | string | undefined;
  fit: FitStrategy;
}

const Image: React.FC<Image> = ({
  src,
  alt,
  height = '100%',
  width = '100%',
  loading = 'lazy',
  fit = 'cover'
}) => {
  return (
    <img
      src={src}
      alt={alt}
      height={height}
      width={width}
      loading={loading}
      className={` h-full w-full ${fitStrategy[fit]}`}
    />
  );
};

Image.displayName = 'Image';

export default Image;
