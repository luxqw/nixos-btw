{...}: {
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    # Ctrl-R is owned by Atuin (see atuin.nix); keep fzf's Ctrl-T/Alt-C.
    historyWidget.command = "";
  };
}
