# Линкуется весь каталог, а не только config.kdl: он тянет
# include "/home/lux/.config/niri/noctalia.kdl", так что рядом обязан
# лежать и второй файл. Раньше это держалось на ручном симлинке,
# созданном мимо home-manager.
{config, ...}: {
  xdg.configFile."niri" = {
    source = config.lib.file.mkOutOfStoreSymlink "/etc/nixos/dotfiles/niri";
    force = true;
  };
}
