import React, { useState } from 'react';
import { Text, View } from 'react-native';
import { theme } from '~styles/theme';

const Home: React.FC<any> = () => {
  const [currentTheme, setCurrentTheme] = useState('dark');
  return (
    <View style={{ flex: 1, backgroundColor: theme[currentTheme].background.primary }}>
      <Text style={{ color: theme[currentTheme].text.primary, fontSize: 20 }}>Home</Text>
      <Text style={{ color: theme[currentTheme].text.secondary, fontSize: 20 }}>sadasdasdsad</Text>
      <View
        style={{
          height: 40,
          width: '100%',
          backgroundColor: theme[currentTheme].button.primary,
          borderRadius: 40
        }}
      />
      <Text
        style={{ color: theme[currentTheme].text.secondary, fontSize: 20, margin: 40 }}
        onPress={() => {
          setCurrentTheme((prev) => (prev === 'dark' ? 'light' : 'dark'));
        }}
      >
        Change Theme - {currentTheme}
      </Text>
    </View>
  );
};

export default Home;
