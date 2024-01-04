import { MediaTrack } from 'audio_x';

type ExtraSmallSize = '3xs' | '2xs';
type BaseSize = 'xs' | 'sm' | 'md' | 'lg' | 'xl';
type ExtraLargeSize = '2xl' | '3xl' | '4xl';

export type Spacing = ExtraSmallSize | BaseSize | ExtraLargeSize;
export type Radius = BaseSize | 'full' | 'none';
export type FontSize = BaseSize | ExtraLargeSize | 'base';
export type FontWeight = 'normal' | 'medium' | 'semibold' | 'bold';
export type Position = 'left' | 'right' | 'top' | 'bottom';

export type TrackType = 'hls' | 'default';

export interface Track extends MediaTrack {
  dominantColor?: string;
}

export interface Response {
  message: string;
  data: any;
  code: number;
  error: string;
}

export type TileSize = ExtraSmallSize | BaseSize | ExtraLargeSize | 'free' | '2.5xs';
export type FigureSize = ExtraSmallSize | BaseSize | ExtraLargeSize | 'free' | '2.5xs';
export type Shape = 'default' | 'rounded_square' | 'circle';
export type FitStrategy = 'default' | 'fill' | 'contain' | 'cover' | 'scale_down';

export type ArrangeMode = 'single' | 'multi';
export type ImageLoading = 'eager' | 'lazy' | undefined;
export type LineCount = 1 | 2 | 3 | 4;
