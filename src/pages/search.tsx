import { useContext, useEffect, useState } from 'react';
import { RiCloseCircleLine, RiSearch2Line } from 'react-icons/ri';
import { useSnapshot } from 'valtio';
import SearchBar from '~components/SearchBar/SearchBar';
import AudioListItemContainer from '~containers/AudioListContainer';
import SectionContainer from '~containers/SectionContainer';
import { AudioXContext } from '~contexts/audioX.context';
import { saveHistory, updateTrackAndPlayerState } from '~helpers/business';
import { createMediaTrack, isValidArray } from '~helpers/common';
import { TILE_CONFIG } from '~helpers/data.config';
import useFetch from '~hooks/useFetch.hook';
import endpoints from '~network/endpoints';
import { baseActions, baseState } from '~states/base';
import { Track } from '~types/common.types';
import { SearchItem } from '~types/component.types';
import { storage } from '~utils/storage';

const search_history_config = {
  keyword: 'text'
};

const Search = () => {
  const audio = useContext(AudioXContext);
  const { searchHistory } = useSnapshot(baseState);

  const [keyword, setKeyword] = useState('');
  const onChange = (text: string) => {
    setKeyword(text);
  };

  const onClear = () => {
    if (keyword.length) {
      setKeyword('');
    }
  };

  useEffect(() => {
    const searchHistory: string | null = storage.getItem('search_history');
    if (searchHistory) {
      baseActions.updateSearchHistory(JSON.parse(searchHistory));
    }
  }, []);

  const { data: results, refetch } = useFetch({
    queryKey: [`search_${keyword}`],
    queryFn: async () => await endpoints.searchStation(keyword, 1, 10),
    shouldFetchOnLoad: false
  });

  const refetchData = async () => {
    await refetch().then(({ isRefetchError, data: respData }) => {
      if (!isRefetchError && isValidArray(respData?.data?.stations) && keyword.length) {
        saveHistory(keyword);
      }
    });
  };

  const onEnter = () => {
    refetchData().then(() => {
      console.log('RE_FETCH DONE');
    });
  };

  const onSearchHistoryActionPress = (text: string) => {
    onChange(text);
    setTimeout(() => {
      onEnter();
    }, 500);
  };

  const onAudioItemClick = (item: any) => {
    const mediaTrack = createMediaTrack(item);
    const track: Track = {
      ...mediaTrack,
      dominantColor: item.dominantColor
    };
    audio.addMediaAndPlay(mediaTrack);
    updateTrackAndPlayerState(track);
  };

  return (
    <div className='flex flex-col gap-4 pt-2 relative'>
      <div className='px-3 sticky top-0 z-10 w-full'>
        <SearchBar
          inputConfig={{
            value: keyword,
            placeHolder: 'Search your favorite radio',
            onChange: onChange,
            styleConfig: {
              padding: '2xs',
              fontSize: 'lg',
              fonWeight: 'medium',
              radius: 'none'
            },
            onKeyDown: onEnter
          }}
          styleConfig={{
            padding: '2xs',
            radius: 'lg'
          }}
          iconButtonConfig={{
            variant: 'unstyled',
            icon: keyword.length ? <RiCloseCircleLine size='22' /> : <RiSearch2Line size='22' />,
            onClick: onClear,
            radius: 'full',
            customClass: 'p-2 w-full'
          }}
        />
      </div>
      {isValidArray(results?.data?.stations) && keyword.length ? (
        <div className='h-[70vh] pb-12 overflow-scroll no-scrollbar'>
          <AudioListItemContainer
            data={results?.data?.stations}
            config={TILE_CONFIG}
            onClick={onAudioItemClick}
          />
        </div>
      ) : (
        <div>
          {isValidArray(searchHistory as SearchItem[]) ? (
            <SectionContainer
              containerType='search_history'
              containerConfig={{
                searchHistoryContainerConfig: {
                  config: search_history_config,
                  data: searchHistory as SearchItem[],
                  displayType: 'default',
                  onClick: onSearchHistoryActionPress
                }
              }}
              sectionHeaderConfig={{
                textLinkConfig: {
                  text: 'Recently Searched',
                  fontSize: 'xl',
                  fontWeight: 'bold'
                }
              }}
            />
          ) : (
            <div></div>
          )}
        </div>
      )}
    </div>
  );
};

export default Search;
