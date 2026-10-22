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
      bash
      go
      json
      lua
      markdown
      markdown_inline
      nix
      yaml
    ];
  };

  goimports = pkgs.runCommandLocal "goimports-${pkgs.gotools.version}" {} ''
    install -Dm755 ${pkgs.gotools}/bin/.goimports-wrapped $out/bin/goimports
  '';

  tmux-sessionizer = pkgs.writeShellApplication {
    name = "tmux-sessionizer";
    runtimeInputs = with pkgs; [tmux fzf findutils coreutils];
    text = ''
      dir=$(find "$HOME/Documents/projects" -mindepth 1 -maxdepth 1 -type d | sort | fzf --reverse) || exit 0
      name=$(basename "$dir" | tr .: __)

      tmux has-session -t "=$name" 2>/dev/null || tmux new-session -ds "$name" -c "$dir"

      if [ -n "''${TMUX-}" ]; then
        tmux switch-client -t "=$name"
      else
        tmux attach-session -t "=$name"
      fi
    '';
  };

  keyhints = pkgs.writeShellApplication {
    name = "keyhints";
    runtimeInputs = with pkgs; [python3 tmux fzf];
    text = ''
      python3 ${pkgs.writeText "keyhints.py" ''
        import os
        import re
        import subprocess
        import tomllib

        def pretty(key):
            for a, b in (("Mod+", "Super+"), ("M-", "Alt+"), ("C-", "Ctrl+"), ("S-", "Shift+")):
                key = key.replace(a, b)
            return key

        with open(os.path.expanduser("~/.config/umbriel/config.toml"), "rb") as f:
            binds = tomllib.load(f).get("keybinds", {})
        for key, act in binds.items():
            if isinstance(act, dict):
                act = act.get("action", "")
            print(f"umbriel  {pretty(key):<30} {act}")

        out = subprocess.run(["tmux", "list-keys"], capture_output=True, text=True).stdout
        for line in out.splitlines():
            m = re.match(r"bind-key\s+(?:-r\s+)?-T\s+(root|prefix)\s+(\S+)\s+(.*)", line)
            if not m or re.match(r"(Mouse|Wheel|Double|Triple)", m[2]):
                continue
            key = pretty(m[2]) if m[1] == "root" else "Prefix " + pretty(m[2])
            print(f"tmux     {key:<30} {m[3].strip()}")
      ''} | fzf --reverse --no-sort --prompt "keys> " --header "Esc to close"
    '';
  };

  mkObsidianPlugin = pluginId: {
    repo,
    version,
    hashes,
  }:
    pkgs.runCommandLocal "obsidian-plugin-${pluginId}-${version}" {} (''
        mkdir -p "$out"
      ''
      + lib.concatStrings (lib.mapAttrsToList (file: hash: ''
          cp ${pkgs.fetchurl {
            url = "https://github.com/${repo}/releases/download/${version}/${file}";
            inherit hash;
          }} "$out/${file}"
        '')
        hashes));

  obsidianPlugins = lib.mapAttrs mkObsidianPlugin {
    obsidian-livesync = {
      repo = "vrtmrz/obsidian-livesync";
      version = "1.0.28";
      hashes = {
        "main.js" = "sha256-zR6F8WZLB1/WHRdWWNUEOQ+Nnx+VyebHyN8byw0V+m4=";
        "manifest.json" = "sha256-oSEnQ8RXtiXlhJEsuYS1nnVuqZTjllKhQup4Wc/lUIY=";
        "styles.css" = "sha256-S6AL70F+6Y2aYt2f67eS3GVVlJz8no4GlFCtaZqyufA=";
      };
    };
    tasknotes = {
      repo = "callumalpass/tasknotes";
      version = "4.12.5";
      hashes = {
        "main.js" = "sha256-f4K2u//l/0sDxrFYGqGT8SBM1ZcHAO+WQfCV4MJ3vE4=";
        "manifest.json" = "sha256-m+yYiTjGejvKIkJNlGaA4CsOodLDn9hgz8rvNcNyBI0=";
        "styles.css" = "sha256-ILc5tmv0VZYhBJ0dS4BovtgWJwoSdzHka7Yg/zFNWNg=";
      };
    };
  };

  obsidian-plugins = pkgs.writeShellApplication {
    name = "obsidian-plugins";

    runtimeInputs = with pkgs; [coreutils jq];

    text = ''
      vault="''${1:-$PWD}"

      if [ ! -d "$vault" ]; then
        echo "obsidian-plugins: no such vault: $vault" >&2
        exit 1
      fi

      plugins_file="$vault/.obsidian/community-plugins.json"

      install_plugin() {
        dir="$vault/.obsidian/plugins/$1"

        mkdir -p "$dir"
        cp --no-preserve=mode,ownership "$2"/* "$dir/"

        if [ -f "$plugins_file" ]; then
          jq --arg id "$1" 'if index($id) then . else . + [$id] end' \
            "$plugins_file" > "$plugins_file.tmp"
          mv "$plugins_file.tmp" "$plugins_file"
        else
          jq -n --arg id "$1" '[$id]' > "$plugins_file"
        fi

        echo "obsidian-plugins: $1 -> $dir"
      }

      mkdir -p "$vault/.obsidian/plugins"

      ${lib.concatStringsSep "\n" (lib.mapAttrsToList
        (pluginId: drv: ''install_plugin "${pluginId}" "${drv}"'')
        obsidianPlugins)}
    '';
  };
  qtctConf = dir: ''
    [Appearance]
    color_scheme_path=${config.xdg.configHome}/${dir}/colors/noctalia.conf
    custom_palette=true
    icon_theme=Papirus-Dark
    style=Fusion
  '';
in {
  imports = [inputs.t3-code-nix.homeModules.t3code];

  home.username = "lux";
  home.homeDirectory = "/home/lux";

  home.stateVersion = "25.11";

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };

  programs.home-manager.enable = true;

  services.udiskie = {
    enable = true;
    automount = true;
    tray = "never";
  };

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    syntaxHighlighting.enable = true;
    autocd = true;

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
      deploy-homelab = "nh os switch -H homelab --target-host homelab --build-host homelab";
      nx = "cd /etc/nixos";
    };

    initContent = lib.mkOrder 950 ''
      setopt no_case_glob
      setopt complete_in_word
      setopt auto_pushd
      setopt pushd_ignore_dups
      unsetopt beep

      stty -ixon

      bindkey '^[[1;5D' backward-word
      bindkey '^[[1;5C' forward-word
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

  programs.t3code = {
    enable = true;
    channel = "stable";
    packageVariant = "prebuilt";
  };

  programs.tmux = {
    enable = true;
    baseIndex = 1;
    keyMode = "vi";
    mouse = true;
    escapeTime = 0;
    historyLimit = 50000;

    plugins = with pkgs.tmuxPlugins; [
      {
        plugin = resurrect;
        extraConfig = ''
          set -g @resurrect-processes ':all:'
        '';
      }
      {
        plugin = continuum;
        extraConfig = ''
          set -g status-left-length 40
          set -g status-left "#[bg=#{@noctalia_primary},fg=#{@noctalia_on_primary},bold] #S #[default] "
          set -g status-right-length 80
          set -g status-right "#[fg=#{@noctalia_on_surface_variant}] #{=/-40/…:pane_current_path} #[bg=#{@noctalia_primary_container},fg=#{@noctalia_on_primary_container}] #H "
          set -g window-status-format " #I #W "
          set -g window-status-current-format " #I #W "
          set -g @continuum-restore 'on'
          set -g @continuum-save-interval '15'
        '';
      }
    ];

    extraConfig = ''
      set -g extended-keys always

      set-hook -g pane-mode-changed 'if -F "#{pane_in_mode}" "display-message \"-- COPY MODE (q/Escape to exit) --\"" "display-message \"-- copy mode exited --\""'

      unbind-key -a -T root

      bind -n MouseDown1Pane select-pane -t = \; send-keys -M
      bind -n MouseDrag1Pane select-pane -t = \; copy-mode -M
      bind -n MouseDrag1Border resize-pane -M
      bind -n WheelUpPane if -F "#{||:#{pane_in_mode},#{mouse_any_flag}}" "send -M" "copy-mode -e"
      bind -n S-PPage copy-mode -eu

      set -g pane-border-lines "double"

      set -g renumber-windows on

      bind f display-popup -E -w 60% -h 50% ${lib.getExe tmux-sessionizer}
      bind -n M-f display-popup -E -w 60% -h 50% ${lib.getExe tmux-sessionizer}
      bind g display-popup -E -w 90% -h 90% -d "#{pane_current_path}" lazygit

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

      bind -n 'M-S-<' swap-window -d -t -1
      bind -n 'M-S->' swap-window -d -t +1
      bind -n 'M-S-{' swap-pane -U
      bind -n 'M-S-}' swap-pane -D

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

      source-file -q "$HOME/.config/tmux/themes/noctalia.conf"
    '';
  };

  xdg.configFile."umbriel" = {
    source = config.lib.file.mkOutOfStoreSymlink "/etc/nixos/dotfiles/umbriel";
    force = true;
  };

  programs.foot = {
    enable = true;
    settings = {
      main = {
        font = "Iosevka NF:size=15";
        pad = "4x4";
        shell = "${pkgs.writeShellScript "foot-tmux" ''
          s=$(tmux list-sessions -F '#{session_attached} #{session_last_attached} #{session_name}' 2>/dev/null \
            | awk '$1 == 0' | sort -k2 -nr | head -n1 | cut -d' ' -f3-)
          [ -n "$s" ] && exec tmux attach -t "=$s"
          n=1
          while tmux has-session -t "=scratch-$n" 2>/dev/null; do n=$((n + 1)); done
          exec tmux new -s "scratch-$n"
        ''}";
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

  programs.obs-studio = {
    enable = true;
    plugins = with pkgs.obs-studio-plugins; [
      obs-backgroundremoval
    ];
  };

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

  home.pointerCursor = {
    enable = true;
    package = pkgs.bibata-cursors;
    name = "Bibata-Modern-Classic";
    size = 24;
    gtk.enable = true;
    x11.enable = true;
  };

  gtk = {
    enable = true;
    colorScheme = "dark";
    theme = {
      package = pkgs.adw-gtk3;
      name = "adw-gtk3-dark";
    };
    gtk4.theme = null;
    iconTheme = {
      package = pkgs.papirus-icon-theme;
      name = "Papirus-Dark";
    };
  };

  dconf.settings."org/gnome/desktop/interface" = {
    color-scheme = "prefer-dark";
    gtk-theme = "adw-gtk3-dark";
    icon-theme = "Papirus-Dark";
    cursor-theme = "Bibata-Modern-Classic";
    cursor-size = 24;
  };

  qt = {
    enable = true;
    platformTheme.name = "qtct";
  };

  xdg.configFile."qt5ct/qt5ct.conf".text = qtctConf "qt5ct";
  xdg.configFile."qt6ct/qt6ct.conf".text = qtctConf "qt6ct";

  xdg.mimeApps = let
    zed = "dev.zed.Zed.desktop";
    imv = "imv-dir.desktop";
    zathura = "org.pwmt.zathura-pdf-mupdf.desktop";
    office = "onlyoffice-desktopeditors.desktop";
    archive = "org.gnome.FileRoller.desktop";
    browser = "zen-beta.desktop";
    assoc = app: types: lib.genAttrs types (_: app);
  in {
    enable = true;
    defaultApplications =
      assoc zed [
        "text/plain"
        "text/markdown"
        "text/x-log"
        "text/x-python"
        "text/x-shellscript"
        "application/x-shellscript"
        "text/x-csrc"
        "text/x-chdr"
        "text/x-c++src"
        "text/x-c++hdr"
        "text/x-csharp"
        "text/x-go"
        "text/x-lua"
        "text/x-nix"
        "text/x-makefile"
        "text/css"
        "text/javascript"
        "application/javascript"
        "application/json"
        "application/x-yaml"
        "application/yaml"
        "application/toml"
        "application/xml"
        "text/xml"
        "application/sql"
        "text/x-patch"
        "text/x-diff"
        "text/x-dockerfile"
        "text/x-rust"
        "text/x-java"
        "text/x-typescript"
        "text/vnd.trolltech.linguist"
        "text/x-go-mod"
        "application/x-bat"
        "application/x-desktop"
      ]
      // assoc imv [
        "image/png"
        "image/jpeg"
        "image/gif"
        "image/webp"
        "image/svg+xml"
        "image/bmp"
        "image/tiff"
        "image/avif"
        "image/heic"
        "image/heif"
        "image/jxl"
        "image/x-icon"
        "image/vnd.microsoft.icon"
      ]
      // assoc "mpv.desktop" [
        "video/mp4"
        "video/x-matroska"
        "video/webm"
        "video/quicktime"
        "video/x-msvideo"
        "video/mpeg"
        "audio/mpeg"
        "audio/flac"
        "audio/ogg"
        "audio/wav"
        "audio/x-wav"
        "audio/mp4"
        "audio/opus"
        "audio/aac"
        "audio/x-opus+ogg"
        "audio/x-vorbis+ogg"
        "audio/x-flac+ogg"
        "audio/x-m4a"
        "audio/webm"
        "audio/x-matroska"
        "audio/x-flac"
        "audio/x-aiff"
        "audio/x-ms-wma"
        "video/ogg"
        "video/mp2t"
        "video/x-flv"
        "video/3gpp"
        "video/x-ms-wmv"
      ]
      // assoc zathura [
        "application/pdf"
        "application/epub+zip"
        "application/x-mobipocket-ebook"
        "application/x-fictionbook"
      ]
      // assoc "org.pwmt.zathura-djvu.desktop" ["image/vnd.djvu" "image/x-djvu"]
      // assoc "org.pwmt.zathura-ps.desktop" ["application/postscript"]
      // assoc "org.pwmt.zathura-cb.desktop" ["application/vnd.comicbook+zip" "application/vnd.comicbook-rar"]
      // assoc office [
        "text/csv"
        "application/rtf"
        "application/msword"
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        "application/vnd.oasis.opendocument.text"
        "application/vnd.ms-excel"
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        "application/vnd.oasis.opendocument.spreadsheet"
        "application/vnd.ms-powerpoint"
        "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        "application/vnd.oasis.opendocument.presentation"
      ]
      // assoc archive [
        "application/zip"
        "application/x-tar"
        "application/gzip"
        "application/x-compressed-tar"
        "application/x-7z-compressed"
        "application/vnd.rar"
        "application/x-rar"
        "application/x-xz"
        "application/x-xz-compressed-tar"
        "application/zstd"
        "application/x-zstd-compressed-tar"
        "application/x-bzip2"
        "application/x-bzip2-compressed-tar"
        "application/x-iso9660-image"
        "application/x-cd-image"
      ]
      // assoc "org.qbittorrent.qBittorrent.desktop" ["application/x-bittorrent" "x-scheme-handler/magnet"]
      // assoc "thunar.desktop" ["inode/directory"]
      // assoc "dbeaver.desktop" ["application/x-sqlite3" "application/vnd.sqlite3"]
      // assoc browser [
        "text/html"
        "application/xhtml+xml"
        "x-scheme-handler/http"
        "x-scheme-handler/https"
        "x-scheme-handler/chrome"
        "x-scheme-handler/mailto"
        "application/x-extension-htm"
        "application/x-extension-html"
        "application/x-extension-shtml"
        "application/x-extension-xhtml"
        "application/x-extension-xht"
      ]
      // {
        "x-scheme-handler/tg" = "org.telegram.desktop.desktop";
        "x-scheme-handler/tonsite" = "org.telegram.desktop.desktop";
        "x-scheme-handler/discord" = "vesktop.desktop";
        "x-scheme-handler/claude-cli" = "claude-code-url-handler.desktop";
        "application/vnd.microsoft.portable-executable" = "steam.desktop";
        "x-scheme-handler/pttp" = "CiscoPacketTracerPtsa-9.0.1.desktop";
        "application/x-pka" = "CiscoPacketTracer-9.0.1.desktop";
        "application/x-pkt" = "CiscoPacketTracer-9.0.1.desktop";
        "application/x-pkz" = "CiscoPacketTracer-9.0.1.desktop";
        "application/x-pksz" = "CiscoPacketTracer-9.0.1.desktop";
      };
  };
  xdg.configFile."mimeapps.list".force = true;

  xdg.configFile."nvim" = {
    source = config.lib.file.mkOutOfStoreSymlink "/etc/nixos/dotfiles/nvim";
    force = true;
  };

  xdg.dataFile."nvim/site/parser".source = "${nvimGrammars}/parser";
  xdg.dataFile."nvim/site/pack/nix/start/nvim-treesitter".source = pkgs.vimPlugins.nvim-treesitter;

  programs.git = {
    enable = true;
    settings = {
      user.name = "lux";
      user.email = "rakhmatullin.damir@tutamail.com";
      init.defaultBranch = "main";
      pull.rebase = true;
    };
  };

  programs.lazygit = {
    enable = true;
    settings = {
      gui.nerdFontsVersion = "3";
      os.editPreset = "nvim-remote";
    };
  };

  home.packages = lib.mkBefore (with pkgs; let
    system = pkgs.stdenv.hostPlatform.system;

    apps = [
      chromium
      inputs.zen-browser.packages.${system}.default
      telegram-desktop
      vesktop
      obsidian
      obsidian-plugins
      onlyoffice-desktopeditors
      keepassxc
      bitwarden-cli
      super-productivity
      localsend
      qbittorrent
      mpv
      imv
      thunar
      file-roller
      zed-editor
      dbeaver-bin
      (writeTextDir "share/mime/packages/go-mod.xml" ''
        <?xml version="1.0" encoding="UTF-8"?>
        <mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
          <mime-type type="text/x-go-mod">
            <comment>Go module file</comment>
            <sub-class-of type="text/plain"/>
            <glob pattern="go.mod"/>
            <glob pattern="go.sum"/>
            <glob pattern="go.work"/>
          </mime-type>
        </mime-info>
      '')
    ];

    games = [
      protonup-qt
      inputs.elyprismlauncher.packages.${system}.default
      (import inputs.creamlinux-installer {inherit pkgs;})
    ];

    cli = [
      ripgrep
      fd
      bat
      eza
      jq
      btop
      dust
      nitch
      wget
      zip
      unzip
      openssl
      exiftool
      ffmpeg
      imagemagick
      yt-dlp
      wl-clipboard
      grim
      slurp
      tmux-sessionizer
      keyhints
      wtype
      inputs.clin.packages.${system}.default
      inputs.anicli-ru.packages.${system}.default
    ];

    network = [
      dnsutils
      mtr
      tcpdump
      traceroute
    ];

    dev = [
      go
      gopls
      goimports
      nodejs_22
      (python3.withPackages (ps: with ps; [numpy onnxruntime pillow]))
      gcc
      gh
      nil
      alejandra
      stylua
      lua-language-server
      vscode-langservers-extracted
      yaml-language-server
    ];

    theming = [
      adwaita-icon-theme
      gnome-themes-extra
    ];
  in
    apps ++ games ++ cli ++ network ++ dev ++ theming);
}
