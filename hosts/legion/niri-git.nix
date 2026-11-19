# niri from git main: the GlobalShortcuts portal (niri PR #4744, merged 2026-11-07, not in 26.04)
# lets apps such as the ChatGPT desktop app register real global hotkeys. Drop this file once a
# niri release > 26.04 is in nixpkgs.
{pkgs, ...}: let
  rev = "689c1e914a5af782a476e433b79c15554bf5a312"; # main, 2026-11-15
  src = pkgs.fetchFromGitHub {
    owner = "niri-wm";
    repo = "niri";
    inherit rev;
    hash = "sha256-13a2sg+XKWFg+c2jCNTnso+Qbuihy6YHK2awm54VLrc=";
  };
in {
  programs.niri.package = pkgs.niri.overrideAttrs (_: {
    version = "26.04-unstable-2026-11-15";
    doInstallCheck = false; # versionCheckHook expects the release version string
    inherit src;
    cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
      inherit src;
      hash = "sha256-rLVTigIUf8rxn25bVdjVyOqPPjBq8KpKINoXQ/gFYxI=";
    };
  });

  # xdg-desktop-portal-gnome's GlobalShortcuts needs org.gnome.Settings.GlobalShortcutsProvider,
  # which gnome-control-center provides (niri wiki, Important Software).
  environment.systemPackages = [pkgs.gnome-control-center];
}
