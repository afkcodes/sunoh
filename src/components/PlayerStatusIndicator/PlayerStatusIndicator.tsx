import { Fragment, useContext } from 'react';
import { RiLoader5Line, RiPauseCircleFill, RiPlayCircleFill } from 'react-icons/ri';
import { AudioXContext } from '~contexts/audioX.context';
import { isColorDark } from '~helpers/common';
import { Track } from '~types/common.types';

interface PlayerStatusIndicatorProps {
  currentTrack: Track;
  size?: number;
}

const PlayerStatusIndicator: React.FC<PlayerStatusIndicatorProps> = ({
  currentTrack,
  size = 35
}) => {
  const audio = useContext(AudioXContext);

  const isPlaying = audio.audioState.playbackState === 'playing';
  const isBuffering = audio.audioState.playbackState === 'buffering';
  const isDark = currentTrack.dominantColor
    ? isColorDark(currentTrack.dominantColor as string)
    : '#121212';

  return (
    <Fragment>
      {!isPlaying && !isBuffering ? (
        <RiPlayCircleFill
          color={isDark ? 'white' : currentTrack.dominantColor}
          className=''
          size={size}
        />
      ) : null}

      {isPlaying ? (
        <RiPauseCircleFill
          color={isDark ? 'white' : currentTrack.dominantColor}
          className=''
          size={size}
        />
      ) : null}

      {isBuffering && !isPlaying ? (
        <RiLoader5Line
          color={isDark ? 'white' : currentTrack.dominantColor}
          size={size}
          className='animate-spin'
        />
      ) : null}
    </Fragment>
  );
};

export default PlayerStatusIndicator;
