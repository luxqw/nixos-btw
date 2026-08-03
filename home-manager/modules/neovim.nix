# Конфиг neovim остаётся сырым дотфайлом: симлинк мимо стора, чтобы
# править lua без пересборки системы.
#
# Парсеры treesitter раньше лежали в репозитории восемью .so-файлами,
# собранными руками под конкретный ABI. Теперь их даёт nixpkgs, а
# neovim находит их в ~/.local/share/nvim/site — этот путь входит в
# runtimepath по умолчанию и не мешает симлинку конфига выше.
{
  config,
  pkgs,
  ...
}: let
  # Именно grammarPlugins, а не withPlugins: последний в текущем nixpkgs
  # отдаёт плагин вообще без скомпилированных .so.
  grammars = pkgs.symlinkJoin {
    name = "nvim-treesitter-parsers";
    paths = with pkgs.vimPlugins.nvim-treesitter.grammarPlugins; [
      c
      go
      javascript
      lua
      nix
      php
      rust
      zig
    ];
  };
in {
  xdg.configFile."nvim" = {
    source = config.lib.file.mkOutOfStoreSymlink "/etc/nixos/dotfiles/nvim";
    force = true;
  };

  xdg.dataFile."nvim/site/parser".source = "${grammars}/parser";
}
