import { proxy } from 'valtio';

export const tabState = proxy({
  currentTab: 0,
  data: null,
  isInputFocussed: false
});

export const tabActions = {
  setTab: (tabId: number, data: any = null) => {
    tabState.currentTab = tabId;
    tabState.data = data;
  }
};
