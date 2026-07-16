{...}: {
  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;

  zramSwap.enable = true;

  # logind's own HandlePowerKey suspends directly, bypassing noctalia (and
  # its lockOnSuspend=true) entirely -- niri binds the key to
  # noctalia's lock-and-suspend instead, so tell logind to stay out of it.
  services.logind.settings.Login.HandlePowerKey = "ignore";
}
