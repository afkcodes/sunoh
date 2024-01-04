import { KeyboardEvent, useRef } from 'react';
import { tabState } from '~states/tab';
import { FontWeightStyle, fontSizeStyle, paddingStyle, radiusStyle } from '~styles/base.style';
import { InputProps } from '~types/component.types';

const Input: React.FC<InputProps> = ({
  placeHolder = '',
  value,
  onChange,
  onBlur = () => {
    console.log('blurred');
    tabState.isInputFocussed = false;
  },
  onFocus = () => {
    console.log('focussed');
    tabState.isInputFocussed = true;
  },
  onKeyDown = () => {
    console.log('submited');
  },
  styleConfig
}) => {
  const inputRef = useRef<HTMLInputElement>(null);

  const onSubMitKeyDown = (e: KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      inputRef.current?.blur();
      onKeyDown(e);
      tabState.isInputFocussed = false;
    }
  };

  return (
    <input
      ref={inputRef}
      type='text'
      placeholder={placeHolder}
      className={`
        w-full shrink-0 bg-transparent border-none ring-none outline-none
        ${paddingStyle[styleConfig.padding]}
        ${fontSizeStyle[styleConfig.fontSize]}
        ${FontWeightStyle[styleConfig.fonWeight]}
        ${radiusStyle[styleConfig.radius]}
        `}
      onChange={onChange}
      onFocus={onFocus}
      onBlur={onBlur}
      value={value}
      onKeyDown={onSubMitKeyDown}
    />
  );
};

export default Input;
