import { FontSize, FontWeight, Radius } from "../types/common.types";

const radiusStyle: { [key in Radius]: string } = {
  xs: "rounded-sm",
  sm: "rounded-sm",
  md: "rounded-sm",
  xl: "rounded-xl",
  lg: "rounded-lg",
  full: "rounded-full",
  none: "radius-none",
};

const fontSizeStyle: { [key in FontSize]: string } = {
  xs: "text-xs",
  sm: "text-sm",
  base: "text-base",
  md: "text-md",
  lg: "text-lg",
  xl: "text-xl",
  "2xl": "text-2xl",
  "3xl": "text-3xl",
  "4xl": "text-4xl",
};

const FontWeightStyle: { [key in FontWeight]: string } = {
  normal: "font-normal",
  bold: "font-bold",
  medium: "font-medium",
  semibold: "font-semibold",
};

export { FontWeightStyle, fontSizeStyle, radiusStyle };
