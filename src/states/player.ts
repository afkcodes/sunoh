import { proxy } from "valtio";
import { Track } from "~types/common.types";

interface PlayerActions {
  setCurrentTrack: (track: Track) => void;
}

const baseTrack: Track = {
  artwork: [
    {
      src: "",
      name: "",
      sizes: "200x200",
    },
  ],
  source: "",
  dominantColor: "",
  id: "",
  title: "",
  artist: "",
};

export const playerState = proxy({
  currentTrack: baseTrack,
});

export const playerActions: PlayerActions = {
  setCurrentTrack: (track: Track) => {
    playerState.currentTrack = track;
  },
};
