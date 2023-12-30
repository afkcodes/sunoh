import { ButtonProps } from "~types/component.types";
import {
  FontWeightStyle,
  fontSizeStyle,
  radiusStyle,
} from "../../styles/base.style";
import { buttonVariantStyle } from "./button.styles";

const Button: React.FC<ButtonProps> = ({
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
  isCapitalized = false,
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
        {text ? (
          <span
            className={`p-0 m-0
            ${isCapitalized ? "inline-block leading-3 mt-0.5" : ""}`}
          >
            {text}
          </span>
        ) : null}
      </div>
    </button>
  );
};

export default Button;
