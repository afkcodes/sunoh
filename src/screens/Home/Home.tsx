import React from 'react';
import { Text } from 'react-native';
import { SView } from '~components';
import { theme } from '~styles';
import { spacing } from '~styles/utilities';

const Home: React.FC<any> = () => {
  return (
    <SView color='primary' flex={1} paddingTop={spacing.md}>
      <Text style={{ color: theme.dark.text.primary, fontSize: 20 }}>Home</Text>
    </SView>
  );
};

export default Home;
