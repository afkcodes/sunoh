import { StateNavigator } from 'navigation';

export const homeNavigator = new StateNavigator([
  { key: 'home', trackCrumbTrail: true },
  { key: 'profile', trackCrumbTrail: true },
  { key: 'podcast', trackCrumbTrail: true },
  { key: 'settings', trackCrumbTrail: true }
]);

export const profileNavigator = new StateNavigator([
  { key: 'podcast', trackCrumbTrail: true },
  { key: 'home', trackCrumbTrail: true },
  { key: 'profile', trackCrumbTrail: true },
  { key: 'settings', trackCrumbTrail: true }
]);

export const podcastNavigator = new StateNavigator([
  { key: 'home', trackCrumbTrail: true },
  { key: 'profile', trackCrumbTrail: true },
  { key: 'podcast', trackCrumbTrail: true },
  { key: 'settings', trackCrumbTrail: true }
]);

export const settingsNavigator = new StateNavigator([
  { key: 'home', trackCrumbTrail: true },
  { key: 'profile', trackCrumbTrail: true },
  { key: 'podcast', trackCrumbTrail: true },
  { key: 'settings', trackCrumbTrail: true }
]);
