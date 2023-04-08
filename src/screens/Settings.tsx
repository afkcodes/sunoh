import { Text, View } from 'react-native';
import { theme } from '~styles/theme';

const Settings = () => {
  return (
    <View>
      <Text style={{ color: theme.light.text.primary, fontSize: 20 }}>Settings</Text>
    </View>
  );
};

export default Settings;
