import { useContext } from "react";
import { useSnapshot } from "valtio";
import Button from "~components/Button/Button";
import FigureTitle from "~components/FigureTitle/FigureTitle";
import PlayerStatusIndicator from "~components/PlayerStatusIndicator/PlayerStatusIndicator";
import { AudioXContext } from "~contexts/audioX.context";
import { getColorWithOpacity } from "~helpers/common";
import { playerState } from "~states/player";
import { Track } from "~types/common.types";

const MiniPlayer = () => {
  const { currentTrack } = useSnapshot(playerState);
  const audio = useContext(AudioXContext);
  // console.log("STATUS A", audio.audioState);

  return (
    <div
      style={{
        backgroundColor: getColorWithOpacity(currentTrack.dominantColor, 0.3),
        backdropFilter: "blur(10px)",
      }}
      className={` transition-all duration-300 w-full flex justify-between items-start px-3 py-2 `}
    >
      <div>
        <FigureTitle
          orientation="horizontal"
          gap="xs"
          figureConfig={{
            src: currentTrack?.artwork ? currentTrack.artwork[0].src : "",
            alt: `${currentTrack.title} poster image`,
            size: "2xs",
            shape: "rounded_square",
          }}
          titleConfig={{
            title: currentTrack.title,
            subTitle: currentTrack.artist as string,
            titleFontSize: "md",
            subtitleFontSize: "xs",
          }}
        />
      </div>

      <Button
        onClick={() => {
          audio.audioState.playbackState !== "playing"
            ? audio.play()
            : audio.pause();
        }}
        variant="unstyled"
        icon={<PlayerStatusIndicator currentTrack={currentTrack as Track} />}
      />
    </div>
  );
};

export default MiniPlayer;
