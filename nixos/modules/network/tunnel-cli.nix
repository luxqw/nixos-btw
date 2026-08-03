# Обёртка над agenix/age для туннелей.
#
# Существует потому, что голые команды требуют помнить три вещи разом:
# запускаться из /etc/nixos/secrets, писать имя как wg/<имя>.age, и знать,
# что новый секрет создаётся age'ом, а не agenix'ем. Здесь всё это зашито.
{
  pkgs,
  inputs,
  ...
}: let
  agenix = inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.default;

  tunnel = pkgs.writeShellApplication {
    name = "tunnel";
    runtimeInputs = [pkgs.age agenix pkgs.systemd];
    text = ''
      set -euo pipefail

      dir=/etc/nixos/secrets
      key="$HOME/.ssh/id_ed25519"

      usage() {
        cat <<'USAGE'
      tunnel — управление туннелями

        tunnel list                 список туннелей и их состояние
        tunnel add <имя> <конфиг>   зашифровать новый конфиг
        tunnel edit <имя>           открыть существующий в $EDITOR
        tunnel show <имя>           вывести расшифрованный в stdout
        tunnel rm <имя>             удалить туннель

      После add, edit и rm нужна пересборка:
        sudo nixos-rebuild switch --flake /etc/nixos
      USAGE
      }

      case "''${1-}" in
        list)
          for f in "$dir"/wg/*.age; do
            [ -e "$f" ] || continue
            n=$(basename "$f" .age)
            printf '%-16s %s\n' "$n" "$(systemctl is-active "wg-quick-$n" 2>&1)"
          done
          ;;

        add)
          [ $# -eq 3 ] || { echo "нужно: tunnel add <имя> <конфиг>" >&2; exit 1; }
          name=$2
          [ ''${#name} -le 15 ] || { echo "имя длиннее 15 символов — интерфейс так назвать нельзя" >&2; exit 1; }
          [ ! -e "$dir/wg/$name.age" ] || { echo "туннель $name уже есть — правь через tunnel edit" >&2; exit 1; }
          [ -f "$3" ] || { echo "нет файла: $3" >&2; exit 1; }
          age -R "$key.pub" -o "$dir/wg/$name.age" "$3"
          echo "создан $dir/wg/$name.age"
          echo "дальше: sudo nixos-rebuild switch --flake /etc/nixos"
          ;;

        edit)
          [ $# -eq 2 ] || { echo "нужно: tunnel edit <имя>" >&2; exit 1; }
          [ -e "$dir/wg/$2.age" ] || { echo "нет такого туннеля: $2" >&2; exit 1; }
          (cd "$dir" && RULES=./secrets.nix agenix -e "wg/$2.age" -i "$key")
          echo "дальше: sudo nixos-rebuild switch --flake /etc/nixos && systemctl restart wg-quick-$2"
          ;;

        show)
          [ $# -eq 2 ] || { echo "нужно: tunnel show <имя>" >&2; exit 1; }
          [ -e "$dir/wg/$2.age" ] || { echo "нет такого туннеля: $2" >&2; exit 1; }
          (cd "$dir" && RULES=./secrets.nix agenix -d "wg/$2.age" -i "$key")
          ;;

        rm)
          [ $# -eq 2 ] || { echo "нужно: tunnel rm <имя>" >&2; exit 1; }
          [ -e "$dir/wg/$2.age" ] || { echo "нет такого туннеля: $2" >&2; exit 1; }
          rm "$dir/wg/$2.age"
          echo "удалён $2; дальше: sudo nixos-rebuild switch --flake /etc/nixos"
          ;;

        *)
          usage
          [ -z "''${1-}" ] && exit 0 || exit 1
          ;;
      esac
    '';
  };
in {
  environment.systemPackages = [tunnel];
}
