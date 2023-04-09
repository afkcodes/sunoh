import { NavigationHandler } from 'navigation-react';
import { NavigationBar, NavigationStack, Scene, TabBar, TabBarItem } from 'navigation-react-native';
import React, { useContext } from 'react';

import Main from '~containers/Main/Main';
import { ThemeContext } from '~contexts/theme.context';
import Home from '~screens/Home';
import Podcast from '~screens/Podcast';
import Profile from '~screens/Profile';
import Settings from '~screens/Settings';
import { fonts, theme } from '~styles/theme';
import { type ThemeType } from '~types/components.types';
import {
  homeNavigator,
  podcastNavigator,
  profileNavigator,
  settingsNavigator
} from './stateNavigators';

const Tabs = () => {
  const { theme: currentTheme } = useContext(ThemeContext);
  return (
    <>
      <NavigationBar hidden={true} />
      <TabBar
        primary={true}
        bottomTabs={true}
        unselectedTintColor={theme[currentTheme as ThemeType].navigation.inactiveColor}
        selectedTintColor={theme.base.navBarIcons}
        barTintColor={theme[currentTheme as ThemeType].navigation.background}
        labelVisibilityMode='unlabeled'
      >
        <TabBarItem
          title='Home'
          image={require('../assets/images/home_inactive.png')}
          fontFamily={fonts.medium}
          fontSize={12}
        >
          <NavigationHandler stateNavigator={homeNavigator}>
            <NavigationStack>
              <Scene stateKey='home'>
                <Main>
                  <Home />
                </Main>
              </Scene>
              <Scene stateKey='podcast'>
                <Podcast />
              </Scene>
            </NavigationStack>
          </NavigationHandler>
        </TabBarItem>

        <TabBarItem
          title='Search'
          image={require('../assets/images/search_inactive.png')}
          fontFamily={fonts.medium}
          fontSize={12}
        >
          <NavigationHandler stateNavigator={profileNavigator}>
            <NavigationStack>
              <Scene stateKey='profile'>
                <Main>
                  <Profile />
                </Main>
              </Scene>
            </NavigationStack>
          </NavigationHandler>
        </TabBarItem>
        <TabBarItem
          title='Podcast'
          image={require('../assets/images/podcast_inactive.png')}
          fontFamily={fonts.medium}
          fontSize={12}
        >
          <NavigationHandler stateNavigator={podcastNavigator}>
            <NavigationStack>
              <Scene stateKey='podcast'>
                <Main>
                  <Podcast />
                </Main>
              </Scene>
            </NavigationStack>
          </NavigationHandler>
        </TabBarItem>
        <TabBarItem
          title='Settings'
          image={require('../assets/images/settings_inactive.png')}
          fontFamily={fonts.medium}
          fontSize={12}
        >
          <NavigationHandler stateNavigator={settingsNavigator}>
            <NavigationStack>
              <Scene stateKey='settings'>
                <Main>
                  <Settings />
                </Main>
              </Scene>
            </NavigationStack>
          </NavigationHandler>
        </TabBarItem>
      </TabBar>
    </>
  );
};

export default Tabs;
