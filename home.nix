{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  nvimGrammars = pkgs.symlinkJoin {
    name = "nvim-treesitter-parsers";
    paths = with pkgs.vimPlugins.nvim-treesitter.grammarPlugins; [
      c
      go
      javascript
      lua
      nix
      php
      rust
      zig
    ];
  };
in {
  # ─────────────────────────────── base ───────────────────────────────

  home.username = "lux";
  home.homeDirectory = "/home/lux";

  home.stateVersion = "25.11";

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };

  programs.home-manager.enable = true;
  programs.obs-studio = {
    enable = true;
    plugins = with pkgs.obs-studio-plugins; [
      obs-backgroundremoval
    ];
  };

  # ─────────────────────────────── shell ──────────────────────────────

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    syntaxHighlighting.enable = true;
    autocd = true;

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
      rebuild = "nh os switch";
      rebuild-test = "nh os test";
      update = "nh os switch --update";
      nx = "cd /etc/nixos";
    };

    initContent = lib.mkOrder 950 ''
      # NOTE: no extended_glob here -- it turns '#' into a glob repetition
      # operator, which breaks flake refs like /etc/nixos#nixos unless
      # every '#' is quoted.
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

  programs.starship = {
    enable = true;
    enableZshIntegration = true;

    settings = {
      add_newline = true;

      format = "$username$hostname$directory$nix_shell$cmd_duration$line_break$character";

      username = {
        style_user = "bold green";
        show_always = false;
        format = "[$user]($style)";
      };

      hostname = {
        ssh_only = true;
        style = "bold green";
        format = "[@$hostname]($style) ";
      };

      directory = {
        style = "bold cyan";
        truncation_length = 0;
        truncate_to_repo = false;
      };

      character = {
        success_symbol = "[❯](bold green)";
        error_symbol = "[❯](bold red)";
      };

      nix_shell = {
        symbol = " ";
        format = "via [$symbol$state]($style) ";
      };

      cmd_duration = {
        min_time = 2000;
        format = "took [$duration](bold yellow) ";
      };
    };
  };

  programs.atuin = {
    enable = true;
    enableZshIntegration = true;

    settings = {
      auto_sync = false;
      update_check = false;
      style = "compact";
    };
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    historyWidget.command = "";
  };

  programs.zoxide.enable = true;

  programs.tmux = {
    enable = true;
    baseIndex = 1;
    keyMode = "vi";
    mouse = true;
    escapeTime = 0;
    historyLimit = 2000;

    plugins = with pkgs.tmuxPlugins; [
      {
        plugin = tokyo-night-tmux;
        extraConfig = ''
          set -g @tokyo-night-tmux_theme night
          set -g @tokyo-night-tmux_show_hostname 1
          set -g @tokyo-night-tmux_show_path 1
        '';
      }
      {
        plugin = resurrect;
        extraConfig = ''
          set -g @resurrect-processes ':all:'
        '';
      }
      {
        plugin = continuum;
        extraConfig = ''
          set -g @continuum-restore 'on'
          set -g @continuum-save-interval '15'
        '';
      }
    ];

    extraConfig = ''
      # Neovim auto-negotiates the Kitty keyboard protocol with foot; without
      # this, tmux doesn't reliably translate that back into its own key
      # names, so root-table Alt binds (M-c etc.) stop matching once nvim has
      # touched the pane and the raw sequence falls through to the shell/nvim.
      set -g extended-keys always

      # mouse=true + keyMode vi means any scroll over a pane silently drops
      # you into copy-mode-vi, which rebinds the whole keytable (Ctrl+C,
      # M-c, etc. stop meaning what you expect) until you press q/Escape.
      # Flash a message on entry/exit so it's never a silent surprise.
      set-hook -g pane-mode-changed 'if -F "#{pane_in_mode}" "display-message \"-- COPY MODE (q/Escape to exit) --\"" "display-message \"-- copy mode exited --\""'

      unbind-key -a -T root

      # unbind-key -a -T root above wipes tmux's built-in mouse bindings too
      # (root table only -- copy-mode-vi's own MouseDrag1Pane/MouseDragEnd1Pane
      # selection binds are untouched). Re-add just the entry points so
      # click-drag still starts a selection.
      bind -n MouseDown1Pane select-pane -t = \; send-keys -M
      bind -n MouseDrag1Pane select-pane -t = \; copy-mode -M
      bind -n MouseDrag1Border resize-pane -M

      set -g pane-border-lines "double"

      set -g renumber-windows on

      bind -n M-r source-file ~/.config/tmux/tmux.conf \; display "Config reloaded!"
      bind -n M-s choose-tree -s

      bind -n M-1 select-window -t 1
      bind -n M-2 select-window -t 2
      bind -n M-3 select-window -t 3
      bind -n M-4 select-window -t 4
      bind -n M-5 select-window -t 5
      bind -n M-6 select-window -t 6
      bind -n M-7 select-window -t 7
      bind -n M-8 select-window -t 8
      bind -n M-9 select-window -t 9

      bind -n M-Left select-pane -L
      bind -n M-Right select-pane -R
      bind -n M-Up select-pane -U
      bind -n M-Down select-pane -D

      bind -n M-S-Left resize-pane -L 5
      bind -n M-S-Right resize-pane -R 5
      bind -n M-S-Up resize-pane -U 3
      bind -n M-S-Down resize-pane -D 3

      bind -n M-h split-window -v
      bind -n M-v split-window -h

      bind -n M-Enter new-window
      bind -n M-c kill-pane
      bind -n M-q kill-window
      bind -n M-d detach
      bind -n M-Q confirm-before -p "Kill entire session? (y/n)" kill-session

      bind -T copy-mode-vi v send -X begin-selection
      bind -T copy-mode-vi y send -X copy-pipe-and-cancel "wl-copy || xclip -in -selection clipboard"
      bind -n M-/ copy-mode \; command-prompt -p "(search down)" "send -X search-forward '%%%'"
      bind -n M-? copy-mode \; command-prompt -p "(search up)"   "send -X search-backward '%%%'"
    '';
  };

  # ────────────────────────────── desktop ─────────────────────────────

  xdg.configFile."niri" = {
    source = config.lib.file.mkOutOfStoreSymlink "/etc/nixos/dotfiles/niri";
    force = true;
  };

  programs.foot = {
    enable = true;
    settings = {
      main = {
        font = "Iosevka NF:size=15";
        pad = "4x4";
        shell = "zsh";
        include = "${config.home.homeDirectory}/.config/foot/themes/noctalia";
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

  home.activation.seedFootTheme = lib.hm.dag.entryAfter ["writeBoundary"] ''
        theme_file="${config.home.homeDirectory}/.config/foot/themes/noctalia"
        if [ ! -e "$theme_file" ]; then
          mkdir -p "$(dirname "$theme_file")"
          cat > "$theme_file" <<'THEME'
    [colors-dark]
    foreground=c0caf5
    background=1a1b26
    regular0=15161E
    regular1=f7768e
    regular2=9ece6a
    regular3=e0af68
    regular4=7aa2f7
    regular5=bb9af7
    regular6=7dcfff
    regular7=a9b1d6
    bright0=414868
    bright1=f7768e
    bright2=9ece6a
    bright3=e0af68
    bright4=7aa2f7
    bright5=bb9af7
    bright6=7dcfff
    bright7=c0caf5
    THEME
        fi
  '';

  programs.zathura = {
    enable = true;
    options = {
      selection-clipboard = "clipboard";
    };
  };

  programs.yazi = {
    enable = true;
    enableZshIntegration = true;
    shellWrapperName = "y";

    plugins = with pkgs.yaziPlugins; {
      full-border = {
        package = full-border;
        setup = true;
      };
      git = {
        package = git;
        setup = true;
      };
      inherit chmod smart-enter compress;
    };

    settings = {
      plugin.prepend_fetchers = [
        {
          url = "*";
          run = "git";
          group = "git";
        }
        {
          url = "*/";
          run = "git";
          group = "git";
        }
      ];

      opener = {
        edit = [
          {
            run = ''nvim "$@"'';
            block = true;
            desc = "Edit in nvim";
          }
        ];
        image = [
          {
            run = ''imv "$@"'';
            orphan = true;
            desc = "Open image in imv";
          }
        ];
        pdf = [
          {
            run = ''zathura "$@"'';
            orphan = true;
            desc = "Open PDF in zathura";
          }
        ];
        torrent = [
          {
            run = ''qbittorrent "$@"'';
            orphan = true;
            desc = "Open in qBittorrent";
          }
        ];
      };

      open.prepend_rules = [
        {
          mime = "image/*";
          use = "image";
        }
        {
          mime = "application/pdf";
          use = "pdf";
        }
        {
          mime = "application/x-bittorrent";
          use = "torrent";
        }
        {
          url = "*.torrent";
          use = "torrent";
        }
      ];
    };

    keymap = {
      mgr.prepend_keymap = [
        {
          on = "l";
          run = "plugin smart-enter";
          desc = "Enter the child directory, or open the file";
        }
        {
          on = "Z";
          run = "shell 'ya emit cd \"$(zoxide query -i)\"' --block --confirm";
          desc = "cd via zoxide";
        }
        {
          on = ["c" "m"];
          run = "plugin chmod";
          desc = "Chmod on selected files";
        }
        {
          on = ["c" "a"];
          run = "plugin compress";
          desc = "Compress selected files";
        }
      ];
    };

    extraPackages = with pkgs; [
      unrar
      p7zip
      unar
      ffmpegthumbnailer
      poppler-utils
      imagemagick
    ];
  };

  # ────────────────────────────── editor ──────────────────────────────

  xdg.configFile."nvim" = {
    source = config.lib.file.mkOutOfStoreSymlink "/etc/nixos/dotfiles/nvim";
    force = true;
  };

  xdg.dataFile."nvim/site/parser".source = "${nvimGrammars}/parser";

  # ──────────────────────────────── git ───────────────────────────────

  programs.git = {
    enable = true;
    settings = {
      user.name = "lux";
      user.email = "rakhmatullin.damir@tutamail.com";
      init.defaultBranch = "main";
      pull.rebase = true;
    };
  };

  # ───────────────────────────── packages ─────────────────────────────

  home.packages = lib.mkBefore (with pkgs;
    [
      vesktop
      wtype
      mpv
      qbittorrent
      chromium
      onlyoffice-desktopeditors
      protonup-qt
      imv
      spotify
      localsend
      exiftool

      ripgrep
      fd
      bat
      eza
      jq
      htop
      wget
      unzip
      wl-clipboard

      nodejs_22
      go
      gh

      zed-editor
      telegram-desktop
      btop
      (import inputs.creamlinux-installer {inherit pkgs;})
      tree
      gcc
      lua-language-server
      nil
      alejandra
      adwaita-icon-theme
      gnome-themes-extra
      nitch
      thunar

      rust-analyzer
      clang-tools
      gopls
      zls
      intelephense
      typescript-language-server
      vscode-langservers-extracted
      haskell-language-server
      serve-d
      templ
      c3-lsp
    ]
    ++ [
      inputs.zen-browser.packages."${pkgs.stdenv.hostPlatform.system}".default
      inputs.clin.packages.${pkgs.stdenv.hostPlatform.system}.default
    ]);
}
