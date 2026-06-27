{
  config,
  pkgs,
  ...
}: {
  home.username = "lux";
  home.homeDirectory = "/home/lux";
  home.stateVersion = "25.11";

  home.packages = with pkgs; [
    # Hypr ecosystem
    hyprpaper
    hyprlock
    hypridle
    hyprshot
    hyprsunset
    hyprpicker

    # Notifications
    mako
    libnotify

    # Apps
    discord
    zed-editor
    antigravity
    mpv
    qbittorrent
    chromium
    onlyoffice-desktopeditors

    # CLI
    ripgrep
    fd
    bat
    eza
    jq
    htop
    wget
    unzip

    # Dev
    nodejs_22
    go
    gh
  ];

  xdg.configFile."hypr/hyprland.lua".source = ./hypr/hyprland.lua;
  xdg.configFile."hypr/hl.meta.lua".source = ./hypr/hl.meta.lua;
  xdg.configFile."hypr/hyprpaper.conf".source = ./hypr/hyprpaper.conf;
  xdg.configFile."hypr/hypridle.conf".source = ./hypr/hypridle.conf;
  xdg.configFile."hypr/hyprlock.conf".source = ./hypr/hyprlock.conf;

  xdg.configFile."mako/config".text = ''
    background-color=#1a1b26
    text-color=#c0caf5
    border-color=#7aa2f7
    border-radius=10
    font=Iosevka NF 12
    default-timeout=5000
    max-visible=5
    layer=overlay
    margin=10
    padding=10,15
    anchor=top-right
  '';

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
