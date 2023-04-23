import React, { createContext, useState } from 'react';
import { type ThemeType } from '~types/components.types';

const baseThemeData: any = {
  theme: 'dark',
  setTheme: () => {}
};
export const ThemeContext = createContext(baseThemeData);

export const ThemeProvider = ({ children }: { children: React.ReactNode }) => {
  const [theme, setTheme] = useState<ThemeType>('dark');
  return <ThemeContext.Provider value={{ theme, setTheme }}>{children}</ThemeContext.Provider>;
};

export default ThemeProvider;
