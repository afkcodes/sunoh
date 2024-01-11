import { Outlet, useLocation } from 'react-router-dom';
import PageTransitionContainer from './PageTransitionContainter';

const ContentContainer = () => {
  const location = useLocation();
  console.log(location);

  return (
    <PageTransitionContainer key={location.pathname}>
      <Outlet />
    </PageTransitionContainer>
  );
};

export default ContentContainer;
