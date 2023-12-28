import {
  FontWeightStyle,
  fontSizeStyle,
  radiusStyle,
} from "../../styles/base.style";
import {
  FontSize,
  FontWeight,
  Position,
  Radius,
} from "../../types/common.types";
import { buttonVariantStyle } from "./button.styles";
import { Variant } from "./button.types";

interface Button {
  variant: Variant;
  onClick: (param: any) => void;
  text?: string;
  radius?: Radius;
  fontSize?: FontSize;
  fontWeight?: FontWeight;
  icon?: React.ReactNode;
  iconPosition?: Position;
  customClass?: string;
}

const Button: React.FC<Button> = ({
  text,
  icon = null,
  onClick = () => {
    console.log("button clicked");
  },
  variant,
  radius = "xs",
  fontSize = "base",
  fontWeight = "medium",
  iconPosition = "left",
  customClass = "",
}) => {
  return (
    <button
      className={`
      text-white
      ${buttonVariantStyle[variant]}
      ${radiusStyle[radius]}
      ${fontSizeStyle[fontSize]}
      ${FontWeightStyle[fontWeight]}
      ${customClass}
    `}
      onClick={onClick}
    >
      <div
        className={` justify-center items-center gap-1 
        ${iconPosition === "left" ? "flex" : "flex flex-row-reverse"}
        ${iconPosition === "top" ? "flex-col" : "flex flex-col-reverse"}
        `}
      >
        {icon ? <span>{icon}</span> : null}
        {text ? <span>{text}</span> : null}
      </div>
    </button>
  );
};

export default Button;
