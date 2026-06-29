{
  config,
  pkgs,
  inputs,
  ...
}: {
  home.username = "lux";
  home.homeDirectory = "/home/lux";

  home.stateVersion = "25.11";

  home.packages = with pkgs; [
    vesktop
    antigravity
    mpv
    qbittorrent
    protonup-qt
    telegram-desktop
    chromium
    onlyoffice-desktopeditors

    ripgrep
    fd
    bat
    eza
    jq
    htop
    wget
    unzip

    nodejs_22
    go
    gh
  ];

  programs.git = {
    enable = true;
    settings = {
      user.name = "lux";
      user.email = "rakhmatullin.damir@tutamail.com";
      init.defaultBranch = "main";
      pull.rebase = true;
    };
  };

  programs.bash = {
    enable = true;
    shellAliases = {
      ls = "eza";
      cat = "bat";
      edit = "nvim /etc/nixos/";
      rebuild = "sudo nixos-rebuild switch --flake /etc/nixos#nixos";
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

  programs.foot = {
    enable = true;
    settings = {
      main = {
        font = "Iosevka NF:size=14";
        pad = "4x4";
      };
      colors-dark = {
        foreground = "c0caf5";
        background = "1a1b26";
        alpha = "0.98";
        regular0 = "15161E";
        regular1 = "f7768e";
        regular2 = "9ece6a";
        regular3 = "e0af68";
        regular4 = "7aa2f7";
        regular5 = "bb9af7";
        regular6 = "7dcfff";
        regular7 = "a9b1d6";
        bright0 = "414868";
        bright1 = "f7768e";
        bright2 = "9ece6a";
        bright3 = "e0af68";
        bright4 = "7aa2f7";
        bright5 = "bb9af7";
        bright6 = "7dcfff";
        bright7 = "c0caf5";
        dim0 = "ff9e64";
        dim1 = "db4b4b";
      };
    };
  };
  xdg.configFile."foot/foot.ini".force = true;

  xdg.configFile."niri/config.kdl" = {
    source = config.lib.file.mkOutOfStoreSymlink "/etc/nixos/niri/config.kdl";
    force = true;
  };

  programs.home-manager.enable = true;
}
