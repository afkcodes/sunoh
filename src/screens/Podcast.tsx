import React from 'react';
import { SView } from '~components';
import SText from '~components/SText/SText';
import { spacing } from '~styles/utilities';

const Podcast = () => {
  return (
    <SView color='primary' flex={1} paddingTop={spacing.md}>
      <SText color='primary' fontSize={40}>
        Hello here is cool text
      </SText>
    </SView>
  );
};

export default Podcast;
