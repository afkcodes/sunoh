import { Fragment, memo, useContext } from 'react';
import { useSnapshot } from 'valtio';
import { AudioXContext } from '~contexts/audioX.context';
import { playerActions, playerState } from '~states/player';

import { RiRepeatFill, RiShuffleFill, RiSkipBackFill, RiSkipForwardFill } from 'react-icons/ri';
import Sheet from 'react-modal-sheet';
import { isValidObject } from '~helpers/common';
import { Track } from '~types/common.types';
import Button from './Button/Button';
import Figure from './Figure/Figure';
import PlayerStatusIndicator from './PlayerStatusIndicator/PlayerStatusIndicator';
import Slider from './Slider';
import TitleSubtitle from './TitleSubtitle/TitleSubtitle';

const Player = memo(() => {
  const { currentTrack, fullPlayerOpen } = useSnapshot(playerState);
  const audio = useContext(AudioXContext);

  const onChange = (value: number) => {
    console.log(value);
  };

  const onSliderClick = (value: number) => {
    console.log(value);
  };

  console.log('RE_RENDERING');

  return (
    <Sheet
      isOpen={fullPlayerOpen}
      onClose={() => {
        playerActions.setFullPlayerState(false);
      }}
      detent='content-height'
    >
      <Sheet.Container className='bg-transparent '>
        <Sheet.Content className='bg-bgSecondary px-3 pb-12  '>
          <Sheet.Header pt-6 />
          {isValidObject(currentTrack) ? (
            <Fragment>
              <div className='text-textLight flex flex-col justify-start items-center w-full gap-10 px-4'>
                <div className='overflow-hidden'>
                  <Figure
                    src={
                      currentTrack && currentTrack.artwork
                        ? (currentTrack?.artwork[0].src as string)
                        : ''
                    }
                    alt={`${currentTrack?.title}_poster`}
                    size='free'
                    fit='cover'
                    loading='lazy'
                    shape='rounded_square'
                  />
                </div>
                <div className='w-full'>
                  <TitleSubtitle
                    title={currentTrack?.title as string}
                    subTitle={currentTrack?.artist as string}
                    titleFontSize='xl'
                    subtitleFontSize='sm'
                  />
                </div>
                <div className='w-full'>
                  <Slider onChange={onChange} onSliderClick={onSliderClick} />
                </div>
                <div className='w-full flex items-center justify-center gap-8'>
                  <Button
                    icon={<RiShuffleFill size={22} />}
                    variant='unstyled'
                    onClick={() => {
                      console.log('play');
                    }}
                  />
                  <div className='flex items-center justify-center gap-6'>
                    <Button
                      icon={<RiSkipBackFill size={34} />}
                      variant='unstyled'
                      onClick={() => {
                        audio.playPrevious();
                      }}
                    />
                    <Button
                      onClick={() => {
                        audio.audioState.playbackState !== 'playing' ? audio.play() : audio.pause();
                      }}
                      variant='unstyled'
                      icon={
                        <PlayerStatusIndicator currentTrack={currentTrack as Track} size={70} />
                      }
                    />
                    <Button
                      icon={<RiSkipForwardFill size={35} />}
                      variant='unstyled'
                      onClick={() => {
                        audio.playNext();
                      }}
                    />
                  </div>
                  <Button
                    icon={<RiRepeatFill size={22} />}
                    variant='unstyled'
                    onClick={() => {
                      console.log('play');
                    }}
                  />
                </div>
              </div>
            </Fragment>
          ) : null}
        </Sheet.Content>
      </Sheet.Container>
    </Sheet>
  );
});

export default Player;
