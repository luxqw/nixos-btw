# A wrapper around agenix/age for tunnels.
#
# It exists because the bare commands require holding three unrelated
# facts at once: run from /etc/nixos/secrets, spell the name wg/<name>.age,
# and reach for age rather than agenix when the secret does not exist yet.
# All three are baked in here.
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
      tunnel — manage wireguard tunnels

        tunnel list                 list tunnels and their state
        tunnel up <name>            bring a tunnel up
        tunnel down <name>          take a tunnel down
        tunnel restart <name>       restart a tunnel
        tunnel add <name> <config>  encrypt a new config
        tunnel edit <name>          open an existing one in $EDITOR
        tunnel show <name>          print the decrypted config
        tunnel rm <name>            remove a tunnel

      up, down and restart need no password — see the polkit rule in
      tunnels.nix. Tunnels also start on their own at boot.

      add, edit and rm need a rebuild afterwards:
        sudo nixos-rebuild switch --flake /etc/nixos
      USAGE
      }

      # Guards the verbs that take a name, so a typo turns into a message
      # rather than systemd complaining about a unit that never existed.
      require_tunnel() {
        [ -n "''${1-}" ] || { echo "usage: tunnel $2 <name>" >&2; exit 1; }
        [ -e "$dir/wg/$1.age" ] || { echo "no such tunnel: $1" >&2; exit 1; }
      }

      case "''${1-}" in
        list)
          for f in "$dir"/wg/*.age; do
            [ -e "$f" ] || continue
            n=$(basename "$f" .age)
            printf '%-16s %s\n' "$n" "$(systemctl is-active "wg-quick-$n" 2>&1)"
          done
          ;;

        up|down|restart)
          verb=$1
          require_tunnel "''${2-}" "$verb"
          case "$verb" in
            up) systemctl start "wg-quick-$2" ;;
            down) systemctl stop "wg-quick-$2" ;;
            restart) systemctl restart "wg-quick-$2" ;;
          esac
          printf '%-16s %s\n' "$2" "$(systemctl is-active "wg-quick-$2" 2>&1)"
          ;;

        add)
          [ $# -eq 3 ] || { echo "usage: tunnel add <name> <config>" >&2; exit 1; }
          name=$2
          [ ''${#name} -le 15 ] || { echo "name longer than 15 characters — not a valid interface name" >&2; exit 1; }
          [ ! -e "$dir/wg/$name.age" ] || { echo "tunnel $name already exists — use tunnel edit" >&2; exit 1; }
          [ -f "$3" ] || { echo "no such file: $3" >&2; exit 1; }
          age -R "$key.pub" -o "$dir/wg/$name.age" "$3"
          echo "created $dir/wg/$name.age"
          echo "next: sudo nixos-rebuild switch --flake /etc/nixos"
          ;;

        edit)
          [ $# -eq 2 ] || { echo "usage: tunnel edit <name>" >&2; exit 1; }
          [ -e "$dir/wg/$2.age" ] || { echo "no such tunnel: $2" >&2; exit 1; }
          (cd "$dir" && RULES=./secrets.nix agenix -e "wg/$2.age" -i "$key")
          echo "next: sudo nixos-rebuild switch --flake /etc/nixos && systemctl restart wg-quick-$2"
          ;;

        show)
          [ $# -eq 2 ] || { echo "usage: tunnel show <name>" >&2; exit 1; }
          [ -e "$dir/wg/$2.age" ] || { echo "no such tunnel: $2" >&2; exit 1; }
          (cd "$dir" && RULES=./secrets.nix agenix -d "wg/$2.age" -i "$key")
          ;;

        rm)
          [ $# -eq 2 ] || { echo "usage: tunnel rm <name>" >&2; exit 1; }
          [ -e "$dir/wg/$2.age" ] || { echo "no such tunnel: $2" >&2; exit 1; }
          rm "$dir/wg/$2.age"
          echo "removed $2; next: sudo nixos-rebuild switch --flake /etc/nixos"
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
