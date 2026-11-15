{pkgs, ...}: {
  time.timeZone = "Europe/Belgrade";
  # >>> p6-deploy:passkeys >>>
  # The owner's pinned passkeys (docs/p6-spec.md P2): read by the core on legion and by the gateway's passkey-enrol on
  # homelab. A store file is root-owned and not writable, which is what the core demands.
  environment.etc."dispatcher/owner-passkeys.json".source = ../hosts/dispatcher-owner-passkeys.json;
  # <<< p6-deploy:passkeys <<<
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
