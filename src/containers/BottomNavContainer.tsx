import { useContext, useEffect, useRef } from 'react';
import { useNavigate } from 'react-router-dom';
import { useSnapshot } from 'valtio';
import Button from '~components/Button/Button';
import MiniPlayer from '~components/MiniPlayer/MiniPlayer';
import { bottomNav } from '~constants/common';
import { AudioXContext } from '~contexts/audioX.context';
import { isValidObject, isValidWindow } from '~helpers/common';
import { playerState } from '~states/player';
import { tabActions, tabState } from '~states/tab';
import { Track } from '~types/common.types';

const BottomNavContainer = () => {
  const snap = useSnapshot(tabState);
  const { currentTrack } = useSnapshot(playerState);
  const navigate = useNavigate();
  const onTabSelect = (id: number, path: string) => {
    tabActions.setTab(id);
    navigate(path);
  };
  const audio = useContext(AudioXContext);
  const bottomNavRef = useRef<HTMLDivElement>(null);
  const initialHeight = useRef<any>(null);

  useEffect(() => {
    if (isValidWindow) {
      initialHeight.current = window.innerHeight;
      const handleResize = () => {
        const latestHeight = window.innerHeight;
        if (latestHeight < initialHeight.current && snap.isInputFocussed) {
          if (bottomNavRef.current) {
            bottomNavRef.current.style.bottom = `${-500}px`;
          }
        } else {
          if (bottomNavRef.current) {
            bottomNavRef.current.style.bottom = `${0}px`;
          }
        }
      };
      window.addEventListener('resize', handleResize);
      return () => {
        window.removeEventListener('resize', handleResize);
      };
    }
  }, [snap.isInputFocussed]);

  return (
    <div
      ref={bottomNavRef}
      className={`
      flex flex-col justify-between fixed transition-all ease-in-out duration-300 bottom-0 bg-bgSecondary shadow-elevation-3 w-full  left-0 right-0 z-10

      `}
    >
      {isValidObject(currentTrack) ? (
        <MiniPlayer currentTrack={currentTrack as Track} audio={audio} />
      ) : null}
      <div className='flex'>
        {bottomNav.map((navItem, idx) => (
          <Button
            key={navItem.id}
            onClick={() => onTabSelect(idx, navItem.path)}
            variant='tertiary'
            fontWeight='normal'
            fontSize='base'
            icon={
              <navItem.icon
                size={26}
                className={snap.currentTab === idx ? 'text-textAccent' : 'bg-transparent'}
              />
            }
            iconPosition='top'
            customClass={`
          py-4 w-full  
          active:bg-btnDarkHover hover:bg-transparent bg-transparent
          `}
            radius='none'
          />
        ))}
      </div>
    </div>
  );
};

export default BottomNavContainer;
