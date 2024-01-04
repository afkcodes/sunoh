import Button from '~components/Button/Button';
import TextLink from '~components/TextLink/TextLink';
import { SectionHeaderProps } from '~types/component.types';

const SectionHeader: React.FC<SectionHeaderProps> = ({ actionButtonConfig, textLinkConfig }) => {
  return (
    <div className='flex justify-between items-center px-3'>
      <div>
        <TextLink
          text={textLinkConfig.text}
          fontSize={textLinkConfig.fontSize}
          fontWeight={textLinkConfig.fontWeight}
        />
      </div>
      <div>
        <Button
          text={actionButtonConfig.text}
          variant={actionButtonConfig.variant}
          onClick={actionButtonConfig.onClick}
          fontSize={actionButtonConfig.fontSize}
          fontWeight={actionButtonConfig.fontWeight}
          customClass={actionButtonConfig.customClass}
          radius={actionButtonConfig.radius}
          isCapitalized={actionButtonConfig.isCapitalized}
        />
      </div>
    </div>
  );
};

export default SectionHeader;
