{pkgs, ...}: {
  users.users.lux.packages = with pkgs; [
    tree
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

    # nvim LSP servers (nvim itself: nixos/modules/neovim.nix)
    rust-analyzer
    clang-tools # clangd
    gopls
    zls
    intelephense
    typescript-language-server
    vscode-langservers-extracted # vscode-{css,json}-language-server
    haskell-language-server
    serve-d
    templ
    c3-lsp
  ];
}
