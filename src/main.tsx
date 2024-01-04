import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { AudioX } from 'audio_x';
import React from 'react';
import ReactDOM from 'react-dom/client';
import { RouterProvider } from 'react-router-dom';

import AudioXProvider from '~contexts/audioX.context.tsx';
import './index.css';
import router from './routes/router.tsx';

const queryClient = new QueryClient();
const audio: AudioX = new AudioX();

audio.init({
  autoPlay: false,
  useDefaultEventListeners: true,
  mode: 'REACT',
  showNotificationActions: true,
  preloadStrategy: 'none',
  playbackRate: 1,
  enableEQ: true,
  enablePlayLog: true,
  enableHls: true,
  hlsConfig: {
    startLevel: -1
  }
});

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <QueryClientProvider client={queryClient}>
      <AudioXProvider audioX={audio}>
        <RouterProvider router={router} />
      </AudioXProvider>
    </QueryClientProvider>
  </React.StrictMode>
);
