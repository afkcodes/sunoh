import { AudioState, AudioX, MediaTrack } from "audio_x";
import { Fragment } from "react";
import Greetings from "~components/Greetings/Greetings";
import SectionContainer from "~containers/SectionContainer";
import { CITY_RADIO_TILE_CONFIG } from "~helpers/data.config";
import useFetch from "~hooks/useFetch.hook";
import endpoints from "~network/endpoints";

const audio = new AudioX();

const Home = () => {
  const {
    data: cityData,
    isSuccess,
    isError,
  } = useFetch({
    queryKey: ["home"],
    queryFn: async () =>
      await endpoints.getStationsByLocationType("city", "mumbai"),
  });

  audio.subscribe("AUDIO_X_STATE", (data: AudioState) => {
    console.log({ ...data });
  });

  const onTileClick = (item: any) => {
    const mediaTrack: MediaTrack = {
      artwork: [
        {
          src: item.imageUrl,
          name: item.name,
          sizes: "200x200",
        },
      ],
      source: item.stream.url,
      title: item.name,
      artist: item.locations[0].city.name,
    };
    audio.addMediaAndPlay(mediaTrack);
  };
  return (
    <div className="justify-center w-full place-items-center gap-4 pt-4 pb-20">
      <Greetings />
      {!isError && isSuccess ? (
        <Fragment>
          <SectionContainer
            sectionHeaderConfig={{
              textLinkConfig: {
                text: "Recently Added",
                fontSize: "xl",
                fontWeight: "bold",
              },
              actionButtonConfig: {
                text: "VIEW ALL",
                onClick: () => {},
                variant: "tertiary",
                fontSize: "xs",
                fontWeight: "bold",
                isCapitalized: true,
                customClass: "p-2",
                radius: "full",
              },
            }}
            containerType="tile"
            containerConfig={{
              data: cityData?.data.slice(10, 20),
              config: CITY_RADIO_TILE_CONFIG,
              tileStyleConfig: {
                shape: "rounded_square",
                size: "2xl",
                fit: "fill",
              },
              onClick: onTileClick,
              displayType: "carousel",
            }}
          />
          <SectionContainer
            sectionHeaderConfig={{
              textLinkConfig: {
                text: "Trending Now",
                fontSize: "xl",
                fontWeight: "bold",
              },
              actionButtonConfig: {
                text: "VIEW ALL",
                onClick: () => {},
                variant: "tertiary",
                fontSize: "xs",
                fontWeight: "bold",
                isCapitalized: true,
                customClass: "p-2",
                radius: "full",
              },
            }}
            containerType="tile"
            containerConfig={{
              data: cityData?.data.slice(0, 10),
              config: CITY_RADIO_TILE_CONFIG,
              tileStyleConfig: {
                shape: "rounded_square",
                size: "2xl",
                fit: "fill",
              },
              onClick: onTileClick,
              displayType: "carousel",
            }}
          />
          <SectionContainer
            sectionHeaderConfig={{
              textLinkConfig: {
                text: "Nearby Stations",
                fontSize: "xl",
                fontWeight: "bold",
              },
              actionButtonConfig: {
                text: "VIEW ALL",
                onClick: () => {},
                variant: "tertiary",
                fontSize: "xs",
                fontWeight: "bold",
                isCapitalized: true,
                customClass: "p-2",
                radius: "full",
              },
            }}
            containerType="tile"
            containerConfig={{
              data: cityData?.data.slice(20, 30),
              config: CITY_RADIO_TILE_CONFIG,
              tileStyleConfig: {
                shape: "rounded_square",
                size: "2xl",
                fit: "fill",
              },
              onClick: onTileClick,
              displayType: "carousel",
            }}
          />
        </Fragment>
      ) : null}
    </div>
  );
};

export default Home;
