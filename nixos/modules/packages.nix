{
  pkgs,
  inputs,
  ...
}: {
  environment.systemPackages = with pkgs; [
    inputs.zen-browser.packages."${pkgs.stdenv.hostPlatform.system}".default
    ntfs3g
    wireguard-tools
    xwayland-satellite
    zed-editor
    telegram-desktop
  ];
}
