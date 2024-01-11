import AudioListItem from '~components/AudioListItem/AudioListItem';
import { AudioListItemContainerProps } from '~types/component.types';

const AudioListItemContainer: React.FC<AudioListItemContainerProps> = ({
  data,
  config,
  onClick
}) => {
  return (
    <div className='flex flex-col gap-4 px-3'>
      {data.map((item) => (
        <AudioListItem key={item.id} data={item} config={config} onClick={onClick} />
      ))}
    </div>
  );
};

export default AudioListItemContainer;
