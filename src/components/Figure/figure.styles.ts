import { FigureSize, FitStrategy, Shape } from "~types/common.types";

const figureSize: {
  [key in FigureSize]: string;
} = {
  "3xs": "size-8",
  "2xs": "size-12",
  xs: "size-16",
  sm: "size-20",
  md: "size-24",
  lg: "size-28",
  xl: "size-32",
  "2xl": "size-36",
  "3xl": "size-40",
  "4xl": "size-44",
  free: "h-full w-full",
};

const figureShape: {
  [key in Shape]: string;
} = {
  default: "overflow-hidden rounded-none",
  rounded_square: "overflow-hidden rounded",
  circle: "overflow-hidden rounded-full",
};

const fitStrategy: {
  [key in FitStrategy]: string;
} = {
  default: "object-none",
  fill: "object-fill",
  contain: "object-contain",
  cover: "object-cover",
  scale_down: "object-scale-down",
};

export { figureShape, figureSize, fitStrategy };
