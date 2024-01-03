interface StorageProps {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
  clear(): void;
  removeItem(key: string): void;
}
import { isValidWindow } from "~helpers/common";

const storage: StorageProps = {
  getItem: (key: string) => {
    let data = null;
    if (isValidWindow) {
      data = window.localStorage.getItem(key);
    }
    return data;
  },

  setItem(key: string, value: string) {
    if (isValidWindow) {
      window.localStorage.setItem(key, value);
    }
  },

  clear() {
    if (isValidWindow) {
      window.localStorage.clear();
    }
  },

  removeItem(key) {
    if (isValidWindow) {
      window.localStorage.removeItem(key);
    }
  },
};

export { storage };
