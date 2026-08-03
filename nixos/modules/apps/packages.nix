# Only what services, hardware or login cannot work without belongs here.
# Everything user-facing lives in home-manager/modules/packages.nix.
{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    ntfs3g # mounting the games partition
    polkit_gnome # authorisation agent for the graphical session
    wireguard-tools # wg show, for inspecting tunnels
    xwayland-satellite # X11 applications under niri
  ];
}
