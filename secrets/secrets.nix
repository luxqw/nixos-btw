let
  lux = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE/1YvuBqo5bySoS2EczLFGNzx8ONDJqeibq6O8n4KiG lux@nixos";
  homelab = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIItAd+Zf3tM9hJbLr+QnBLmcJWB0JFzw9Al8zWLvzepq root@homelab";

  rules = dir: publicKeys:
    map (name: {
      name = "${dir}/${name}";
      value = {inherit publicKeys;};
    })
    (builtins.filter
      (name: builtins.match ".*\\.age" name != null)
      (builtins.attrNames (builtins.readDir (./. + "/${dir}"))));
in
  builtins.listToAttrs (rules "wg" [lux] ++ rules "legion" [lux] ++ rules "homelab" [lux homelab])
