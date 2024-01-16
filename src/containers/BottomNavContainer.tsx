import { MediaTrack } from 'audio_x';
import { useContext } from 'react';
import { useNavigate } from 'react-router-dom';
import { useSnapshot } from 'valtio';
import Button from '~components/Button/Button';
import MiniPlayer from '~components/MiniPlayer/MiniPlayer';
import { bottomNav } from '~constants/common';
import { AudioXContext } from '~contexts/audioX.context';
import { isValidObject } from '~helpers/common';
import { playerActions, playerState } from '~states/player';
import { tabActions, tabState } from '~states/tab';

const BottomNavContainer = () => {
  const snap = useSnapshot(tabState);
  const navigate = useNavigate();
  const { currentTrack } = useSnapshot(playerState);
  const audio = useContext(AudioXContext);
  const onTabSelect = (id: number, path: string) => {
    tabActions.setTab(id);
    navigate(path);
  };
  // const bottomNavRef = useRef<HTMLDivElement>(null);
  // const initialHeight = useRef<any>(null);

  // useEffect(() => {
  //   if (isValidWindow) {
  //     initialHeight.current = window.innerHeight;
  //     const handleResize = () => {
  //       const latestHeight = window.innerHeight;
  //       if (latestHeight < initialHeight.current && snap.isInputFocussed) {
  //         if (bottomNavRef.current) {
  //           bottomNavRef.current.style.bottom = `${-500}px`;
  //         }
  //       } else {
  //         if (bottomNavRef.current) {
  //           bottomNavRef.current.style.bottom = `${0}px`;
  //         }
  //       }
  //     };
  //     window.addEventListener('resize', handleResize);
  //     return () => {
  //       window.removeEventListener('resize', handleResize);
  //     };
  //   }
  // }, [snap.isInputFocussed]);

  return (
    <div className='fixed bottom-0 w-full'>
      {isValidObject(currentTrack) ? (
        <MiniPlayer
          audio={audio}
          currentTrack={currentTrack as MediaTrack}
          onClick={() => {
            playerActions.setFullPlayerState(true);
          }}
        />
      ) : null}
      <div className='flex w-full bg-bgSecondary '>
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
        M
      </div>
    </div>
  );
};

export default BottomNavContainer;
