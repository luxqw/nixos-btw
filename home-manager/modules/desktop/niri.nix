{config, ...}: {
  xdg.configFile."niri/config.kdl" = {
    source = config.lib.file.mkOutOfStoreSymlink "/etc/nixos/dotfiles/niri/config.kdl";
    force = true;
  };
}
