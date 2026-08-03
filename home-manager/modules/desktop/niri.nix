# The whole directory is linked, not just config.kdl: it pulls in
# include "/home/lux/.config/niri/noctalia.kdl", so the second file has to
# sit beside it. This used to rest on a hand-made symlink created outside
# home-manager.
{config, ...}: {
  xdg.configFile."niri" = {
    source = config.lib.file.mkOutOfStoreSymlink "/etc/nixos/dotfiles/niri";
    force = true;
  };
}
