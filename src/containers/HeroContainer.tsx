import { RiPlayFill, RiShuffleFill } from 'react-icons/ri';
import Button from '~components/Button/Button';
import Figure from '~components/Figure/Figure';
import TextLink from '~components/TextLink/TextLink';
import { dataExtractor } from '~helpers/common';

interface HeroContainerProps {
  data: any;
  config: any;
}
const HeroContainer: React.FC<HeroContainerProps> = ({ data, config }) => {
  // const id = dataExtractor(data, config.id);
  const src = dataExtractor(data, config.image);
  const title = dataExtractor(data, config.title);
  const subTitle = dataExtractor(data, config.subtitle);
  // const dominantColor = dataExtractor(data, config.dominantColor);
  console.log(src);
  return (
    <div className='relative'>
      <div className='absolute top-0 left-0 z-1 blur-2xl opacity-40'>
        <Figure src={src} alt={`${title}_poster`} size='free' fit='cover' loading='eager' />
      </div>

      <div className='flex flex-col justify-center items-center gap-3 px-3 text-center'>
        <Figure
          src={src}
          alt={`${title}_poster`}
          size='5xl'
          fit='cover'
          loading='eager'
          shape='rounded_square'
        />
        <div className='mt-2'>
          <TextLink text={title} fontSize='2xl' fontWeight='bold' />
        </div>
        <div>
          <TextLink text={subTitle} fontSize='sm' fontWeight='medium' numOfLines={2} />
        </div>

        <div className='flex gap-4 mt-2'>
          <Button
            text='Play'
            fontSize='xl'
            fontWeight='semibold'
            radius='xl'
            variant='unstyled'
            customClass='px-6 py-2.5  backdrop-blur-sm  bg-white w-40 hover:bg-white active:bg-white/70 text-textDark'
            icon={<RiPlayFill size={26} />}
            iconPosition='left'
            onClick={() => {
              console.log('play');
            }}
          />
          <Button
            text='Shuffle'
            fontSize='xl'
            radius='xl'
            fontWeight='semibold'
            variant='unstyled'
            customClass='px-6 py-2.5 backdrop-blur-sm bg-white/30 w-40 hover:bg-white/30 active:bg-white/20'
            icon={<RiShuffleFill />}
            onClick={() => {
              console.log('play');
            }}
          />
        </div>
      </div>
    </div>
  );
};

export default HeroContainer;
