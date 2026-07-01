{pkgs, ...}: {
  programs.gamemode.enable = true;
  programs.steam = {
    enable = true;
    package = pkgs.millennium-steam;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
  };
}
