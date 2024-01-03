import { useContext } from "react";
import { useNavigate } from "react-router-dom";
import { useSnapshot } from "valtio";
import Button from "~components/Button/Button";
import MiniPlayer from "~components/MiniPlayer/MiniPlayer";
import { bottomNav } from "~constants/common";
import { AudioXContext } from "~contexts/audioX.context";
import { isValidObject } from "~helpers/common";
import { playerState } from "~states/player";
import { tabActions, tabState } from "~states/tab";
import { Track } from "~types/common.types";

const BottomNavContainer = () => {
  const snap = useSnapshot(tabState);
  const { currentTrack } = useSnapshot(playerState);
  const navigate = useNavigate();
  const onTabSelect = (id: number, path: string) => {
    tabActions.setTab(id);
    navigate(path);
  };
  const audio = useContext(AudioXContext);

  return (
    <div className="flex flex-col justify-between fixed bg-bgSecondary shadow-elevation-3 max-w-full bottom-0 left-0 right-0 z-10">
      {isValidObject(currentTrack) ? (
        <MiniPlayer currentTrack={currentTrack as Track} audio={audio} />
      ) : null}
      <div className="flex">
        {bottomNav.map((navItem, idx) => (
          <Button
            key={navItem.id}
            onClick={() => onTabSelect(idx, navItem.path)}
            variant="tertiary"
            fontWeight="normal"
            fontSize="base"
            icon={
              <navItem.icon
                size={26}
                className={
                  snap.currentTab === idx ? "text-textAccent" : "bg-transparent"
                }
              />
            }
            iconPosition="top"
            customClass={`
          py-4 w-full  
          active:bg-btnDarkHover hover:bg-transparent bg-transparent
          `}
            radius="none"
          />
        ))}
      </div>
    </div>
  );
};

export default BottomNavContainer;
