{...}: {
  programs.zathura = {
    enable = true;
    options = {
      # Zathura copies selections to PRIMARY by default, so Ctrl+C/Ctrl+V
      # don't see it -- only middle-click paste works. Send it to the
      # system clipboard instead.
      selection-clipboard = "clipboard";
    };
  };
}
