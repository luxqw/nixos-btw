{
  config,
  pkgs,
  inputs,
  ...
}: {
  home.username = "lux";
  home.homeDirectory = "/home/lux";

  home.stateVersion = "25.11";

  home.packages = with pkgs; [
    discord
    zed-editor
    antigravity
    mpv
    qbittorrent
    chromium
    onlyoffice-desktopeditors

    ripgrep
    fd
    bat
    eza
    jq
    htop
    wget
    unzip

    nodejs_22
    go
    gh
  ];

  programs.git = {
    enable = true;
    settings = {
      user.name = "lux";
      user.email = "rakhmatullin.damir@tutamail.com";
      init.defaultBranch = "main";
      pull.rebase = true;
    };
  };

  programs.bash = {
    enable = true;
    shellAliases = {
      ls = "eza";
      cat = "bat";
      edit = "nvim /etc/nixos/";
      rebuild = "sudo nixos-rebuild switch --flake /etc/nixos#nixos";
      rebuild-hypr = "sudo nixos-rebuild switch --flake /etc/nixos/hyprland#nixos-hypr";
    };
  };

  gtk = {
    enable = true;
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
  };

  programs.home-manager.enable = true;
}
