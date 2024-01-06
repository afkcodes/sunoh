import { MediaTrack } from 'audio_x';
import { Track, TrackType } from '~types/common.types';

export const isValidFunction = (fun: any) => typeof fun === 'function';
export const isValidArray = (arr: any[]) => arr && Array.isArray(arr) && arr.length > 0;
export const isValidWindow = window instanceof Window && typeof window !== 'undefined';
export const isValidObject = (obj: any): boolean =>
  obj !== null && typeof obj === 'object' && !Array.isArray(obj);

export const deepCompare = (obj1: any, obj2: any): boolean => {
  // Check if the types of both objects are the same
  if (typeof obj1 !== typeof obj2) {
    return false;
  }

  // Handle null and primitive types (string, number, boolean, etc.)
  if (obj1 === null || ['string', 'number', 'boolean', 'undefined'].includes(typeof obj1)) {
    return obj1 === obj2;
  }

  // Handle arrays
  if (Array.isArray(obj1)) {
    // Check if the arrays have the same length
    if (obj1.length !== obj2.length) {
      return false;
    }
    // Recursively compare each element in the array
    for (let i = 0; i < obj1.length; i++) {
      if (!deepCompare(obj1[i], obj2[i])) {
        return false;
      }
    }
    return true;
  }

  // Handle objects
  const obj1Keys = Object.keys(obj1);
  const obj2Keys = Object.keys(obj2);

  // Check if the objects have the same number of keys
  if (obj1Keys.length !== obj2Keys.length) {
    return false;
  }

  // Recursively compare each key-value pair in the objects
  for (const key of obj1Keys) {
    // Check if the key exists in both objects and the values are deeply equal
    if (!obj2Keys.includes(key) || !deepCompare(obj1[key], obj2[key])) {
      return false;
    }
  }

  // If all checks pass, the objects are deeply equal
  return true;
};

export const typeChecker = (data: any) => {
  let type = '';

  if (typeof data === 'object' && !Array.isArray(data)) {
    type = 'object';
  }
  if (Array.isArray(data)) {
    type = 'array';
  }

  if (['string', 'number', 'boolean', 'undefined'].includes(typeof data)) {
    type = typeof data;
  }

  return type;
};

/* eslint-disable no-prototype-builtins */
type NestedObject = Record<string, any>; // Define a type for nested objects

export const dataExtractor = (obj: NestedObject, key: string): any | null => {
  if (!(obj instanceof Object)) {
    // If the provided object is not an instance of Object (i.e., not a valid object), return null
    return null;
  }

  const keys = key.split('.'); // Split the key by dot notation to get individual keys
  let currentObj: NestedObject | any[] | null = obj; // Initialize a variable to keep track of the current object

  for (const k of keys) {
    if (currentObj === null) {
      // If current object is null, return null (gracefully handle nested null values)
      return null;
    }

    if (Array.isArray(currentObj)) {
      // If the current object is an array
      const index = parseInt(k, 10); // Convert the key to an integer (for array index)
      if (!Number.isNaN(index) && index >= 0 && index < currentObj.length) {
        // Check if the index is a valid number and within the array length
        currentObj = currentObj[index]; // Update the current object to the element at the given index
      } else {
        return null; // If the index is out of range, return null
      }
    } else if (currentObj instanceof Object) {
      // If the current object is a regular object

      if (currentObj.hasOwnProperty(k)) {
        // Check if the key exists in the current object
        currentObj = currentObj[k]; // Update the current object to the value associated with the key
      } else {
        return null; // If the key doesn't exist, return null
      }
    } else {
      return null; // If the current object is neither an array nor an object, return null
    }
  }

  return currentObj; // Return the final value found after traversing the keys
};

export const getTrackFromMetaData = (track: Track, config: any) => {
  const url = dataExtractor(track, config.stream) || '';
  const artist = dataExtractor(track, config.artist) || '';
  const title = dataExtractor(track, config.title) || '';
  const artwork =
    dataExtractor(track, config.artwork) ||
    'https://cdn.statically.io/gh/megabyt-dev/def-img/6b991495/radio.png'; // use better fallback image
  const genre = dataExtractor(track, config.genre) || '';
  const bufferPosition = 0;
  const currentPosition = 0;
  const type: TrackType = url.includes('m3u8') ? 'hls' : 'default';
  const blurHash = dataExtractor(track, config.blurHash);
  const dominantColor = dataExtractor(track, config.dominantColor);

  return {
    url,
    title,
    artist,
    artwork,
    bufferPosition,
    currentPosition,
    genre,
    type,
    dominantColor,
    blurHash
  };
};

export const getColorWithOpacity = (hexColor: string, opacity: number): string => {
  // Ensure opacity is within the valid range of 0 to 1
  opacity = Math.min(1, Math.max(0, opacity));

  // Parse the hex color to RGB components
  const r: number = parseInt(hexColor.slice(1, 3), 16);
  const g: number = parseInt(hexColor.slice(3, 5), 16);
  const b: number = parseInt(hexColor.slice(5, 7), 16);

  // Calculate the new RGB values with opacity
  const newR: number = Math.round(r * opacity);
  const newG: number = Math.round(g * opacity);
  const newB: number = Math.round(b * opacity);

  // Convert the RGB values to hex and pad with zeros if needed
  const newHexR: string = newR.toString(16).padStart(2, '0');
  const newHexG: string = newG.toString(16).padStart(2, '0');
  const newHexB: string = newB.toString(16).padStart(2, '0');

  // Create the new hex color with opacity
  const newHexColor: string = `#${newHexR}${newHexG}${newHexB}`;

  return newHexColor;
};

export const findDuplicatesAndRemove = <T>(jsonArray: T[], key: keyof T, count?: number): T[] => {
  const seen = new Set<any>();
  const uniqueArray: T[] = [];

  for (const item of jsonArray) {
    const keyValue = item[key];

    if (!seen.has(keyValue)) {
      seen.add(keyValue);
      uniqueArray.push(item);

      if (count !== undefined && uniqueArray.length >= count) {
        break;
      }
    }
  }

  return uniqueArray;
};

export const getGreeting = () => {
  const currentDate = new Date();
  const currentHour = currentDate.getHours();

  let greeting: string;

  if (currentHour >= 5 && currentHour < 12) {
    greeting = 'Good morning !';
  } else if (currentHour >= 12 && currentHour < 18) {
    greeting = 'Good afternoon !';
  } else if (currentHour >= 18 && currentHour < 22) {
    greeting = 'Good evening !';
  } else {
    greeting = 'Good night !';
  }
  return greeting;
};

export const isColorDark = (color: string) => {
  // Convert color to RGB
  const hexToRgb = (hex: string) => {
    const bigint = parseInt(hex.replace('#', ''), 16);
    return {
      r: (bigint >> 16) & 255,
      g: (bigint >> 8) & 255,
      b: bigint & 255
    };
  };

  // Calculate perceived brightness
  const calculatePerceivedBrightness = ({ r, g, b }: { r: number; g: number; b: number }) => {
    return Math.sqrt(r * r * 0.299 + g * g * 0.587 + b * b * 0.114);
  };

  const { r, g, b } = hexToRgb(color);
  const brightness = calculatePerceivedBrightness({ r, g, b });

  // Set a threshold value for determining darkness (adjust as needed)
  const threshold = 100; // You can adjust this threshold as needed

  return brightness < threshold;
};

let q = 1;
export const createMediaTrack = (item: any) => {
  const mediaTrack: MediaTrack = {
    id: item._id,
    artwork: [
      {
        src: item.imageUrl,
        name: item.name,
        sizes: '200x200'
      }
    ],
    source: `${item.stream.url}?q=${++q}`,
    title: item.name,
    artist: item.locations[0].city.name
  };

  return mediaTrack;
};
