import { ChangeEvent, useState } from 'react';
import { RiCloseCircleLine, RiSearch2Line } from 'react-icons/ri';
import SearchBar from '~components/SearchBar/SearchBar';

const Search = () => {
  const [key, setKey] = useState('');
  const onChange = (e: ChangeEvent<HTMLInputElement>) => {
    setKey(e.target.value);
  };

  const onClear = () => {
    if (key.length) {
      setKey('');
    }
  };

  return (
    <div className='px-3 pt-2'>
      <SearchBar
        inputConfig={{
          value: key,
          placeHolder: 'Search your favorite radio',
          onChange: onChange,
          styleConfig: {
            padding: '2xs',
            fontSize: 'lg',
            fonWeight: 'medium',
            radius: 'none'
          }
        }}
        styleConfig={{
          padding: '2xs',
          radius: 'lg'
        }}
        iconButtonConfig={{
          variant: 'unstyled',
          icon: key.length ? <RiCloseCircleLine size='22' /> : <RiSearch2Line size='22' />,
          onClick: onClear,
          radius: 'full',
          customClass: 'p-2 w-full'
        }}
      />
    </div>
  );
};

export default Search;
