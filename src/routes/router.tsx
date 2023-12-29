import { createBrowserRouter } from "react-router-dom";
import LayoutContainer from "~containers/LayoutContainer";
import Home from "~pages/home";
import Profile from "~pages/profile";
import Search from "~pages/search";
import Settings from "~pages/settings";

const router = createBrowserRouter([
  {
    path: "/",
    element: <LayoutContainer />,
    children: [
      {
        path: "/",
        element: <Home />,
        index: true,
      },
      {
        path: "/search",
        element: <Search />,
      },
      {
        path: "/profile",
        element: <Profile />,
      },
      {
        path: "/settings",
        element: <Settings />,
      },
    ],
  },
]);

export default router;
