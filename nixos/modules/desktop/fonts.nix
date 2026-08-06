{pkgs, ...}: {
  fonts.packages = with pkgs; [
    nerd-fonts.iosevka
    (iosevka-bin.override {variant = "Aile";})
    (iosevka-bin.override {variant = "Etoile";})
    noto-fonts-color-emoji
  ];

  fonts.fontconfig.defaultFonts = {
    sansSerif = ["Iosevka Aile"];
    serif = ["Iosevka Etoile"];
    monospace = ["Iosevka Nerd Font Mono"];
    emoji = ["Noto Color Emoji"];
  };
}
