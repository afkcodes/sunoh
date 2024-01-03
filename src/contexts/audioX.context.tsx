import { AUDIO_STATE, AudioState, AudioX } from "audio_x";
import { createContext, useState } from "react";

interface AudioXProviderProps {
  children: React.ReactNode;
  audioX: AudioX;
}

export const AudioXContext = createContext({
  audioState: AUDIO_STATE,
  play: () => {},
  pause: () => {},
  stop: () => {},
});

const AudioXProvider: React.FC<AudioXProviderProps> = ({
  children,
  audioX,
}) => {
  const [audioState, setAudioState] = useState(AUDIO_STATE);

  audioX.subscribe("AUDIO_X_STATE", (data: AudioState) => {
    setAudioState(data);
  });

  const play = () => {
    audioX.play();
  };

  const pause = () => {
    audioX.pause();
  };

  const stop = () => {
    audioX.stop();
  };

  return (
    <AudioXContext.Provider value={{ audioState, pause, play, stop }}>
      {children}
    </AudioXContext.Provider>
  );
};

export default AudioXProvider;
