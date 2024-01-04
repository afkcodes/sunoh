import Button from '~components/Button/Button';
import Input from '~components/Input/Input';
import { paddingStyle, radiusStyle } from '~styles/base.style';
import { Radius, Spacing } from '~types/common.types';
import { ButtonProps, InputProps } from '~types/component.types';

interface SearchBarProps {
  inputConfig: InputProps;
  styleConfig: {
    padding: Spacing;
    radius: Radius;
  };
  iconButtonConfig?: ButtonProps;
}

const SearchBar: React.FC<SearchBarProps> = ({ inputConfig, iconButtonConfig, styleConfig }) => {
  return (
    <div
      className={`
      flex items-center space-between bg-bgSecondary
      ${paddingStyle[styleConfig.padding]}
      ${radiusStyle[styleConfig.radius]}
      `}
    >
      <div className='w-[95%]'>
        <Input {...inputConfig} />
      </div>
      <div>{iconButtonConfig ? <Button {...iconButtonConfig} /> : null}</div>
    </div>
  );
};

export default SearchBar;
