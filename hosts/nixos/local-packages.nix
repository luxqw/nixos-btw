{pkgs, ...}: {
  users.users.lux.packages = with pkgs; [
    tree
    foot
    neovim
    gcc
    lua-language-server
    nil
    alejandra
    adwaita-icon-theme
    gnome-themes-extra
    nitch
    thunar
    rofi
    opencode
  ];
}
