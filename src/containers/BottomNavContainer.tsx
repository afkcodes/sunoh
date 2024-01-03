import { useNavigate } from "react-router-dom";
import { useSnapshot } from "valtio";
import Button from "~components/Button/Button";
import MiniPlayer from "~components/MiniPlayer/MiniPlayer";
import { bottomNav } from "~constants/common";
import { tabActions, tabState } from "~states/tab";

const BottomNavContainer = () => {
  const snap = useSnapshot(tabState);
  const navigate = useNavigate();
  const onTabSelect = (id: number, path: string) => {
    tabActions.setTab(id);
    navigate(path);
  };

  return (
    <div className="flex flex-col justify-between fixed bg-bgSecondary shadow-elevation-3 max-w-full bottom-0 left-0 right-0 z-10">
      <MiniPlayer />
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
