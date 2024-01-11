import { createBrowserRouter } from 'react-router-dom';
import LayoutContainer from '~containers/LayoutContainer';
import Home from '~pages/home';
import Playlist from '~pages/playlist';
import Profile from '~pages/profile';
import Search from '~pages/search';
import Settings from '~pages/settings';

const router = createBrowserRouter([
  {
    path: '/',
    element: <LayoutContainer />,
    children: [
      {
        path: '/',
        element: <Home key='home' />,
        index: true
      },
      {
        path: '/:category/view-all',
        element: <Search key='search' />
      },
      {
        path: '/search',
        element: <Search key='search' />
      },
      {
        path: '/profile',
        element: <Profile key='profile' />
      },
      {
        path: '/settings',
        element: <Settings key='settings' />
      },
      {
        path: '/playlist/:id',
        element: <Playlist />
      }
    ]
  }
]);

export default router;
