# Proxies — clients that move traffic past network restrictions.
#
# v2raya and throne solve the same problem and both want the default
# route. Enabling throne's tun mode will fight v2raya; only v2raya is
# actually in use right now.
{pkgs, ...}: {
  services.v2raya = {
    enable = true;
    cliPackage = pkgs.xray;
  };

  programs.throne = {
    enable = true;
    tunMode.enable = true;
  };
}
