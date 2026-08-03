{pkgs, ...}: {
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    autocd = true;

    plugins = [
      {
        name = "zsh-completions";
        src = pkgs.zsh-completions;
      }
    ];

    history = {
      size = 10000;
      save = 10000;
      ignoreDups = true;
      ignoreSpace = true;
      share = true;
      extended = true;
    };

    autosuggestion.strategy = ["history" "completion"];

    completionInit = ''
      autoload -Uz compinit
      # NixOS fpath spans multiple profile generations (thousands of
      # completion files); compinit's full security audit (compaudit)
      # rescanning all of them on every start is most of zsh's startup
      # time. Only pay for the full audit once a day, otherwise fast-load
      # the cached dump.
      zcompdump="''${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump"
      mkdir -p "''${zcompdump:h}"
      if [[ -f "$zcompdump" && -n "$zcompdump"(#qN.mh+24) ]]; then
        compinit -C -d "$zcompdump"
      else
        compinit -d "$zcompdump"
      fi
      zstyle ':completion:*' menu select
      zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*'
      zstyle ':completion:*' list-colors "''${(s.:.)LS_COLORS}"
      zstyle ':completion:*' group-name '""'
      zstyle ':completion:*:descriptions' format '%F{cyan}-- %d --%f'
      zstyle ':completion:*:warnings' format '%F{red}-- no matches found --%f'
    '';

    shellAliases = {
      ls = "eza";
      cat = "bat";
      edit = "nvim /etc/nixos/";
      edit-hm = "nvim /etc/nixos/home-manager/modules/packages.nix";
      edit-sys = "nvim /etc/nixos/nixos/modules/packages.nix";
      rebuild = "sudo nixos-rebuild switch --flake /etc/nixos#nixos";
      update = "cd /etc/nixos/ && sudo nix flake update && sudo nixos-rebuild switch --flake /etc/nixos#nixos";
      nx = "cd /etc/nixos";
    };

    initContent = ''
      # NOTE: no extended_glob here -- it turns '#' into a glob repetition
      # operator, which breaks flake refs like /etc/nixos#nixos (used by
      # the rebuild/update aliases below) unless every '#' is quoted.
      setopt no_case_glob
      setopt complete_in_word
      setopt auto_pushd
      setopt pushd_ignore_dups
      unsetopt beep

      # Ctrl+S/Ctrl+Q default to XOFF/XON flow control, which freezes the
      # terminal on a stray Ctrl+S until Ctrl+Q is pressed. Disable it.
      stty -ixon

      _vpn_dir="/etc/nixos/wireguard"

      _vpn_is_up() {
        sudo wg show wg0 &>/dev/null
      }

      _vpn_active_name() {
        local active
        active=$(sudo readlink "$_vpn_dir/wg0.conf" 2>/dev/null)
        basename "$active" .conf 2>/dev/null
      }

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
        echo "Added: $name  (run: vpn $name)"
      }

      vpn-list() {
        local active up_marker
        active=$(_vpn_active_name)
        _vpn_is_up && up_marker=" [up]" || up_marker=" [down]"
        local found=0
        while IFS= read -r f; do
          [[ "$f" == *wg0.conf ]] && continue
          found=1
          local n
          n=$(basename "$f" .conf)
          if [[ "$n" == "$active" ]]; then
            echo "* $n (active)$up_marker"
          else
            echo "  $n"
          fi
        done < <(sudo find "$_vpn_dir" -maxdepth 1 -name "*.conf" 2>/dev/null)
        [[ $found -eq 0 ]] && echo "  (no configs yet)"
      }

      vpn-up() {
        local name="$1"
        if [[ -n "$name" ]]; then
          local conf="$_vpn_dir/$name.conf"
          if ! sudo test -f "$conf"; then
            echo "Config '$name' not found. Available:"
            vpn-list
            return 1
          fi
          if _vpn_is_up; then
            sudo wg-quick down wg0
          fi
          sudo ln -sf "$conf" "$_vpn_dir/wg0.conf" || return 1
        fi

        if _vpn_is_up; then
          echo "VPN already up ($(_vpn_active_name))"
          return 0
        fi

        local active
        active=$(_vpn_active_name)
        if [[ -z "$active" ]]; then
          echo "No active VPN config. Usage: vpn-up <name>"
          vpn-list
          return 1
        fi
        sudo wg-quick up wg0 && echo "VPN up: $active"
      }

      vpn-down() {
        if ! _vpn_is_up; then
          echo "VPN already down"
          return 0
        fi
        sudo wg-quick down wg0 && echo "VPN down"
      }

      vpn() {
        local name="$1"
        if [[ -n "$name" ]]; then
          vpn-up "$name"
          return $?
        fi
        if _vpn_is_up; then
          vpn-down
        else
          vpn-up
        fi
      }
    '';
  };
}
