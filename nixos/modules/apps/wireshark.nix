# Wireshark needs a module rather than a line in packages.nix: capturing
# as a non-root user takes a dumpcap wrapper holding cap_net_raw and
# cap_net_admin, executable only by the `wireshark` group -- both the
# wrapper and the group come from the module, and user.nix puts lux in it.
#
# The default package is wireshark-cli, which ships no GUI at all; the
# full package is named plainly `wireshark` and carries the Qt interface
# alongside the same tshark and dumpcap.
{pkgs, ...}: {
  programs.wireshark = {
    enable = true;
    package = pkgs.wireshark;
  };
}
