import SearchHistoryItem from '~components/SearchHistoryItem/SearchHistoryItem';
import { SearchHistoryContainerProps } from '~types/component.types';

const SearchHistoryContainer: React.FC<SearchHistoryContainerProps> = ({
  data,
  onClick,
  config
}) => {
  return (
    <div className='px-3'>
      {data.map((item, idx) => (
        <SearchHistoryItem key={idx} data={item} config={config} onClick={onClick} />
      ))}
    </div>
  );
};

export default SearchHistoryContainer;
