# agenix rules. No editing needed: the list is derived from the contents of
# wg/, so a new tunnel is covered automatically as soon as its file exists.
#
# Add a tunnel (paths are absolute, so the command works from anywhere):
#   age -R ~/.ssh/id_ed25519.pub -o /etc/nixos/secrets/wg/<name>.age <config>.conf
#   sudo nixos-rebuild switch --flake /etc/nixos
#
# Edit an existing one (from /etc/nixos/secrets):
#   agenix -e wg/<name>.age
#
# Before the first rebuild age is not yet installed — use `nix-shell -p age`.
#
# The `tunnel` command wraps all of this; see README.md.
let
  lux = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE/1YvuBqo5bySoS2EczLFGNzx8ONDJqeibq6O8n4KiG lux@nixos";

  tunnels =
    builtins.filter
    (name: builtins.match ".*\\.age" name != null)
    (builtins.attrNames (builtins.readDir ./wg));
in
  builtins.listToAttrs (map (name: {
      name = "wg/${name}";
      value.publicKeys = [lux];
    })
    tunnels)
