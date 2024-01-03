import { Fragment, useContext } from "react";
import {
  RiLoader5Line,
  RiPauseCircleFill,
  RiPlayCircleFill,
} from "react-icons/ri";
import { AudioXContext } from "~contexts/audioX.context";
import { isColorDark } from "~helpers/common";
import { Track } from "~types/common.types";

interface PlayerStatusIndicatorProps {
  currentTrack: Track;
}

const PlayerStatusIndicator: React.FC<PlayerStatusIndicatorProps> = ({
  currentTrack,
}) => {
  const audio = useContext(AudioXContext);

  const isPlaying = audio.audioState.playbackState === "playing";
  const isBuffering = audio.audioState.playbackState === "buffering";

  return (
    <Fragment>
      {!isPlaying && !isBuffering ? (
        <RiPlayCircleFill
          color={
            isColorDark(currentTrack.dominantColor)
              ? "white"
              : currentTrack.dominantColor
          }
          className=""
          size={48}
        />
      ) : null}

      {isPlaying ? (
        <RiPauseCircleFill
          color={
            isColorDark(currentTrack.dominantColor)
              ? "white"
              : currentTrack.dominantColor
          }
          className=""
          size={48}
        />
      ) : null}

      {isBuffering && !isPlaying ? (
        <RiLoader5Line
          color={
            isColorDark(currentTrack.dominantColor)
              ? "white"
              : currentTrack.dominantColor
          }
          size={48}
          className="animate-spin"
        />
      ) : null}
    </Fragment>
  );
};

export default PlayerStatusIndicator;
