import { useState } from "react";
import { useNavigate } from "react-router-dom";
import Button from "~components/Button/Button";
import { bottomNav } from "~constants/common";

const BottomNavContainer = () => {
  const [selectedTab, setSelectedTab] = useState(0);
  const navigate = useNavigate();
  const onTabSelect = (id: number, path: string) => {
    setSelectedTab(id);
    navigate(path);
  };

  return (
    <div className="flex justify-between absolute bg-bgPrimary bottom-0 left-0 right-0 w-full shadow-md">
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
                selectedTab === idx ? "text-textAccent" : "bg-transparent"
              }
            />
          }
          iconPosition="top"
          customClass={`
          py-4 w-full  
          active:bg-btnDarkHover hover:bg-btnDarkHover bg-transparent
          `}
          radius="none"
        />
      ))}
    </div>
  );
};

export default BottomNavContainer;
