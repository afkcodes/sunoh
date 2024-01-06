import { proxy } from 'valtio';
import { SearchItem } from '~types/component.types';

export const baseState = proxy({
  searchHistory: [] as SearchItem[]
});

export const baseActions = {
  updateSearchHistory: (history: SearchItem[]) => {
    baseState.searchHistory = history;
  }
};
