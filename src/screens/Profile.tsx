import React from 'react';
import { SView } from '~components';
import SText from '~components/SText/SText';

const Profile = () => {
  return (
    <SView display='flex' flex={1}>
      <SText color='primary' fontSize={20} family='medium' marginTop={20}>
        Hello here is cool text Hello here is cool text Hello here is cool text Hello here is cool
        text
      </SText>
      <SText color='primary' fontSize={20} family='regular' marginTop={20}>
        Hello here is cool text Hello here is cool text Hello here is cool text Hello here is cool
        text
      </SText>
      <SText color='primary' fontSize={20} family='semibold' marginTop={20}>
        Hello here is cool text Hello here is cool text Hello here is cool text Hello here is cool
        text
      </SText>

      <SText color='primary' fontSize={20} family='bold' marginTop={20}>
        Hello here is cool text Hello here is cool text Hello here is cool text Hello here is cool
        text
      </SText>

      <SText color='primary' fontSize={20} family='heavy' marginTop={20}>
        Hello here is cool text Hello here is cool text Hello here is cool text Hello here is cool
        text
      </SText>
    </SView>
  );
};

export default Profile;
