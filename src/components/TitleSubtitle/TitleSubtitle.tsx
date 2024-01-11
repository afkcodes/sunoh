import { FontWeightStyle, fontSizeStyle, lineCountStyle } from '~styles/base.style';
import { TitleSubtitleProps } from '~types/component.types';

const TitleSubtitle: React.FC<TitleSubtitleProps> = ({
  title,
  subTitle,
  titleFontSize = 'sm',
  subtitleFontSize = 'xs',
  titleFontWeight = 'semibold',
  subtitleFontWeight = 'medium',
  noOfLinesTitle = 1,
  noOfLinesSubtitle = 1
}) => {
  return (
    <div className='w-full'>
      <p
        className={`
        ${fontSizeStyle[titleFontSize]}
        ${FontWeightStyle[titleFontWeight]}
        ${lineCountStyle[noOfLinesTitle]}
        `}
      >
        {title}
      </p>
      <p
        className={`
        text-textMedium
        ${fontSizeStyle[subtitleFontSize]}
        ${FontWeightStyle[subtitleFontWeight]}
        ${lineCountStyle[noOfLinesSubtitle]}
        `}
      >
        {subTitle}
      </p>
    </div>
  );
};

export default TitleSubtitle;
