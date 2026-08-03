# Правила agenix. Редактировать не нужно: список выводится из содержимого
# wg/, поэтому новый туннель покрывается правилом автоматически, как только
# его файл появился.
#
# Добавить туннель:
#   age -R ~/.ssh/id_ed25519.pub -o secrets/wg/<имя>.age <конфиг>.conf
#   sudo nixos-rebuild switch --flake /etc/nixos
#
# Отредактировать существующий:
#   agenix -e wg/<имя>.age
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
