import { Variant } from "./button.types";

const buttonVariantStyle: { [key in Variant]: string } = {
  primary:
    "bg-btnPrimary hover:bg-btnPrimaryHover active:bg-btnPrimaryActive transition-color duration-300",
  secondary:
    "bg-btnSecondary hover:bg-btnSecondaryHover active:bg-btnSecondaryActive transition-color duration-300",
  tertiary:
    "bg-btnDark hover:bg-btnDarkHover active:bg-btnDarkActive transition-color duration-300",
  ghost:
    "bg-btnGhost hover:bg-btnGhostHoverBg active:bg-btnGhostActiveBg hover:border-btnGhostHoverBorder active:border-btnGhostActiveBorder active:border  transition-all duration-300",
  unstyled:
    "bg-transparent active:bg-transparent hover:bg-transparent outline-none ring-none border-none",
};

export { buttonVariantStyle };
