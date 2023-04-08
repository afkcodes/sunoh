import { StateNavigator } from 'navigation';
import { NavigationHandler } from 'navigation-react';
import { NavigationStack, Scene } from 'navigation-react-native';
import React from 'react';
import Tabs from '~navigation/Tabs';

const stateNavigator = new StateNavigator([{ key: 'tabs' }]);

const App: React.FC<any> = () => {
  return (
    <NavigationHandler stateNavigator={stateNavigator}>
      <NavigationStack>
        <Scene stateKey='tabs'>
          <Tabs />
        </Scene>
      </NavigationStack>
    </NavigationHandler>
  );
};

export default App;
