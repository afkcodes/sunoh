import React from 'react';
import { SView } from '~components';
import Tile from '~components/Tile/Tile';

const Home: React.FC<any> = () => {
  return (
    <SView
      display='flex'
      flexDirection='row'
      flexWrap='wrap'
      padding={20}
      columnGap={20}
      rowGap={50}
    >
      <Tile
        src='https://c.saavncdn.com/153/Hanuman-Chalisa-From-HanuMan-Hindi-Hindi-2023-20230406164727-500x500.jpg'
        size='lg'
      />
    </SView>
  );
};

export default Home;
