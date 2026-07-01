{...}: {
  imports = [
    ./modules
  ];

  home.username = "lux";
  home.homeDirectory = "/home/lux";

  home.stateVersion = "25.11";

  programs.home-manager.enable = true;
}
