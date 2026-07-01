{pkgs, ...}: {
  home.packages = with pkgs; [
    vesktop
    antigravity
    mpv
    qbittorrent
    chromium
    onlyoffice-desktopeditors
    protonup-qt

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
