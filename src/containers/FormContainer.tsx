import { Dispatch, SetStateAction, useCallback, useState } from 'react';
import { deepCompare, typeChecker } from '../helpers/common';

export type Value = string | any[] | object;

export interface Validators<T> {
  defaultValidators?: {
    [name in keyof T]?: Array<(value: Value, formValues: T) => string>;
  };
  customValidators?: {
    [name in keyof T]?: Array<(value: Value, formValues: T) => string>;
  };
}

export interface FormValues {
  [field: string]: any;
}

export type Input = 'text' | 'select' | 'checkbox' | 'radio' | 'upload';
export type InputData = { name: string; value: Value; type: Input };
export type FormOperationMode = 'EDIT' | 'VIEW';

const FormContainer = <T extends FormValues>({
  initialValues,
  children,
  validators,
  validateOnChange = false,
  onSubmit = () => {
    console.log('submit form');
  },
  mode = 'EDIT',
  formatters
}: {
  initialValues: T;
  children: (args: {
    values: T;
    formattedValues: T;
    touched: T;
    dirty: boolean;
    errors: {
      [key in keyof T]: {
        message?: string;
        customValidateMessage?: string;
      };
    };
    isValid: boolean;
    onChange: (e: InputData) => void;
    onFocus: (e: InputData) => void;
    onBlur: (e: InputData) => void;
    onSubmit: (values: T) => void;
    reset: () => void;
    mode: FormOperationMode;
    setFormMode: Dispatch<SetStateAction<FormOperationMode>>;
  }) => JSX.Element;
  validators: Validators<T>;
  validateOnChange?: boolean;
  onSubmit: (values: T) => void;
  mode: FormOperationMode;
  formatters?: { [name in keyof T]?: (value: Value) => any };
}) => {
  const [values, setValues] = useState(initialValues);
  const [errors, setErrors] = useState<T>({} as T);
  const [dirty, setDirty] = useState(false);
  const [touched, setTouched] = useState<T>({} as T);
  const [formattedValues, setFormattedValues] = useState(initialValues);
  const [formOperationMode, setFormOperationMode] = useState(mode);

  const { defaultValidators, customValidators } = validators;

  const reset = () => {
    setValues(initialValues);
    setErrors({} as T);
    setTouched({} as T);
    setDirty(false);
  };

  const getFormattedValue = useCallback(
    (name: string, val: Value) => {
      let value = val;
      if (formatters) {
        Object.keys(formatters).forEach((fieldName) => {
          if (fieldName === name) {
            value = formatters?.[fieldName]?.(val);
          }
        });
      }
      return value;
    },
    [formatters]
  );

  const setFormValue = useCallback(
    (name: string, value: Value, type: Input) => {
      const formattedValue: any = formatters?.[name] ? getFormattedValue(name, value) : value;

      const initialValueType = typeChecker(initialValues[name]);

      switch (initialValueType) {
        case 'object': {
          setValues((prev: T) => {
            return {
              ...prev,
              [name]: { ...prev[name], ...formattedValue }
            };
          });
          setFormattedValues((prev: T) => {
            return {
              ...prev,
              [name]: { ...prev[name], ...formattedValue }
            };
          });
          break;
        }

        case 'array': {
          if (type === 'checkbox') {
            const modifiedItem = formattedValue;
            setValues((prev: T) => {
              const existingItems = prev?.[name];

              // remove existing object from array
              let newItems = existingItems.filter(
                (checkBoxItem: any) => checkBoxItem?.name !== (modifiedItem as any)?.name
              );
              // push new object to array
              newItems.push(modifiedItem);
              //filter only 'checked' items
              newItems = newItems?.filter((item: any) => item?.value);

              return { ...prev, [name]: newItems };
            });
            setFormattedValues((prev: T) => {
              const existingItems = prev[name];

              // remove existing object from array
              let newItems = existingItems.filter(
                (checkBoxItem: any) => checkBoxItem?.name !== (modifiedItem as any)?.name
              );
              // push new object to array
              newItems.push(modifiedItem);
              //filter only 'checked' items
              newItems = newItems?.filter((item: any) => item?.formattedValue);

              return { ...prev, [name]: newItems };
            });
          }
          break;
        }
        default: {
          setValues((prev: T) => {
            return {
              ...prev,
              [name]: value
            };
          });
          setFormattedValues((prev: T) => {
            return {
              ...prev,
              [name]: formattedValue
            };
          });
          break;
        }
      }
    },
    [formatters, getFormattedValue, initialValues]
  );

  const setFormError = useCallback(
    (name: keyof T, message: any) => {
      let errorObj = { ...errors };

      if (message === '') {
        delete errorObj[name];
      } else {
        errorObj = { ...errors, [name]: message };
      }
      setErrors(() => errorObj);
    },
    [errors]
  );

  const setDirtyStatus = useCallback((initialValues: T, values: T) => {
    if (Object.keys(values).length) {
      setDirty(!deepCompare(initialValues, values));
    }
  }, []);

  const setTouchedFields = useCallback((name: string) => {
    setTouched((prev: T) => {
      return { ...prev, [name]: true };
    });
  }, []);

  const validateFields = useCallback(
    (name: keyof T, value: Value) => {
      const customValidatorsList = customValidators?.[name];
      const defaultValidatorsList = defaultValidators?.[name];
      let message = '';
      let customValidateMessage = '';

      if (Array.isArray(defaultValidatorsList) && defaultValidatorsList.length) {
        defaultValidatorsList.every((validator) => {
          message = validator(value, values);
          return message === '';
        });
      }

      if (Array.isArray(customValidatorsList) && customValidatorsList.length) {
        customValidatorsList.every((validator) => {
          customValidateMessage = validator(value, values);
          return customValidateMessage === '';
        });
      }

      if (defaultValidators?.[name] || customValidators?.[name]) {
        setFormError(name, { message, customValidateMessage });
      }
    },
    [customValidators, defaultValidators, setFormError, values]
  );

  const onChange = useCallback(
    (data: InputData) => {
      const { name, value, type } = data;

      if (validateOnChange) {
        validateFields(name, value);
      }
      setFormValue(name, value, type);
    },
    [setFormValue, validateFields, validateOnChange]
  );

  const onBlur = useCallback(
    (data: InputData) => {
      const { name, value } = data;
      validateFields(name, value);
      setDirtyStatus(initialValues, values);
      setTouchedFields(name);
    },
    [validateFields, setDirtyStatus, initialValues, values, setTouchedFields]
  );

  const onFocus = useCallback((e: InputData) => {
    console.log(e);
  }, []);

  const isFormValid = () => {
    let isValid = true;
    for (const err in errors) {
      if (errors[err].message || errors[err].customValidateMessage) {
        isValid = false;
      }
    }
    return isValid;
  };

  return (
    <form>
      {children({
        values,
        formattedValues,
        onFocus,
        onChange,
        touched,
        errors,
        onBlur,
        dirty,
        isValid: isFormValid(),
        onSubmit,
        mode: formOperationMode,
        setFormMode: setFormOperationMode,
        reset
      })}
    </form>
  );
};

export default FormContainer;
