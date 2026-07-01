{...}: {
  programs.bash = {
    enable = true;
    shellAliases = {
      ls = "eza";
      cat = "bat";
      edit = "nvim /etc/nixos/";
      rebuild = "sudo nixos-rebuild switch --flake /etc/nixos#nixos";
      update = "cd /etc/nixos/ && sudo nix flake update && sudo nixos-rebuild switch --flake /etc/nixos#nixos";
      nx = "cd /etc/nixos";
      vpn-up = "sudo wg-quick up wg0";
      vpn-down = "sudo wg-quick down wg0";
    };
    initExtra = ''
      _vpn_dir="/etc/nixos/wireguard"

      vpn-set() {
        local name="$1"
        if [[ -z "$name" ]]; then
          echo "Usage: vpn-set <name>"
          vpn-list
          return 1
        fi
        local conf="$_vpn_dir/$name.conf"
        if ! sudo test -f "$conf"; then
          echo "Config '$name' not found. Available:"
          vpn-list
          return 1
        fi
        sudo ln -sf "$conf" "$_vpn_dir/wg0.conf" || return 1
        echo "Active VPN: $name"
      }

      vpn-add() {
        local file="$1"
        if [[ -z "$file" || ! -f "$file" ]]; then
          echo "Usage: vpn-add <path/to/config.conf>"
          return 1
        fi
        local name
        name=$(basename "$file" .conf)
        sudo mkdir -p "$_vpn_dir"
        sudo cp "$file" "$_vpn_dir/$name.conf" || { echo "Failed to copy config"; return 1; }
        sudo chmod 600 "$_vpn_dir/$name.conf"
        echo "Added: $name  (run: vpn-set $name)"
      }

      vpn-list() {
        local active
        active=$(sudo readlink "$_vpn_dir/wg0.conf" 2>/dev/null)
        active=$(basename "$active" .conf 2>/dev/null)
        local found=0
        while IFS= read -r f; do
          [[ "$f" == *wg0.conf ]] && continue
          found=1
          local n
          n=$(basename "$f" .conf)
          [[ "$n" == "$active" ]] && echo "* $n (active)" || echo "  $n"
        done < <(sudo find "$_vpn_dir" -maxdepth 1 -name "*.conf" 2>/dev/null)
        [[ $found -eq 0 ]] && echo "  (no configs yet)"
      }
    '';
  };
}
