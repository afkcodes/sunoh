import { StateNavigator } from 'navigation';
import { NavigationHandler } from 'navigation-react';
import { NavigationStack, Scene } from 'navigation-react-native';
import React from 'react';
import ThemeProvider from '~contexts/theme.context';
import Tabs from '~navigation/Tabs';

const stateNavigator = new StateNavigator([{ key: 'tabs' }]);

const App: React.FC<any> = () => {
  return (
    <ThemeProvider>
      <NavigationHandler stateNavigator={stateNavigator}>
        <NavigationStack>
          <Scene stateKey='tabs'>
            <Tabs />
          </Scene>
        </NavigationStack>
      </NavigationHandler>
    </ThemeProvider>
  );
};

export default App;
