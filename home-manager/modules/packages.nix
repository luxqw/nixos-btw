{pkgs, ...}: {
  home.packages = with pkgs; [
    vesktop
    mpv
    qbittorrent
    chromium
    onlyoffice-desktopeditors
    protonup-qt
    obs-studio
    imv
    zathura

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
  ];
}
