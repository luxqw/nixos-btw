{pkgs, ...}: {
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    syntaxHighlighting.enable = true;
    autocd = true;

    # zsh picks vi keybindings on its own whenever $EDITOR or $VISUAL
    # contains the substring "vi" -- "nvim" does, so the prompt silently
    # came up in vi mode. Pin the keymap instead of renaming the editor.
    defaultKeymap = "emacs";

    autosuggestion = {
      enable = true;
      strategy = ["history" "completion"];
    };

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
    '';
  };
}
