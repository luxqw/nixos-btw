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
