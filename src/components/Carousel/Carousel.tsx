type CarouselType = 'DEFAULT' | 'FLOW';
const CarouselStyleMap: {
  [key in CarouselType]: string;
} = {
  DEFAULT: 'flex snap-x snap-proximity no-scrollbar overflow-x-auto gap-x-4 px-3',
  FLOW: 'grid snap-x snap-proximity no-scrollbar overflow-x-auto grid-flow-col grid-rows-3 gap-4 px-3'
};

interface SnapCarouselPropsType {
  children: React.ReactNode;
  type: CarouselType;
  shouldSnap?: boolean;
}
const SnapCarousel: React.FC<SnapCarouselPropsType> = ({ children, type = 'DEFAULT' }) => {
  return <ul className={CarouselStyleMap[type]}>{children}</ul>;
};

export default SnapCarousel;
