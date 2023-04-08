import React from 'react';
import { Text, View } from 'react-native';
import { theme } from '~styles/theme';

const Profile = () => {
  return (
    <View>
      <Text style={{ color: theme.light.text.primary, fontSize: 20 }}>Profile</Text>
    </View>
  );
};

export default Profile;
