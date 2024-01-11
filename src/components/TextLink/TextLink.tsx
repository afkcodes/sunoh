import { Link } from 'react-router-dom';
import { FontWeightStyle, fontSizeStyle, lineCountStyle } from '~styles/base.style';
import { TextLinkProps } from '~types/component.types';

const TextLink: React.FC<TextLinkProps> = ({
  to,
  text,
  fontSize = 'base',
  fontWeight = 'normal',
  numOfLines = 1
}) => {
  const fontSizeClass = fontSizeStyle[fontSize];
  const fontWeightClass = FontWeightStyle[fontWeight];

  return to ? (
    <Link to={to} className={`${fontSizeClass} ${fontWeightClass}`}>
      {text}
    </Link>
  ) : (
    <p className={`${fontSizeClass} ${fontWeightClass} ${lineCountStyle[numOfLines]}`}>{text}</p>
  );
};

export default TextLink;
