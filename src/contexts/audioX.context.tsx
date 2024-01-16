/* eslint-disable @typescript-eslint/no-unused-vars */
import { AUDIO_STATE, AudioState, AudioX, MediaTrack, QueuePlaybackType } from 'audio_x';
import { createContext, useEffect } from 'react';
import { useSnapshot } from 'valtio';
import { storeLastTrack } from '~helpers/business';
import { playerActions, playerState } from '~states/player';
import { Track } from '~types/common.types';
import { storage } from '~utils/storage';

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
  addToQueue: (_queue: MediaTrack[], _playbackType: QueuePlaybackType) => void;
  clearQueue: () => void;
  playNext: () => void;
  playPrevious: () => void;
  addMediaAndPlay: (_track?: MediaTrack | null, _fetchFn?: (mediaTrack: MediaTrack) => any) => void;
}

export const AudioXContext: React.Context<AudioContextProps> = createContext({
  audioState: AUDIO_STATE,
  play: () => {},
  pause: () => {},
  stop: () => {},
  reset: () => {},
  addMediaAndPlay: (_track?: MediaTrack | null, _fetchFn?: (mediaTrack: MediaTrack) => any) => {},
  addToQueue: (_queue: MediaTrack[], _playbackType: QueuePlaybackType) => {},
  clearQueue: () => {},
  playNext: () => {},
  playPrevious: () => {}
});

const AudioXProvider: React.FC<AudioXProviderProps> = ({ children, audioX }) => {
  const { audioState } = useSnapshot(playerState);

  useEffect(() => {
    const lastTrack: string | null = storage.getItem('current_track');
    if (lastTrack) {
      const track: Track = JSON.parse(lastTrack);
      playerState.currentTrack = track;
      audioX.addMedia(track);
      if (track.progress) {
        audioX.seek(track.progress);
      }
    }
  }, [audioX]);

  audioX.subscribe('AUDIO_X_STATE', (state: AudioState) => {
    playerActions.setPlayerState(state);
    if (playerState.currentTrack) {
      playerState.currentTrack.progress = state.progress as number;
      storeLastTrack(playerState.currentTrack);
    }
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

  const addMediaAndPlay = (
    track?: MediaTrack | null,
    fetchFn?: (mediaTrack: MediaTrack) => any
  ) => {
    audioX.addMediaAndPlay(track, fetchFn);
  };

  const reset = () => {
    audioX.reset();
  };

  const addToQueue = (queue: MediaTrack[], playbackType: QueuePlaybackType = 'DEFAULT') => {
    audioX.addQueue(queue, playbackType);
  };

  const clearQueue = () => {
    audioX.clearQueue();
  };

  const playNext = () => {
    audioX.playNext();
  };

  const playPrevious = () => {
    audioX.playPrevious();
  };

  return (
    <AudioXContext.Provider
      value={{
        audioState: audioState as AudioState,
        pause,
        play,
        stop,
        addMediaAndPlay,
        reset,
        addToQueue,
        clearQueue,
        playNext,
        playPrevious
      }}
    >
      {children}
    </AudioXContext.Provider>
  );
};

export default AudioXProvider;
