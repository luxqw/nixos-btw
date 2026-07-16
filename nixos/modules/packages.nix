{
  pkgs,
  inputs,
  ...
}: {
  environment.systemPackages = with pkgs; [
    ntfs3g
    exiftool
    polkit_gnome
    wireguard-tools
    xwayland-satellite
    localsend
  ];
}
