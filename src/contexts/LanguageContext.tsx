import { createContext, useState } from 'react';

type Language = 'EN' | 'KA';
interface LanguageContextProps {
  lang: 'EN' | 'KA';
  changeLang: (lang: Language) => void;
}
export const LanguageContext = createContext<LanguageContextProps>({
  lang: 'EN',
  changeLang: () => {}
});

interface LanguageProvider {
  children: React.ReactNode;
}

const LanguageProvider: React.FC<LanguageProvider> = ({ children }) => {
  const [lang, setLang] = useState<Language>('EN');

  const updateLanguage = (lang: Language) => {
    setLang(lang);
  };

  return (
    <LanguageContext.Provider value={{ lang, changeLang: updateLanguage }}>
      {children}
    </LanguageContext.Provider>
  );
};

export default LanguageProvider;
