{config, ...}: {
  xdg.configFile."nvim" = {
    source = config.lib.file.mkOutOfStoreSymlink "/etc/nixos/nvim";
    force = true;
  };
}
