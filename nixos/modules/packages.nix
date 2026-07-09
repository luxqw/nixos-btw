{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    ntfs3g
    wireguard-tools
    xwayland-satellite
  ];
}
