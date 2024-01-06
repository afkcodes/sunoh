import AudioListItem from '~components/AudioListItem/AudioListItem';

interface AudioListItemContainerProps {
  data: any[];
  config: any;
  onClick: (item?: any) => void;
}

const AudioListItemContainer: React.FC<AudioListItemContainerProps> = ({
  data,
  config,
  onClick
}) => {
  return (
    <div className='flex flex-col gap-4 px-3'>
      {data.map((item) => (
        <AudioListItem data={item} config={config} onClick={onClick} />
      ))}
    </div>
  );
};

export default AudioListItemContainer;
