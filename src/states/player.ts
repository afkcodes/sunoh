import { proxy } from "valtio";
import { Track } from "~types/common.types";

interface PlayerActions {
  setCurrentTrack: (track: Track) => void;
}

export const playerState: { currentTrack: Track | null } = proxy({
  currentTrack: null,
});

export const playerActions: PlayerActions = {
  setCurrentTrack: (track: Track) => {
    playerState.currentTrack = track;
  },
};
