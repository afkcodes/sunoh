import { baseActions } from '~states/base';
import { playerState } from '~states/player';
import { Track } from '~types/common.types';
import { SearchItem } from '~types/component.types';
import { storage } from '~utils/storage';
import { findDuplicatesAndRemove, isValidArray } from './common';

export const saveHistory = (keyword: string) => {
  const searchHistory: string | null = storage.getItem('search_history');

  if (searchHistory && isValidArray(JSON.parse(searchHistory))) {
    const appendedData = findDuplicatesAndRemove(
      [{ text: keyword }, ...JSON.parse(searchHistory)] as SearchItem[],
      'text',
      5
    );
    storage.setItem('search_history', JSON.stringify(appendedData));
    baseActions.updateSearchHistory(appendedData);
  } else {
    storage.setItem('search_history', JSON.stringify([{ text: keyword }]));
    baseActions.updateSearchHistory([{ text: keyword }]);
  }
};

export const updateTrackAndPlayerState = (track: Track) => {
  storage.setItem('current_track', JSON.stringify(track));
  playerState.currentTrack = track;
};

export const storeLastTrack = (track: Track) => {
  storage.setItem('current_track', JSON.stringify(track));
};
