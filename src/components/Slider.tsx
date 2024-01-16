import { memo } from 'react';
import ReactSlider from 'react-slider';
import { useSnapshot } from 'valtio';
import { playerState } from '~states/player';

interface SliderProps {
  onChange: (value: number) => void;
  onSliderClick: (value: number) => void;
}

const Slider: React.FC<SliderProps> = memo(({ onChange, onSliderClick }) => {
  const { audioState } = useSnapshot(playerState);

  return (
    <ReactSlider
      className='text-white flex items-center p-0 m-0'
      thumbClassName=''
      trackClassName='bg-white/50 backdrop-blur-sm h-2 rounded-full'
      min={0}
      max={(audioState.duration as number) || 0}
      value={audioState.progress || 0}
      onChange={onChange}
      onSliderClick={onSliderClick}
      renderThumb={(props: any) => (
        <div
          {...props}
          className=' bg-white/80 backdrop-blur-sm text-white h-5 w-2 rounded-full'
        ></div>
      )}
    />
  );
});

export default Slider;
