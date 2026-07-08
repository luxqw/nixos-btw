{pkgs, ...}: {
  environment.systemPackages = [pkgs.neovim-unwrapped];

  # Declarative, rebuild-safe symlink: ~/.config/nvim -> the repo's nvim/
  # config directory. L+ (re)creates the link on every activation.
  systemd.tmpfiles.rules = [
    "L+ /home/lux/.config/nvim - - - - /etc/nixos/nvim"
  ];
}
