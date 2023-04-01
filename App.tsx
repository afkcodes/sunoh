import { StateNavigator } from 'navigation';
import { NavigationHandler } from 'navigation-react';
import { NavigationBar, NavigationStack, Scene, TabBar, TabBarItem } from 'navigation-react-native';
import React from 'react';
import { Platform } from 'react-native';
import Home from '~screens/Home';
import { colors } from '~styles/colors';

const test = new StateNavigator([
  { key: 'home' },
  { key: 'profile', trackCrumbTrail: true },
  { key: 'podcast', trackCrumbTrail: true }
]);

const Tabs = () => (
  <>
    <NavigationBar hidden={true} />
    <TabBar
      primary
      bottomTabs
      defaultTab={0}
      selectedTintColor={colors.teal[700]}
      unselectedTintColor='red'
    >
      <TabBarItem title='Inbox'>
        <NavigationHandler stateNavigator={test}>
          <NavigationStack>
            <Scene stateKey='home'>
              <Home />
            </Scene>
            <Scene stateKey='podcast'>
              <Home />
            </Scene>
            <Scene stateKey='profile'>
              <Home />
            </Scene>
          </NavigationStack>
        </NavigationHandler>
      </TabBarItem>
      <TabBarItem title='asdasd'>
        <NavigationHandler stateNavigator={test}>
          <NavigationStack
            backgroundColor={() => (Platform.OS === 'android' ? 'rgba(255,255,255,0)' : 'white')}
          >
            <Scene stateKey='profile'>
              <Home />
            </Scene>
            <Scene stateKey='home'>
              <Home />
            </Scene>
            <Scene stateKey='podcast'>
              <Home />
            </Scene>
          </NavigationStack>
        </NavigationHandler>
      </TabBarItem>
      <TabBarItem title='asdasd'>
        <NavigationHandler stateNavigator={test}>
          <NavigationStack
            backgroundColor={() => (Platform.OS === 'android' ? 'rgba(255,255,255,0)' : 'white')}
          >
            <Scene stateKey='profile'>
              <Home />
            </Scene>
            <Scene stateKey='home'>
              <Home />
            </Scene>
            <Scene stateKey='podcast'>
              <Home />
            </Scene>
          </NavigationStack>
        </NavigationHandler>
      </TabBarItem>
      <TabBarItem title='asdasd'>
        <NavigationHandler stateNavigator={test}>
          <NavigationStack
            backgroundColor={() => (Platform.OS === 'android' ? 'rgba(255,255,255,0)' : 'white')}
          >
            <Scene stateKey='profile'>
              <Home />
            </Scene>
            <Scene stateKey='home'>
              <Home />
            </Scene>
            <Scene stateKey='podcast'>
              <Home />
            </Scene>
          </NavigationStack>
        </NavigationHandler>
      </TabBarItem>
    </TabBar>
  </>
);

const stateNavigator = new StateNavigator([{ key: 'tabs' }]);

const App: React.FC<any> = () => {
  return (
    <NavigationHandler stateNavigator={stateNavigator}>
      {/* <NavigationStack>
        <Scene stateKey='home'>
          <Home />
        </Scene>
        <Scene stateKey='profile'>
          <Profile />
        </Scene>
        <Scene stateKey='podcast'>

          <Home />
        </Scene>
      </NavigationStack> */}

      <NavigationStack
        crumbStyle={(from) => (from ? 'scale_in' : 'scale_out')}
        unmountStyle={(from) => (from ? 'slide_in' : 'slide_out')}
      >
        <Scene stateKey='tabs'>
          <Tabs />
        </Scene>
      </NavigationStack>
    </NavigationHandler>
  );
};

export default App;
