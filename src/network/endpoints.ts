import { Response } from '~types/common.types';
import http from './http';

const baseURL = import.meta.env.VITE_BASE_API_URL;
const routes = {
  getStationByTags: '/station/tags',
  popularStation: '/station/popular',
  updateStreamStatus: '/station/update-stream',
  likeStation: '/station/update-likes',
  updatePlayCount: '/station/update-play-count',
  searchStation: '/station/search'
};

const endpoints = {
  getStationsByLocationType: async (
    locationType: 'city' | 'state' | 'country',
    location: string,
    page: number = 1,
    offset: number = 10
  ) => {
    const data = await http(
      `${baseURL}/${locationType}/${location}?page=${page}&offset=${offset}`,
      {
        method: 'GET'
      }
    );
    return data as Response;
  },

  getStationByTags: async (tags: string) => {
    const data = await http(`${baseURL}${routes.getStationByTags}`, {
      method: 'GET',
      params: {
        name: tags
      }
    });
    return data as Response;
  },

  getPopularStation: async (locationType: 'city' | 'state' | 'country', locationId: string) => {
    const data = await http(`${baseURL}${routes.popularStation}`, {
      method: 'GET',
      params: {
        locationType,
        locationId
      }
    });
    return data as Response;
  },

  updateStreamStatus: async (streamId: string, streamStatus: boolean) => {
    const data = await http(`${baseURL}${routes.updateStreamStatus}`, {
      method: 'POST',
      body: JSON.stringify({
        streamId,
        streamStatus
      })
    });
    return data as Response;
  },

  likeStation: async (radioId: string, likeAction: 'LIKE' | 'UNLIKE', city: string) => {
    const data = await http(`${baseURL}${routes.likeStation}`, {
      method: 'POST',
      params: {
        radioId,
        likeAction,
        city
      }
    });
    return data as Response;
  },

  updatePlayCount: async (radioId: string, city: string) => {
    const data = await http(`${baseURL}${routes.updatePlayCount}`, {
      method: 'POST',
      params: {
        radioId,
        city
      }
    });
    return data as Response;
  },

  searchStation: async (term: string, limit: number, offset: number) => {
    const data = await http(`${baseURL}${routes.searchStation}`, {
      method: 'GET',
      params: {
        term,
        limit,
        offset
      }
    });
    return data as Response;
  }
};

export default endpoints;
