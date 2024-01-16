import Button from '~components/Button/Button';
import FigureTitle from '~components/FigureTitle/FigureTitle';
import PlayerStatusIndicator from '~components/PlayerStatusIndicator/PlayerStatusIndicator';
import { AudioContextProps } from '~contexts/audioX.context';
import { getColorWithOpacity } from '~helpers/common';
import { Track } from '~types/common.types';

interface MiniPlayerProps {
  currentTrack: Track;
  audio: AudioContextProps;
  onClick: () => void;
}

const MiniPlayer: React.FC<MiniPlayerProps> = ({ currentTrack, audio, onClick }) => {
  return (
    <div
      style={{
        backgroundColor: currentTrack.dominantColor
          ? getColorWithOpacity(currentTrack.dominantColor as string, 0.3)
          : 'rgba(30,30,30,0.6)',
        backdropFilter: 'blur(10px)'
      }}
      className={` transition-all duration-300 w-full flex justify-between items-center px-3 py-2 `}
    >
      <button className='w-[90%] p-0 m-0' onClick={onClick}>
        <FigureTitle
          orientation='horizontal'
          gap='xs'
          figureConfig={{
            src: currentTrack?.artwork ? currentTrack.artwork[0].src : '',
            alt: `${currentTrack.title} poster image`,
            size: '2xs',
            shape: 'rounded_square'
          }}
          titleConfig={{
            title: currentTrack.title,
            subTitle: currentTrack.artist as string,
            titleFontSize: 'md',
            subtitleFontSize: 'xs'
          }}
        />
      </button>

      <Button
        onClick={() => {
          audio.audioState.playbackState !== 'playing' ? audio.play() : audio.pause();
        }}
        variant='unstyled'
        icon={<PlayerStatusIndicator currentTrack={currentTrack as Track} />}
      />
    </div>
  );
};

export default MiniPlayer;
