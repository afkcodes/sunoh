import { Link } from 'react-router-dom';
import { FontWeightStyle, fontSizeStyle } from '~styles/base.style';
import { TextLinkProps } from '~types/component.types';

const TextLink: React.FC<TextLinkProps> = ({
  to,
  text,
  fontSize = 'base',
  fontWeight = 'normal'
}) => {
  const fontSizeClass = fontSizeStyle[fontSize];
  const fontWeightClass = FontWeightStyle[fontWeight];

  return to ? (
    <Link to={to} className={`${fontSizeClass} ${fontWeightClass}`}>
      {text}
    </Link>
  ) : (
    <span className={`${fontSizeClass} ${fontWeightClass}`}>{text}</span>
  );
};

export default TextLink;
