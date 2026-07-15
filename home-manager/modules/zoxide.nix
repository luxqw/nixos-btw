{...}: {
  # Installs the zoxide binary only -- no shell integration (no `z`/`zi`
  # commands). Used by yazi's `Z` keybind (see yazi.nix) to jump to frecent
  # directories while browsing; Atuin's Ctrl-R covers shell history instead.
  programs.zoxide.enable = true;
}
