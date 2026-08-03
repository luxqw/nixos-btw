# A deliberate exception to "only system things in the system": root needs
# an editor to fix configs by hand when home-manager is unavailable. The
# user's neovim and its config live in home-manager.
{pkgs, ...}: {
  environment.systemPackages = [pkgs.neovim-unwrapped];
}
