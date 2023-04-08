import React from 'react';
import { Text, View } from 'react-native';
import { theme } from '~styles/theme';

const Home: React.FC<any> = () => {
  return (
    <View>
      <Text style={{ color: theme.light.text.primary, fontSize: 20 }}>Home</Text>
    </View>
  );
};

export default Home;
