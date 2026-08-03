# Tunnels — named WireGuard interfaces into private networks.
#
# The list of tunnels is written down nowhere: it is derived from the
# contents of secrets/wg/, where a filename serves as the interface name
# and the unit name. Adding a tunnel means dropping a new .age in there
# and rebuilding. See docs/adr/0001.
{
  config,
  lib,
  ...
}: let
  secretsDir = ../../../secrets/wg;

  names =
    map (lib.removeSuffix ".age")
    (builtins.attrNames
      (lib.filterAttrs
        (name: type: type == "regular" && lib.hasSuffix ".age" name)
        (builtins.readDir secretsDir)));

  units = map (name: "wg-quick-${name}.service") names;
in {
  age.secrets = lib.genAttrs names (name: {
    file = secretsDir + "/${name}.age";
  });

  networking.wg-quick.interfaces = lib.genAttrs names (name: {
    configFile = config.age.secrets.${name}.path;
  });

  # Tunnels start at boot, but stopping and starting them by hand needs no
  # password. The grant is narrow: only these units, only these verbs.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      var units = ${builtins.toJSON units};
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          units.indexOf(action.lookup("unit")) >= 0 &&
          ["start", "stop", "restart"].indexOf(action.lookup("verb")) >= 0 &&
          subject.user == "lux") {
        return polkit.Result.YES;
      }
    });
  '';
}
