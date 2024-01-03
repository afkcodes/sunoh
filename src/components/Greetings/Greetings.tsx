import { RiSearchLine } from "react-icons/ri";
import Button from "~components/Button/Button";
import TextLink from "~components/TextLink/TextLink";
import { getGreeting } from "~helpers/common";

const Greetings = () => {
  const greeting = getGreeting();
  return (
    <section className="flex px-3 mb-4 justify-between items-center">
      <div className="flex flex-col">
        <TextLink fontSize="2xl" text={greeting} fontWeight="bold" />
      </div>
      <div className="self-start">
        <Button
          icon={<RiSearchLine size={22} />}
          onClick={() => {}}
          variant="tertiary"
          customClass="p-2 "
          radius="full"
        />
      </div>
    </section>
  );
};

export default Greetings;
