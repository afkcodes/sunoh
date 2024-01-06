import FigureTitle from '~components/FigureTitle/FigureTitle';
import { dataExtractor } from '~helpers/common';

interface AudioListItemProps {
  data: any;
  config: any;
  onClick: (item?: any) => void;
}

const AudioListItem: React.FC<AudioListItemProps> = ({ data, config, onClick }) => {
  const src = dataExtractor(data, config.posterImage);
  const title = dataExtractor(data, config.name);
  const subTitle = dataExtractor(data, config.city);
  const dominantColor = dataExtractor(data, config.dominantColor);

  const onTileClick = () => {
    onClick(data);
  };
  return (
    <button onClick={onTileClick} className='w-full p-0 m-0 overflow-hidden'>
      <FigureTitle
        figureConfig={{
          src: src,
          alt: `${title} poster`,
          fit: 'fill',
          loading: 'lazy',
          shape: 'rounded_square',
          size: '2xs',
          dominantColor: dominantColor
        }}
        gap='xs'
        orientation='horizontal'
        titleConfig={{
          title: subTitle,
          subTitle: subTitle
        }}
      />
    </button>
  );
};

export default AudioListItem;
