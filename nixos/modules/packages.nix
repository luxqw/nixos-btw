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
    showmethekey
    btop
    (import inputs.creamlinux-installer {inherit pkgs;})
    inputs.clin.packages.${system}.default
    inputs.tele.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
