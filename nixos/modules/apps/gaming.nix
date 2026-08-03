{...}: {
  programs.gamemode.enable = true;
  programs.gamescope.enable = true;

  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
  };
}
