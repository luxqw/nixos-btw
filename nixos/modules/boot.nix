{pkgs, ...}: {
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.kernelModules = ["xt_TPROXY" "xt_socket" "xt_mark" "iptable_mangle" "nf_tproxy_ipv4"];
}
