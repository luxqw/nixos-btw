{...}: {
  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;

  zramSwap.enable = true;
}
