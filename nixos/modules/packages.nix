{
  pkgs,
  inputs,
  ...
}: {
  environment.systemPackages = with pkgs; [
    ntfs3g
    exiftool
    wireguard-tools
    xwayland-satellite
    inputs.tele.packages.${pkgs.system}.default
    inputs.torio.packages.${pkgs.system}.default
  ];
}
