import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { AudioX } from "audio_x";
import React from "react";
import ReactDOM from "react-dom/client";
import { RouterProvider } from "react-router-dom";
import "./index.css";
import router from "./routes/router.tsx";

const queryClient = new QueryClient();
const audio = new AudioX();

audio.init({
  mode: "REACT",
  autoPlay: false,
  useDefaultEventListeners: true,
  enableHls: true,
  showNotificationActions: true,
});

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <QueryClientProvider client={queryClient}>
      <RouterProvider router={router} />
    </QueryClientProvider>
  </React.StrictMode>
);
