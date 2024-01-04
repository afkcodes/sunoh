import SectionHeader from '~components/SectionHeader/SectionHeader';
import { SectionContainerConfig } from '~types/component.types';
import TileContainer from './TileContainer';

const SectionContainer: React.FC<SectionContainerConfig> = ({
  sectionHeaderConfig,
  containerType,
  containerConfig
}) => {
  const { textLinkConfig, actionButtonConfig } = sectionHeaderConfig;
  return (
    <section className='mb-8'>
      <SectionHeader textLinkConfig={textLinkConfig} actionButtonConfig={actionButtonConfig} />
      <div className='mt-4'>
        {containerType === 'tile' ? (
          <TileContainer
            config={containerConfig.config}
            data={containerConfig.data}
            onClick={containerConfig.onClick}
            tileStyleConfig={containerConfig.tileStyleConfig}
            displayType={containerConfig.displayType}
          />
        ) : null}
      </div>
    </section>
  );
};

export default SectionContainer;
