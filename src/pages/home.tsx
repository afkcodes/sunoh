import { AudioX, MediaTrack } from "audio_x";
import TileContainer from "~containers/TileContainer";
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
    <div className="grid grid-cols-2 justify-center w-full place-items-center gap-4 pt-4 pb-20">
      {!isError && isSuccess ? (
        <TileContainer
          data={cityData?.data}
          config={CITY_RADIO_TILE_CONFIG}
          tileStyleConfig={{
            shape: "rounded_square",
            size: "2xl",
            fit: "fill",
          }}
          onClick={onTileClick}
        />
      ) : null}
    </div>
  );
};

export default Home;
