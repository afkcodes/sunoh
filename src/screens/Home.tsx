import React, { useContext } from 'react';
import { Pressable } from 'react-native';
import { SView } from '~components';
import SText from '~components/SText/SText';
import { ThemeContext } from '~contexts/theme.context';

const Home: React.FC<any> = () => {
  const { theme, setTheme } = useContext(ThemeContext);
  console.log(theme);
  return (
    <SView display='flex' flex={1}>
      <Pressable
        onPress={() => {
          setTheme(theme === 'dark' ? 'light' : 'dark');
        }}
      >
        <SText color='primary' fontSize={16}>
          Hello here is cool text Hello here is cool text Hello here is cool text Hello here is cool
          text
        </SText>
      </Pressable>
    </SView>
  );
};

export default Home;
