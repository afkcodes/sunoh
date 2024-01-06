import SectionHeader from '~components/SectionHeader/SectionHeader';
import { SectionContainerConfig } from '~types/component.types';
import SearchHistoryContainer from './SearchHistoryContainer';
import TileContainer from './TileContainer';

const SectionContainer: React.FC<SectionContainerConfig> = ({
  sectionHeaderConfig,
  containerType,
  containerConfig
}) => {
  const { textLinkConfig, actionButtonConfig } = sectionHeaderConfig;
  const { tileContainerConfig, searchHistoryContainerConfig } = containerConfig;
  return (
    <section className='mb-8'>
      <SectionHeader textLinkConfig={textLinkConfig} actionButtonConfig={actionButtonConfig} />
      <div className='mt-2'>
        {containerType === 'tile' && tileContainerConfig ? (
          <TileContainer
            config={tileContainerConfig.config}
            data={tileContainerConfig.data}
            onClick={tileContainerConfig.onClick}
            tileStyleConfig={tileContainerConfig.tileStyleConfig}
            displayType={tileContainerConfig.displayType}
          />
        ) : null}

        {containerType === 'search_history' && searchHistoryContainerConfig ? (
          <SearchHistoryContainer
            config={searchHistoryContainerConfig.config}
            data={searchHistoryContainerConfig.data}
            onClick={searchHistoryContainerConfig.onClick}
          />
        ) : null}
      </div>
    </section>
  );
};

export default SectionContainer;
