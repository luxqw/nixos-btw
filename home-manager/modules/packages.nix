{
  pkgs,
  inputs,
  ...
}: {
  home.packages = with pkgs;
    [
      vesktop
      wtype
      mpv
      qbittorrent
      chromium
      onlyoffice-desktopeditors
      protonup-qt
      obs-studio
      imv

      ripgrep
      fd
      bat
      eza
      jq
      htop
      wget
      unzip
      wl-clipboard

      nodejs_22
      go
      gh

      zed-editor
      telegram-desktop
      showmethekey
      btop
      (import inputs.creamlinux-installer {inherit pkgs;})
      tree
      gcc
      lua-language-server
      nil
      alejandra
      adwaita-icon-theme
      gnome-themes-extra
      nitch
      thunar
      opencode

      rust-analyzer
      clang-tools # clangd
      gopls
      zls
      intelephense
      typescript-language-server
      vscode-langservers-extracted
      haskell-language-server
      serve-d
      templ
      c3-lsp
    ]
    ++ [
      inputs.zen-browser.packages."${pkgs.stdenv.hostPlatform.system}".default
      inputs.clin.packages.${pkgs.stdenv.hostPlatform.system}.default
      inputs.tele.packages.${pkgs.system}.default
      inputs.torio.packages.${pkgs.system}.default
    ];
}
