import { Dispatch, FocusEvent, SetStateAction } from 'react';
import { Variant } from '~components/Button/button.types';
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
  Spacing,
  TileSize
} from '~types/common.types';

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
  onClick: (item: any) => void;
  displayType: 'carousel' | 'default';
  tileStyleConfig?: TileStyleProps;
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
  iconGap?: Spacing;
}

export interface SectionHeaderProps {
  textLinkConfig: TextLinkProps;
  actionButtonConfig?: ButtonProps;
}

export interface TextLinkProps {
  text: string;
  to?: string;
  fontSize?: FontSize;
  fontWeight?: FontWeight;
  numOfLines?: LineCount;
}

export interface SectionContainerConfig {
  sectionHeaderConfig: SectionHeaderProps;
  containerType: 'tile' | 'audio_list' | 'search_history';
  containerConfig: {
    tileContainerConfig?: TileContainerProps;
    searchHistoryContainerConfig?: SearchHistoryContainerProps;
    audioListItemContainerConfig?: AudioListItemContainerProps;
  };
}

export interface InputProps {
  placeHolder: string;
  value: string;
  onChange?: (value: string) => void;
  onFocus?: (e?: FocusEvent<HTMLInputElement>) => void;
  onBlur?: (e?: FocusEvent<HTMLInputElement>) => void;
  onKeyDown?: (e?: React.KeyboardEvent<HTMLInputElement>) => void;
  styleConfig: {
    padding: Spacing;
    fonWeight: FontWeight;
    fontSize: FontSize;
    radius: Radius;
  };
}

export interface SearchHistoryItemProps {
  data: SearchItem;
  config: any;
  onClick: (item: any) => void;
}

export interface SearchHistoryContainerProps {
  data: SearchItem[];
  config: any;
  onClick: (item: any) => void;
  tileStyleConfig?: any; // added because of type error
  displayType?: any; // added because of type error
}

export interface SearchItem {
  text: string;
}

export interface AudioListItemContainerProps {
  data: any[];
  config: any;
  onClick: (item?: any) => void;
}
