import { RiHome5Line, RiSearchLine, RiSettings4Line, RiUser3Line } from 'react-icons/ri';

const bottomNav = [
  {
    id: 1,
    text: 'Home',
    icon: RiHome5Line,
    path: '/'
  },
  {
    id: 2,
    text: 'Search',
    icon: RiSearchLine,
    path: '/search'
  },
  {
    id: 3,
    text: 'Profile',
    icon: RiUser3Line,
    path: '/profile'
  },
  {
    id: 4,
    text: 'Settings',
    icon: RiSettings4Line,
    path: '/settings'
  }
];

export { bottomNav };
