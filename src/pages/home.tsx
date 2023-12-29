import Tile from "~components/Tile/Tile";

const Home = () => {
  return (
    <div>
      <div>Home</div>
      <Tile
        figureConfig={{
          src: "https://pbs.twimg.com/media/GAbHm-GaUAADByK?format=jpg&name=large",
          alt: "",
          size: "3xl",
          shape: "rounded_square",
        }}
        tileConfig={{ shape: "rounded_square", size: "3xl" }}
        titleSubtitleConfig={{ title: "Papa Meri Jaan", subTitle: "Animal" }}
      />
    </div>
  );
};

export default Home;
