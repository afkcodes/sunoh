import React from 'react';
import { Text, View } from 'react-native';
import { theme } from '~styles/theme';

const Podcast = () => {
  return (
    <View>
      <Text style={{ color: theme.light.text.primary, fontSize: 20 }}>Podcast</Text>
    </View>
  );
};

export default Podcast;
