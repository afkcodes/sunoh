// PageTransitionContainer.tsx
import { AnimatePresence, motion } from 'framer-motion';
import React, { ReactNode } from 'react';
import { useLocation } from 'react-router-dom';

interface PageTransitionContainerProps {
  children: ReactNode;
}

const PageTransitionContainer: React.FC<PageTransitionContainerProps> = ({ children }) => {
  const location = useLocation();
  return (
    <AnimatePresence mode='wait'>
      <motion.div
        key={location.pathname}
        initial={{ opacity: 0, y: 30 }}
        animate={{ opacity: 1, y: 0 }}
        exit={{ opacity: 0, y: 30 }}
        transition={{ duration: 0.2 }}
      >
        {children}
      </motion.div>
    </AnimatePresence>
  );
};

export default PageTransitionContainer;
