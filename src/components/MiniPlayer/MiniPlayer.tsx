import Button from '~components/Button/Button';
import FigureTitle from '~components/FigureTitle/FigureTitle';
import PlayerStatusIndicator from '~components/PlayerStatusIndicator/PlayerStatusIndicator';
import { AudioContextProps } from '~contexts/audioX.context';
import { getColorWithOpacity } from '~helpers/common';
import { Track } from '~types/common.types';

interface MiniPlayerProps {
  currentTrack: Track;
  audio: AudioContextProps;
}

const MiniPlayer: React.FC<MiniPlayerProps> = ({ currentTrack, audio }) => {
  return (
    <div
      style={{
        backgroundColor: getColorWithOpacity(currentTrack.dominantColor as string, 0.3),
        backdropFilter: 'blur(10px)'
      }}
      className={` transition-all duration-300 w-full flex justify-between items-start px-3 py-2 `}
    >
      <div>
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
      </div>

      <Button
        onClick={() => {
          audio.audioState.playbackState !== 'playing'
            ? audio.addMediaAndPlay(currentTrack) // this is only for live streams update this when a finite audio is played
            : audio.reset();
        }}
        variant='unstyled'
        icon={<PlayerStatusIndicator currentTrack={currentTrack as Track} />}
      />
    </div>
  );
};

export default MiniPlayer;
