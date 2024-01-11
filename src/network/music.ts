import { Response } from '~types/common.types';
import http from './http';

const baseURL = 'http://localhost:3000';

const musicEndpoints = {
  home: async () => {
    const data = await http(`${baseURL}/music/listen`, {
      method: 'GET'
    });
    return data as Response;
  },
  playlist: async (id: string) => {
    const data = await http(`${baseURL}/music/playlist/${id}`, {
      method: 'GET'
    });
    return data as Response;
  },
  getSongData: async (id: string) => {
    const data = await http(`${baseURL}/music/song/${id}`, {
      method: 'GET'
    });
    return data as Response;
  }
};

export { musicEndpoints };
