export const isValidFunction = (fun: any) => typeof fun === "function";

export const deepCompare = (obj1: any, obj2: any): boolean => {
  // Check if the types of both objects are the same
  if (typeof obj1 !== typeof obj2) {
    return false;
  }

  // Handle null and primitive types (string, number, boolean, etc.)
  if (
    obj1 === null ||
    ["string", "number", "boolean", "undefined"].includes(typeof obj1)
  ) {
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
  let type = "";

  if (typeof data === "object" && !Array.isArray(data)) {
    type = "object";
  }
  if (Array.isArray(data)) {
    type = "array";
  }

  if (["string", "number", "boolean", "undefined"].includes(typeof data)) {
    type = typeof data;
  }

  return type;
};
