# Туннели — именованные WireGuard-интерфейсы в частные сети.
#
# Список туннелей нигде не записан: он выводится из содержимого
# secrets/wg/, где имя файла служит именем интерфейса и именем юнита.
# Чтобы добавить туннель, достаточно положить туда новый .age и
# пересобрать систему. См. docs/adr/0001.
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

  # Туннели поднимаются при буте, но гасить и поднимать их можно вручную
  # без пароля. Разрешение узкое: только эти юниты, только эти глаголы.
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
