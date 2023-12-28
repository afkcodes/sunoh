type BaseSize = "xs" | "sm" | "md" | "lg" | "xl";
type ExtraLargeSize = "2xl" | "3xl" | "4xl";

export type Spacing = BaseSize | "xs" | "sm" | "md" | "lg";
export type Radius = BaseSize | "full" | "none";
export type FontSize = BaseSize | ExtraLargeSize | "base";
export type FontWeight = "normal" | "medium" | "semibold" | "bold";
export type TileSize =
  | Exclude<ExtraLargeSize, BaseSize>
  | "2xl"
  | "3xl"
  | "4xl";
export type Position = "left" | "right" | "top" | "bottom";
