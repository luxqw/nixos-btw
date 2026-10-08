{pkgs, ...}: {
  time.timeZone = "Europe/Belgrade";
  i18n.defaultLocale = "en_US.UTF-8";

  zramSwap.enable = true;

  programs.nh = {
    enable = true;
    clean = {
      enable = true;
      extraArgs = "--keep 5 --keep-since 7d";
    };
  };

  nix.settings = {
    auto-optimise-store = true;
    experimental-features = ["nix-command" "flakes"];
    download-buffer-size = 268435456;
    trusted-users = ["root" "lux"];
  };

  nixpkgs.config.allowUnfree = true;

  programs.zsh.enable = true;

  users.users.lux = {
    isNormalUser = true;
    description = "Lux";
    shell = pkgs.zsh;
    extraGroups = ["media"];
  };

  users.groups.media.gid = 2000;
}
