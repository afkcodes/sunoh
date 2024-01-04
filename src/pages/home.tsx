import { Fragment, useContext } from 'react';
import { useNavigate } from 'react-router-dom';
import Greetings from '~components/Greetings/Greetings';
import SectionContainer from '~containers/SectionContainer';
import { AudioXContext } from '~contexts/audioX.context';
import { createMediaTrack } from '~helpers/common';
import { TILE_CONFIG } from '~helpers/data.config';
import useFetch from '~hooks/useFetch.hook';
import endpoints from '~network/endpoints';
import { playerState } from '~states/player';
import { Track } from '~types/common.types';
import { storage } from '~utils/storage';

const Home = () => {
  const audio = useContext(AudioXContext);
  const navigate = useNavigate();

  const {
    data: cityData,
    isSuccess,
    isError,
  } = useFetch({
    queryKey: ['home'],
    queryFn: async () =>
      await endpoints.getStationsByLocationType('city', 'mumbai', 1, 40),
  });

  const onTileClick = (item: any) => {
    const mediaTrack = createMediaTrack(item);
    const track: Track = {
      ...mediaTrack,
      dominantColor: item.dominantColor,
    };
    audio.addMediaAndPlay(mediaTrack);
    storage.setItem('current_track', JSON.stringify(track));
    playerState.currentTrack = track;
  };

  console.log('RERendering home');

  return (
    <div className='justify-center w-full place-items-center gap-4 pt-4 pb-28'>
      <Greetings />
      {!isError && isSuccess ? (
        <Fragment>
          <SectionContainer
            sectionHeaderConfig={{
              textLinkConfig: {
                text: 'Recently Added',
                fontSize: 'xl',
                fontWeight: 'bold',
              },
              actionButtonConfig: {
                text: 'VIEW ALL',
                onClick: () => {
                  navigate('/recently-added/view-all');
                },
                variant: 'tertiary',
                fontSize: 'xs',
                fontWeight: 'bold',
                isCapitalized: true,
                customClass: 'p-2',
                radius: 'full',
              },
            }}
            containerType='tile'
            containerConfig={{
              data: cityData?.data.stations.slice(10, 20),
              config: TILE_CONFIG,
              tileStyleConfig: {
                shape: 'rounded_square',
                size: '2xl',
                fit: 'fill',
              },
              onClick: onTileClick,
              displayType: 'carousel',
            }}
          />
          <SectionContainer
            sectionHeaderConfig={{
              textLinkConfig: {
                text: 'Trending Now',
                fontSize: 'xl',
                fontWeight: 'bold',
              },
              actionButtonConfig: {
                text: 'VIEW ALL',
                onClick: () => {},
                variant: 'tertiary',
                fontSize: 'xs',
                fontWeight: 'bold',
                isCapitalized: true,
                customClass: 'p-2',
                radius: 'full',
              },
            }}
            containerType='tile'
            containerConfig={{
              data: cityData?.data.stations.slice(0, 10),
              config: TILE_CONFIG,
              tileStyleConfig: {
                shape: 'rounded_square',
                size: '2xl',
                fit: 'fill',
              },
              onClick: onTileClick,
              displayType: 'carousel',
            }}
          />
          <SectionContainer
            sectionHeaderConfig={{
              textLinkConfig: {
                text: 'Nearby Stations',
                fontSize: 'xl',
                fontWeight: 'bold',
              },
              actionButtonConfig: {
                text: 'VIEW ALL',
                onClick: () => {},
                variant: 'tertiary',
                fontSize: 'xs',
                fontWeight: 'bold',
                isCapitalized: true,
                customClass: 'p-2',
                radius: 'full',
              },
            }}
            containerType='tile'
            containerConfig={{
              data: cityData?.data.stations.slice(20, 30),
              config: TILE_CONFIG,
              tileStyleConfig: {
                shape: 'rounded_square',
                size: '2xl',
                fit: 'fill',
              },
              onClick: onTileClick,
              displayType: 'carousel',
            }}
          />
        </Fragment>
      ) : null}
    </div>
  );
};

export default Home;
