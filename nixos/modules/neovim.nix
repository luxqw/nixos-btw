{pkgs, ...}: {
  environment.systemPackages = [pkgs.neovim-unwrapped];
}
