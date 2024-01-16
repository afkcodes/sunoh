import { ButtonProps } from '~types/component.types';
import { FontWeightStyle, fontSizeStyle, gapStyle, radiusStyle } from '../../styles/base.style';
import { buttonVariantStyle } from './button.styles';

const Button: React.FC<ButtonProps> = ({
  text,
  icon = null,
  onClick = () => {
    console.log('button clicked');
  },
  variant,
  radius = 'xs',
  fontSize = 'base',
  fontWeight = 'medium',
  iconPosition = 'left',
  customClass = '',
  isCapitalized = false,
  iconGap = 'sm'
}) => {
  const iconPositionMap = {
    left: 'flex',
    right: 'flex flex-row-reverse',
    top: 'flex-col',
    bottom: 'flex flex-col-reverse'
  };

  return (
    <button
      className={`
      transition-all duration-300
      ${buttonVariantStyle[variant]}
      ${radiusStyle[radius]}
      ${fontSizeStyle[fontSize]}
      ${FontWeightStyle[fontWeight]}
      ${customClass}
    `}
      onClick={onClick}
    >
      <div
        className={` flex items-center m-0 p-0
        ${iconPositionMap[iconPosition]}
        ${gapStyle[iconGap]}
        `}
      >
        {icon ? <span>{icon}</span> : null}
        {text ? (
          <span
            className={`p-0 m-0
            ${isCapitalized ? 'inline-block leading-3 mt-0.5' : ''}`}
          >
            {text}
          </span>
        ) : null}
      </div>
    </button>
  );
};

export default Button;
