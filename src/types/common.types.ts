type ExtraSmallSize = "3xs" | "2xs";
type BaseSize = "xs" | "sm" | "md" | "lg" | "xl";
type ExtraLargeSize = "2xl" | "3xl" | "4xl";

export type Spacing = BaseSize | "xs" | "sm" | "md" | "lg";
export type Radius = BaseSize | "full" | "none";
export type FontSize = BaseSize | ExtraLargeSize | "base";
export type FontWeight = "normal" | "medium" | "semibold" | "bold";
export type Position = "left" | "right" | "top" | "bottom";

export type TrackType = "hls" | "default";

export interface Track {
  artist: string;
  url: string;
  title: string;
  type: TrackType;
  artwork: string;
  genre: string;
  bufferPosition?: number;
  currentPosition?: number;
  blurHash?: string;
  dominantColor?: string;
}

export interface Response {
  message: string;
  data: any;
  code: number;
  error: string;
}

export type TileSize = ExtraSmallSize | BaseSize | ExtraLargeSize | "free";
export type FigureSize = ExtraSmallSize | BaseSize | ExtraLargeSize | "free";
export type Shape = "default" | "rounded_square" | "circle";
export type FitStrategy =
  | "default"
  | "fill"
  | "contain"
  | "cover"
  | "scale_down";

export type ArrangeMode = "single" | "multi";
export type ImageLoading = "eager" | "lazy" | undefined;
export type LineCount = 1 | 2 | 3 | 4;
