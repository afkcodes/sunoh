import BottomNavContainer from "./BottomNavContainer";
import ContentContainer from "./ContentContainer";

const LayoutContainer = () => {
  return (
    <main className="bg-bgPrimary text-textLight min-h-dvh ">
      <ContentContainer />
      <BottomNavContainer />
    </main>
  );
};

export default LayoutContainer;
