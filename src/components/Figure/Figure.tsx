import Image from '~components/Image/Image';

import { memo } from 'react';
import { FigureProps } from '~types/component.types';
import { figureShape, figureSize } from './figure.styles';

const Figure: React.FC<FigureProps> = memo(
  ({
    src,
    alt,
    shape = 'default',
    size = 'md',
    loading = 'lazy',
    mode = 'single',
    fit = 'cover',
    dominantColor = ''
  }) => {
    return (
      <figure
        className={`
        ${figureSize[size]}
        ${figureShape[shape]}
        group pointer-events-none relative
      `}
        tabIndex={0}
        style={{ backgroundColor: dominantColor }}
      >
        {mode === 'single' ? <Image src={src} alt={alt} loading={loading} fit={fit} /> : null}
      </figure>
    );
  }
);

export default Figure;
