import { RiArrowLeftUpLine, RiHistoryLine } from 'react-icons/ri';
import { dataExtractor } from '~helpers/common';
import { SearchHistoryItemProps } from '~types/component.types';

const SearchHistoryItem: React.FC<SearchHistoryItemProps> = ({ data, config, onClick }) => {
  const keyword = dataExtractor(data, config.keyword);
  const onActionItemClick = (e: any) => {
    e.preventDefault();
    onClick(keyword);
  };
  return (
    <button onClick={onActionItemClick} className={`flex w-full justify-between py-3 items-center`}>
      <div className='flex h-full items-center'>
        <RiHistoryLine size={20} className='text-textMedium' />
        <p className='ml-2 font-medium text-textMedium'>{keyword}</p>
      </div>
      <RiArrowLeftUpLine size={24} />
    </button>
  );
};

export default SearchHistoryItem;
