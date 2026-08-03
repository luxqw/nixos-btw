{pkgs, ...}: {
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
  nix.settings = {
    auto-optimise-store = true;
    experimental-features = ["nix-command" "flakes"];
    download-buffer-size = 268435456;
    trusted-users = ["root" "lux"];
  };

  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [nh nix-output-monitor];
  environment.sessionVariables.NH_FLAKE = "/etc/nixos";
}
