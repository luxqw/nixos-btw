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
    vesktop
    zed-editor
    antigravity
    mpv
    qbittorrent
    protonup-qt
    telegram-desktop
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
      vpn-up = "sudo wg-quick up wg0";
      vpn-down = "sudo wg-quick down wg0";
    };
  };

  programs.foot = {
    enable = true;
    settings = {
      main = {
        font = "Iosevka NF:size=14";
        pad = "4x4";
      };
      colors-dark = {
        foreground = "c0caf5";
        background = "1a1b26";
        alpha = "0.98";
        regular0 = "15161E";
        regular1 = "f7768e";
        regular2 = "9ece6a";
        regular3 = "e0af68";
        regular4 = "7aa2f7";
        regular5 = "bb9af7";
        regular6 = "7dcfff";
        regular7 = "a9b1d6";
        bright0 = "414868";
        bright1 = "f7768e";
        bright2 = "9ece6a";
        bright3 = "e0af68";
        bright4 = "7aa2f7";
        bright5 = "bb9af7";
        bright6 = "7dcfff";
        bright7 = "c0caf5";
        dim0 = "ff9e64";
        dim1 = "db4b4b";
      };
    };
  };

  programs.home-manager.enable = true;
}
