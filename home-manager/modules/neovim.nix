# The neovim config stays a raw dotfile: a symlink past the store, so lua
# can be edited without rebuilding the system.
#
# Treesitter parsers used to sit in the repository as eight .so files built
# by hand against one specific ABI. They come from nixpkgs now, and neovim
# finds them in ~/.local/share/nvim/site — a path that is on the runtimepath
# by default and does not collide with the config symlink above.
{
  config,
  pkgs,
  ...
}: let
  # grammarPlugins rather than withPlugins: the latter yields a plugin with
  # no compiled .so at all in the current nixpkgs.
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
