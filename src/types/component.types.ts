import { Dispatch, SetStateAction } from "react";
import { Variant } from "~components/Button/button.types";
import {
  ArrangeMode,
  FigureSize,
  FitStrategy,
  FontSize,
  FontWeight,
  ImageLoading,
  LineCount,
  Position,
  Radius,
  Shape,
  TileSize,
} from "~types/common.types";

export interface FigureProps {
  src: string;
  alt: string;
  shape?: Shape;
  size?: FigureSize;
  fit?: FitStrategy;
  loading?: ImageLoading;
  mode?: ArrangeMode;
  onLoad?: Dispatch<SetStateAction<string>>;
  dominantColor?: string;
}

export interface TitleSubtitleProps {
  title: string;
  subTitle: string;
  titleFontSize?: FontSize;
  subtitleFontSize?: FontSize;
  titleFontWeight?: FontWeight;
  subtitleFontWeight?: FontWeight;
  noOfLinesTitle?: LineCount;
  noOfLinesSubtitle?: LineCount;
}

export interface TileStyleProps {
  shape: Shape;
  size: TileSize;
  fit?: FitStrategy;
  titleFontSize?: FontSize;
  subtitleFontSize?: FontSize;
  titleFontWeight?: FontWeight;
  subtitleFontWeight?: FontWeight;
}

export interface TileContainerProps {
  data: any[];
  config: any;
  tileStyleConfig: TileStyleProps;
  onClick: (item: any) => void;
  displayType: "carousel" | "default";
}

export interface ButtonProps {
  variant: Variant;
  onClick: (param: any) => void;
  text?: string;
  radius?: Radius;
  fontSize?: FontSize;
  fontWeight?: FontWeight;
  icon?: React.ReactNode;
  iconPosition?: Position;
  customClass?: string;
  isCapitalized?: boolean;
}

export interface SectionHeaderProps {
  textLinkConfig: TextLinkProps;
  actionButtonConfig: ButtonProps;
}

export interface TextLinkProps {
  text: string;
  to?: string;
  fontSize?: FontSize;
  fontWeight?: FontWeight;
}

export interface SectionContainerConfig {
  sectionHeaderConfig: SectionHeaderProps;
  containerType: "tile" | "audio_list";
  containerConfig: TileContainerProps;
}
