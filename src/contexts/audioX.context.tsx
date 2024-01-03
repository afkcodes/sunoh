/* eslint-disable @typescript-eslint/no-unused-vars */
import { AUDIO_STATE, AudioState, AudioX, MediaTrack } from "audio_x";
import { createContext, useEffect, useState } from "react";
import { playerState } from "~states/player";
import { storage } from "~utils/storage";

interface AudioXProviderProps {
  children: React.ReactNode;
  audioX: AudioX;
}

export interface AudioContextProps {
  audioState: AudioState;
  play: () => void;
  pause: () => void;
  stop: () => void;
  reset: () => void;
  addMediaAndPlay: (_track: MediaTrack) => void;
}

export const AudioXContext: React.Context<AudioContextProps> = createContext({
  audioState: AUDIO_STATE,
  play: () => {},
  pause: () => {},
  stop: () => {},
  reset: () => {},
  addMediaAndPlay: (_track: MediaTrack) => {},
});

const AudioXProvider: React.FC<AudioXProviderProps> = ({
  children,
  audioX,
}) => {
  const [audioState, setAudioState] = useState(AUDIO_STATE);

  useEffect(() => {
    const lastTrack: string | null = storage.getItem("current_track");
    if (lastTrack) {
      playerState.currentTrack = JSON.parse(lastTrack);
    }
  }, []);

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

  const addMediaAndPlay = (track: MediaTrack) => {
    audioX.addMediaAndPlay(track);
  };

  const reset = () => {
    audioX.reset();
  };

  return (
    <AudioXContext.Provider
      value={{ audioState, pause, play, stop, addMediaAndPlay, reset }}
    >
      {children}
    </AudioXContext.Provider>
  );
};

export default AudioXProvider;
