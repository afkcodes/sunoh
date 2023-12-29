import { Dispatch, SetStateAction } from "react";
import {
  ArrangeMode,
  FigureSize,
  FitStrategy,
  FontSize,
  FontWeight,
  ImageLoading,
  LineCount,
  Shape,
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
