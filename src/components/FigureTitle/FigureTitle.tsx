import Figure from '~components/Figure/Figure';
import { tileSize } from '~components/Tile/tile.styles';
import TitleSubtitle from '~components/TitleSubtitle/TitleSubtitle';
import { gapStyle } from '~styles/base.style';
import { FigureSize, Spacing } from '~types/common.types';
import { FigureProps, TitleSubtitleProps } from '~types/component.types';

interface FigureTitleProps {
  figureConfig: FigureProps;
  titleConfig: TitleSubtitleProps;
  orientation: 'horizontal' | 'vertical';
  gap: Spacing;
}

const FigureTitle: React.FC<FigureTitleProps> = ({
  figureConfig = {
    src: '',
    size: '2xs'
  },
  titleConfig,
  orientation = 'vertical',
  gap = 'sm'
}) => {
  const orientationStyles =
    orientation === 'vertical'
      ? `flex flex-col ${gapStyle[gap]}`
      : `flex items-center justify-center ${gapStyle[gap]}`;

  return (
    <div
      className={`
      ${orientationStyles}
      text-start
    `}
    >
      <div
        className={`
      ${tileSize[figureConfig.size as FigureSize]}
      `}
      >
        <Figure
          src={figureConfig.src}
          alt={`${figureConfig.alt} poster`}
          size={figureConfig.size}
          shape={figureConfig.shape}
          fit={figureConfig.fit}
          dominantColor={figureConfig.dominantColor}
        />
      </div>
      <TitleSubtitle
        title={titleConfig.title}
        subTitle={titleConfig.subTitle}
        titleFontSize={titleConfig.titleFontSize}
        titleFontWeight={titleConfig.titleFontWeight}
        subtitleFontSize={titleConfig.subtitleFontSize}
        subtitleFontWeight={titleConfig.subtitleFontWeight}
      />
    </div>
  );
};

export default FigureTitle;
