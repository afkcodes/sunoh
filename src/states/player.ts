import { AUDIO_STATE, AudioState } from 'audio_x';
import { proxy } from 'valtio';
import { Track } from '~types/common.types';

interface PlayerActions {
  setCurrentTrack: (track: Track) => void;
  setPlayerState: (state: AudioState) => void;
}

export const playerState: {
  currentTrack: Track | null;
  audioState: AudioState;
} = proxy({
  currentTrack: null,
  audioState: AUDIO_STATE,
});

export const playerActions: PlayerActions = {
  setCurrentTrack: (track: Track) => {
    playerState.currentTrack = track;
  },
  setPlayerState: (state: AudioState) => {
    playerState.audioState = state;
  },
};
