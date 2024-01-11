import { Fragment, memo } from 'react';
import { useNavigate } from 'react-router-dom';
import Greetings from '~components/Greetings/Greetings';
import SectionContainer from '~containers/SectionContainer';
import { HOME_CONFIG } from '~helpers/data.config';
import useFetch from '~hooks/useFetch.hook';
import { musicEndpoints } from '~network/music';

const Home = memo(() => {
  const navigate = useNavigate();

  const { data, isSuccess, isError } = useFetch({
    queryKey: ['home'],
    queryFn: async () => await musicEndpoints.home()
  });

  const onTileClick = (item: any) => {
    navigate(`/playlist/${item.id}`, { state: item });
  };

  return (
    <div className='justify-center w-full place-items-center gap-4 pt-4 pb-28'>
      <Greetings />
      {!isError && isSuccess ? (
        <Fragment>
          <SectionContainer
            sectionHeaderConfig={{
              textLinkConfig: {
                text: data?.data[0].title,
                fontSize: 'xl',
                fontWeight: 'bold'
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
                radius: 'full'
              }
            }}
            containerType='tile'
            containerConfig={{
              tileContainerConfig: {
                data: data?.data[0].items,
                config: HOME_CONFIG,
                tileStyleConfig: {
                  shape: 'rounded_square',
                  size: '2xl',
                  fit: 'fill'
                },
                onClick: onTileClick,
                displayType: 'carousel'
              }
            }}
          />
          <SectionContainer
            sectionHeaderConfig={{
              textLinkConfig: {
                text: data?.data[2].title,
                fontSize: 'xl',
                fontWeight: 'bold'
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
                radius: 'full'
              }
            }}
            containerType='tile'
            containerConfig={{
              tileContainerConfig: {
                data: data?.data[2].items,
                config: HOME_CONFIG,
                tileStyleConfig: {
                  shape: 'rounded_square',
                  size: '2xl',
                  fit: 'fill'
                },
                onClick: onTileClick,
                displayType: 'carousel'
              }
            }}
          />
          <SectionContainer
            sectionHeaderConfig={{
              textLinkConfig: {
                text: data?.data[3].title,
                fontSize: 'xl',
                fontWeight: 'bold'
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
                radius: 'full'
              }
            }}
            containerType='tile'
            containerConfig={{
              tileContainerConfig: {
                data: data?.data[3].items,
                config: HOME_CONFIG,
                tileStyleConfig: {
                  shape: 'rounded_square',
                  size: '2xl',
                  fit: 'fill'
                },
                onClick: onTileClick,
                displayType: 'carousel'
              }
            }}
          />
          <SectionContainer
            sectionHeaderConfig={{
              textLinkConfig: {
                text: data?.data[4].title,
                fontSize: 'xl',
                fontWeight: 'bold'
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
                radius: 'full'
              }
            }}
            containerType='tile'
            containerConfig={{
              tileContainerConfig: {
                data: data?.data[4].items,
                config: HOME_CONFIG,
                tileStyleConfig: {
                  shape: 'rounded_square',
                  size: '2xl',
                  fit: 'fill'
                },
                onClick: onTileClick,
                displayType: 'carousel'
              }
            }}
          />
          <SectionContainer
            sectionHeaderConfig={{
              textLinkConfig: {
                text: data?.data[6].title,
                fontSize: 'xl',
                fontWeight: 'bold'
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
                radius: 'full'
              }
            }}
            containerType='tile'
            containerConfig={{
              tileContainerConfig: {
                data: data?.data[6].items,
                config: HOME_CONFIG,
                tileStyleConfig: {
                  shape: 'circle',
                  size: '2xl',
                  fit: 'fill'
                },
                onClick: onTileClick,
                displayType: 'carousel'
              }
            }}
          />
        </Fragment>
      ) : null}
    </div>
  );
});

export default Home;
