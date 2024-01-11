import { Outlet, useLocation } from 'react-router-dom';
import PageTransitionContainer from './PageTransitionContainter';

const ContentContainer = () => {
  const location = useLocation();

  return (
    <PageTransitionContainer key={location.pathname}>
      <Outlet />
    </PageTransitionContainer>
  );
};

export default ContentContainer;
