import BottomNavContainer from "./BottomNavContainer";
import ContentContainer from "./ContentContainer";

const LayoutContainer = () => {
  return (
    <main className="bg-bgPrimary text-textLight  px-2 relative">
      <ContentContainer />
      <BottomNavContainer />
    </main>
  );
};

export default LayoutContainer;
