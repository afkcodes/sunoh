import { useColorScheme } from 'react-native';

const useTheme: any = () => {
  const theme = useColorScheme();
  console.log(theme);
};

export default useTheme;
