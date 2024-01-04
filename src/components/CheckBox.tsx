interface CheckboxProps {
  checked: boolean;
  onChange: (event: React.ChangeEvent<HTMLInputElement>) => void;
  customClass?: string;
}

const Checkbox: React.FC<CheckboxProps> = ({ checked, onChange, customClass }) => {
  return (
    <input
      type='checkbox'
      checked={checked}
      onChange={onChange}
      className={`h-4 w-4 accent-primaryAccent ${customClass}`}
    />
  );
};

export default Checkbox;
