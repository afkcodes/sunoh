import Player from '~components/Player';
import BottomNavContainer from './BottomNavContainer';
import ContentContainer from './ContentContainer';

const LayoutContainer = () => {
  return (
    <main vaul-drawer-wrapper='' className='bg-bgPrimary text-textLight h-dvh '>
      <ContentContainer />
      <BottomNavContainer />
      <Player />
    </main>
  );
};

export default LayoutContainer;
