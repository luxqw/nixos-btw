{
  pkgs,
  inputs,
  ...
}: {
  environment.systemPackages = with pkgs; [
    ntfs3g
    wireguard-tools
    xwayland-satellite
    inputs.torio.packages.${pkgs.system}.default
    inputs.tele.packages.${pkgs.system}.default
  ];
}
