import { memo, useContext } from 'react';
import { useLocation } from 'react-router-dom';
import HeroContainer from '~containers/HeroContainer';
import SectionContainer from '~containers/SectionContainer';
import { AudioXContext } from '~contexts/audioX.context';
import { updateTrackAndPlayerState } from '~helpers/business';
import { createMediaTrack } from '~helpers/common';
import { AUDIO_LIST_CONFIG, HOME_CONFIG } from '~helpers/data.config';
import useFetch from '~hooks/useFetch.hook';
import { musicEndpoints } from '~network/music';

const Playlist = memo(() => {
  const { state } = useLocation();
  const audio = useContext(AudioXContext);
  const { data, isSuccess, isError } = useFetch({
    queryKey: [`playlist${state.id}`],
    queryFn: async () => await musicEndpoints.playlist(state.id)
  });

  const onSongItemClick = async (item: any) => {
    const data = await musicEndpoints.getSongData(item.id);
    const mediaTrack = createMediaTrack(data.data);
    console.log(mediaTrack);
    audio.addMediaAndPlay(mediaTrack);
    updateTrackAndPlayerState(mediaTrack);
  };
  return (
    <div className='pt-4 pb-28'>
      <div className='relative z-1'>
        <HeroContainer data={state} config={HOME_CONFIG} />
      </div>
      <div className='mt-12'>
        {isSuccess && !isError ? (
          <SectionContainer
            containerConfig={{
              audioListItemContainerConfig: {
                data: data?.data.songs,
                config: AUDIO_LIST_CONFIG,
                onClick: onSongItemClick
              }
            }}
            containerType='audio_list'
            sectionHeaderConfig={{
              textLinkConfig: {
                text: ''
              }
            }}
          />
        ) : null}
      </div>
    </div>
  );
});

export default Playlist;
