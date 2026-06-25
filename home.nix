{
  config,
  pkgs,
  inputs,
  ...
}: {
  home.username = "lux";
  home.homeDirectory = "/home/lux";

  home.stateVersion = "25.11";

  home.packages = [
    pkgs.claude-code

    pkgs.discord
    pkgs.zed-editor
    pkgs.antigravity
    pkgs.mpv
    pkgs.qbittorrent

    pkgs.ripgrep
    pkgs.fd
    pkgs.bat
    pkgs.eza
    pkgs.jq
    pkgs.htop
    pkgs.wget
    pkgs.unzip

    pkgs.nodejs_22
    pkgs.go
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
