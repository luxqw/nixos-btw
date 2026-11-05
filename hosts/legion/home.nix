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
      c
      diff
      go
      gomod
      gosum
      gowork
      html
      javascript
      json
      lua
      luadoc
      luap
      markdown
      markdown_inline
      nix
      printf
      python
      query
      regex
      toml
      vim
      vimdoc
      xml
      yaml
    ];
  };

  goimports = pkgs.runCommandLocal "goimports-${pkgs.gotools.version}" {} ''
    install -Dm755 ${pkgs.gotools}/bin/.goimports-wrapped $out/bin/goimports
  '';

  # Zellij fixes its theme per server, so a session started in Hyprland has
  # Caelestia's colours and keeps them when attached later from another session.
  zellijTheme = ''
    theme=()
    theme_dir=''${XDG_STATE_HOME:-$HOME/.local/state}/session-theme/zellij
    if [ "''${XDG_CURRENT_DESKTOP-}" = Hyprland ] && [ -e "$theme_dir/caelestia-ui.kdl" ]; then
      theme=(options --theme caelestia-ui --theme-dir "$theme_dir")
    fi
  '';

  zellij-pick = pkgs.writeShellApplication {
    name = "zellij-pick";
    runtimeInputs = with pkgs; [zellij fzf zoxide findutils coreutils gawk];
    text = ''
      ${zellijTheme}
      out=$(
        {
          zellij ls -s 2>/dev/null | sed 's/^/@/'
          find "$HOME/Documents/projects" -mindepth 1 -maxdepth 1 -type d | sort
          zoxide query -l
        } | awk '!seen[$0]++' \
          | fzf --reverse --print-query --prompt "session> " \
              --header "@ = session · dir = project session · type a new name + Enter"
      ) || [ -n "$out" ] || exit 0

      query=$(sed -n 1p <<<"$out")
      pick=$(sed -n 2p <<<"$out")
      pick=''${pick:-$query}
      [ -n "$pick" ] || exit 0

      if [[ $pick == @* ]]; then
        name=''${pick#@}
        dir=$HOME
      elif [ -d "$pick" ]; then
        name=$(basename "$pick" | tr .: __)
        dir=$pick
      else
        name=$pick
        dir=$HOME
      fi

      if [ -n "''${ZELLIJ-}" ]; then
        zellij ls -s 2>/dev/null | grep -qxF "$name" || (cd "$dir" && zellij attach -b "$name" "''${theme[@]}")
        zellij action switch-session "$name"
      else
        cd "$dir" && exec zellij attach -c "$name" "''${theme[@]}"
      fi
    '';
  };

  zellij-scratch = pkgs.writeShellApplication {
    name = "zellij-scratch";
    runtimeInputs = with pkgs; [zellij gnugrep gawk coreutils findutils];
    text = ''
      ${zellijTheme}
      # Keep the 3 last closed windows to resurrect; the rest free their numbers.
      # zellij drops session-metadata.kdl on close, so dir mtime is the close time.
      info=''${XDG_CACHE_HOME:-$HOME/.cache}/zellij/contract_version_1/session_info
      zellij ls -n 2>/dev/null \
        | awk '/EXITED/ && $1 ~ /^s-[0-9]+$/ {print $1}' \
        | (cd "$info" && xargs -r ls -dt -- 2>/dev/null) \
        | tail -n +4 \
        | while read -r s; do zellij delete-session "$s" >/dev/null 2>&1; done || true

      n=1
      while zellij ls -s 2>/dev/null | grep -qxF "s-$n"; do n=$((n + 1)); done
      exec zellij attach -c "s-$n" "''${theme[@]}"
    '';
  };

  # Colours follow the session: Noctalia's in Umbriel and niri, Caelestia's in
  # Hyprland. foot, qt5ct/qt6ct, gtk and nvim read theirs through links in
  # ~/.local/state/session-theme/, and this points the links at one source or
  # the other (the zellij scripts pick their theme by XDG_CURRENT_DESKTOP). Run
  # at session start (below), by Caelestia after each colour change
  # (dotfiles/caelestia/cli.json postHook), and with --seed at activation, which
  # only creates the links that are missing, so every include resolves.
  session-theme = pkgs.writeShellApplication {
    name = "session-theme";
    runtimeInputs = with pkgs; [coreutils hyprland];
    text = ''
      state=''${XDG_STATE_HOME:-$HOME/.local/state}
      config=''${XDG_CONFIG_HOME:-$HOME/.config}
      dir=$state/session-theme
      caelestia=$state/caelestia/theme

      seed=false
      if [ "''${1-}" = --seed ]; then
        seed=true
      fi
      hyprland=false
      if [ "$seed" = false ] && [ "''${XDG_CURRENT_DESKTOP-}" = Hyprland ]; then
        hyprland=true
      fi

      mkdir -p "$dir/zellij"
      [ -e "$dir/empty" ] || : > "$dir/empty"

      link() {
        if [ "$seed" = true ] && [ -L "$dir/$1" ]; then
          return
        fi
        ln -sfn "$2" "$dir/$1.new"
        mv -T "$dir/$1.new" "$dir/$1"
      }

      # Caelestia's output in Hyprland once it has written it, else the fallback.
      pick() {
        if [ "$hyprland" = true ] && [ -e "$caelestia/$2" ]; then
          link "$1" "$caelestia/$2"
        else
          link "$1" "$3"
        fi
      }

      pick foot.ini foot.ini "$dir/empty"
      pick qtct.conf qtct.conf "$config/qt6ct/colors/noctalia.conf"
      pick gtk3.css gtk3.css "$dir/empty"
      pick gtk4.css gtk4.css "$dir/empty"
      link zellij/caelestia-ui.kdl "$caelestia/caelestia-ui.kdl"
      if [ "$hyprland" = true ] && [ -e "$caelestia/nvim.lua" ]; then
        link nvim.lua "$caelestia/nvim.lua"
      elif [ "$seed" = false ]; then
        rm -f "$dir/nvim.lua"
      fi

      # Caelestia just changed colours: repaint Hyprland's borders and shadow.
      if [ "$hyprland" = true ] && [ -n "''${SCHEME_NAME-}" ] && [ -n "''${HYPRLAND_INSTANCE_SIGNATURE-}" ]; then
        hyprctl eval 'require("hyprland.theme").apply()' > /dev/null || true
      fi
    '';
  };

  # A switch failure does not identify the failed stage; leave recovery manual.
  mkDeploy = name: elevation:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [pkgs.nh];
      text = ''
        flags=(-H homelab --target-host homelab --build-host homelab${elevation})
        status=0
        nh os switch "''${flags[@]}" "$@" || status=$?
        if [ "$status" -eq 0 ]; then
          exit 0
        fi
        echo "warning: switch failed (exit $status); no boot recovery was attempted" >&2
        echo "Only after inspecting an actual activation failure, register the generation manually with:" >&2
        printf ' %q' nh os boot "''${flags[@]}" "$@" >&2
        printf '\n' >&2
        exit "$status"
      '';
    };

  deploy-homelab = mkDeploy "deploy-homelab" " -e passwordless";
  deploy-homelab-pw = mkDeploy "deploy-homelab-pw" "";

  torrent-add = pkgs.writeShellApplication {
    name = "torrent-add";
    runtimeInputs = with pkgs; [openssh libnotify];
    text = ''
      send() {
        case $1 in
          magnet:*) printf '%s' "$1" | ssh homelab 'curl -sf --data-urlencode urls@- http://127.0.0.1:8080/api/v2/torrents/add' ;;
          *) ssh homelab 'curl -sf -F "torrents=@-;filename=upload.torrent" http://127.0.0.1:8080/api/v2/torrents/add' <"$1" ;;
        esac >/dev/null
      }

      for arg in "$@"; do
        if send "$arg"; then
          notify-send -a torrent "Sent to homelab" "''${arg:0:80}"
        else
          notify-send -a torrent -u critical "homelab rejected the torrent" "''${arg:0:80}"
        fi
      done
    '';
  };

  keyhints = pkgs.writeShellApplication {
    name = "keyhints";
    runtimeInputs = with pkgs; [python3 fzf];
    text = ''
      python3 "''${XDG_CONFIG_HOME:-$HOME/.config}/keyhints/keyhints.py" \
        | fzf --ansi --reverse --no-sort --nth=2.. --prompt "keys> " \
            --header "★ first · type an app (nvim, yazi, zellij, skills…) to filter · Esc closes"
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
  # User units of the Hyprland session (home.nix below): they belong to
  # hyprland-session.target, not to graphical-session.target, which Umbriel
  # and niri reach too. Logging out from Caelestia's power menu or a crash skips
  # the shutdown hook, and lingering keeps the target active, so the units
  # would restart-loop into the next session. The ExecCondition asks the
  # compositor over its IPC socket (a stale socket file refuses the connection):
  # a failed condition skips the start quietly and stops the loop, and it only
  # runs when a unit starts, never in a live session.
  hyprlandSession = description: service: {
    Unit = {
      Description = description;
      PartOf = ["hyprland-session.target"];
      After = ["graphical-session.target"];
    };
    Service =
      {
        Restart = "on-failure";
        ExecCondition = "${pkgs.hyprland}/bin/hyprctl version";
      }
      // service;
    Install.WantedBy = ["hyprland-session.target"];
  };

  clipboardWatcher = type:
    hyprlandSession "Store ${type} clipboard history" {
      ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --type ${type} --watch ${lib.getExe pkgs.cliphist} store";
    };

  gtkCss = dir: file: ''
    @import url("file://${config.xdg.configHome}/${dir}/noctalia.css");
    @import url("file://${config.home.homeDirectory}/.local/state/session-theme/${file}");
  '';

  # The colours come through session-theme (Noctalia's or Caelestia's).
  qtctConf = ''
    [Appearance]
    color_scheme_path=${config.home.homeDirectory}/.local/state/session-theme/qtct.conf
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
      update = "nh os build --update --diff always";
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

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.t3code = {
    enable = true;
    # The AppImage runs in bwrap with only a fixed list of /etc mounted, so
    # projects under /etc/nixos need their own bind.
    package = inputs.t3-code-nix.packages.${pkgs.stdenv.hostPlatform.system}.t3code.override {
      appimageTools =
        pkgs.appimageTools
        // {
          wrapType2 = args:
            pkgs.appimageTools.wrapType2 (args // {extraBwrapArgs = ["--bind /etc/nixos /etc/nixos"];});
        };
    };
  };

  # The package copies only usr/share out of the AppImage, and its .desktop
  # sits at the root, so the launcher never sees T3 Code without this.
  xdg.desktopEntries.t3code = {
    name = "T3 Code";
    exec = "t3code %U";
    icon = "t3code";
    comment = "Desktop app for coding agents";
    categories = ["Development"];
    mimeType = ["x-scheme-handler/t3code"];
    settings.StartupWMClass = "t3code";
  };

  xdg.configFile."keyhints" = {
    source = config.lib.file.mkOutOfStoreSymlink "/etc/nixos/dotfiles/keyhints";
    force = true;
  };

  xdg.configFile."zellij/config.kdl" = {
    source = config.lib.file.mkOutOfStoreSymlink "/etc/nixos/dotfiles/zellij/config.kdl";
    force = true;
  };

  xdg.configFile."umbriel" = {
    source = config.lib.file.mkOutOfStoreSymlink "/etc/nixos/dotfiles/umbriel";
    force = true;
  };

  # The niri session (beside Umbriel). DMS writes its dms/*.kdl includes in
  # this directory (gitignored there).
  xdg.configFile."niri" = {
    source = config.lib.file.mkOutOfStoreSymlink "/etc/nixos/dotfiles/niri";
    force = true;
  };

  # The Hyprland session (beside Umbriel and niri), with the Caelestia shell.
  # Not Home Manager's wayland.windowManager.hyprland: it would write its own
  # hyprland.lua into this directory. Caelestia writes hypr/scheme/ here.
  xdg.configFile."hypr" = {
    source = config.lib.file.mkOutOfStoreSymlink "/etc/nixos/dotfiles/hypr";
    force = true;
  };

  # The shell saves shell.json from its settings UI, so this is writable too.
  xdg.configFile."caelestia" = {
    source = config.lib.file.mkOutOfStoreSymlink "/etc/nixos/dotfiles/caelestia";
    force = true;
  };

  # One rules file for Claude and Codex; the ~/.agents repo is its source.
  home.file = lib.genAttrs [".claude/CLAUDE.md" ".codex/AGENTS.md"] (_: {
    source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.agents/CLAUDE.md";
    force = true;
  });

  # Umbriel has no hotplug hooks, but takes wlr-output-management: with any
  # external monitor plugged in, the laptop panel drops to 60 Hz so the
  # compositor drives one 165 Hz screen instead of two.
  services.kanshi = {
    enable = true;
    settings = [
      {
        profile.name = "docked";
        profile.outputs = [
          {
            criteria = "eDP-1";
            mode = "2560x1600@60.002Hz";
          }
          {criteria = "*";}
        ];
      }
      {
        profile.name = "laptop";
        profile.outputs = [
          {
            criteria = "eDP-1";
            mode = "2560x1600@165.004Hz";
          }
        ];
      }
    ];
  };

  programs.foot = {
    enable = true;
    settings = {
      main = {
        font = "Iosevka NF:size=15";
        pad = "4x4";
        shell = lib.getExe zellij-scratch;
        # Noctalia's theme, then the session's (empty outside Hyprland): the
        # later include wins. Keep the noctalia include: without it Noctalia's
        # apply script rewrites foot.ini.
        include = [
          "${config.home.homeDirectory}/.config/foot/themes/noctalia"
          "${config.home.homeDirectory}/.local/state/session-theme/foot.ini"
        ];
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

  xdg.configFile."voxtype/config.toml".source = (pkgs.formats.toml {}).generate "voxtype.toml" {
    state_file = "auto";
    hotkey = {
      enabled = true;
      key = "RIGHTCTRL";
      mode = "push_to_talk";
    };
    audio = {
      device = "default";
      max_duration_secs = 120;
      pause_media = true;
    };
    whisper = {
      model = "${pkgs.fetchurl {
        url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin";
        hash = "sha256-H8cPd0046xaZk6w5Huo1fvR8iHV+9y7llDh5t+jivGk=";
      }}";
      language = ["ru" "en"];
      translate = false;
      # Whisper copies the prompt's style; without it, it sometimes writes
      # lowercase with no punctuation. A Russian-only prompt turns English into Russian.
      initial_prompt = "Привет! Короче, посмотри конфиг NixOS и логи. Please check the repository, then tell me what happened.";
      gpu_isolation = true;
    };
    output = {
      # wtype drops Cyrillic keystrokes in Electron; paste is lossless.
      # ctrl+shift+v pastes in foot and as plain text in Chromium.
      mode = "paste";
      paste_keys = "ctrl+shift+v";
      restore_clipboard = true;
      fallback_to_clipboard = true;
      append_text = " ";
      # Noctalia plays a sound on every notification.
      notification.on_transcription = false;
    };
  };

  systemd.user.services.voxtype = {
    Unit = {
      Description = "Voxtype push-to-talk dictation";
      PartOf = ["graphical-session.target"];
      After = ["graphical-session.target" "pipewire.service"];
      X-Restart-Triggers = ["${config.xdg.configFile."voxtype/config.toml".source}"];
    };
    Service = {
      ExecStart = "${lib.getExe pkgs.voxtype-vulkan} -q daemon";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = ["graphical-session.target"];
  };

  # The Hyprland session. Hyprland 0.56 starts no session target, so
  # dotfiles/hypr/hyprland/execs.lua starts this one, as Home Manager's would.
  systemd.user.targets.hyprland-session.Unit = {
    Description = "Hyprland compositor session";
    Documentation = ["man:systemd.special(7)"];
    BindsTo = ["graphical-session.target"];
    Wants = ["graphical-session-pre.target"];
    After = ["graphical-session-pre.target"];
    PropagatesStopTo = ["graphical-session.target"];
  };

  # Which colours the app themes use, by session (see session-theme above).
  systemd.user.services.session-theme = {
    Unit = {
      Description = "Point the app themes at this session's colours";
      After = ["graphical-session-pre.target"];
      Before = ["graphical-session.target" "xdg-desktop-autostart.target"];
    };
    Service = {
      Type = "oneshot";
      ExecStart = lib.getExe session-theme;
    };
    Install.WantedBy = ["graphical-session.target"];
  };

  # Locking is hyprlock's (configuration.nix, U2F); Caelestia's own lock and
  # idle timeouts are off (dotfiles/caelestia/shell.json).
  systemd.user.services.caelestia = hyprlandSession "Caelestia shell" {
    Type = "exec";
    ExecStart = lib.getExe pkgs.caelestia-shell;
    # caelestia-cli's random wallpaper reads this, not shell.json's paths.
    Environment = ["QT_QPA_PLATFORM=wayland" "CAELESTIA_WALLPAPERS_DIR=${config.home.homeDirectory}/Documents/walls"];
    RestartSec = 2;
  };

  systemd.user.services.hyprpolkitagent = hyprlandSession "Hyprland polkit agent" {
    ExecStart = "${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent";
  };

  systemd.user.services.cliphist-text = clipboardWatcher "text";
  systemd.user.services.cliphist-image = clipboardWatcher "image";

  # Locks after 5 minutes and before sleep, with hyprlock.
  systemd.user.services.hypridle = hyprlandSession "Idle lock for the Hyprland session" {
    ExecStart = "${lib.getExe pkgs.hypridle} -c ${config.xdg.configHome}/hypr/hypridle.conf";
  };

  # Seed the session-theme links (which default to Noctalia's) so that foot,
  # qt and gtk includes resolve before the first session starts.
  home.activation.seedSessionTheme = lib.hm.dag.entryAfter ["writeBoundary"] ''
    run ${lib.getExe session-theme} --seed
  '';

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
            run = ''nvim %s'';
            block = true;
            desc = "Edit in nvim";
          }
        ];
        image = [
          {
            run = ''imv %s'';
            orphan = true;
            desc = "Open image in imv";
          }
        ];
        pdf = [
          {
            run = ''zathura %s'';
            orphan = true;
            desc = "Open PDF in zathura";
          }
        ];
        torrent = [
          {
            run = ''torrent-add %s'';
            orphan = true;
            desc = "Send to homelab qBittorrent";
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
    # Noctalia's colours (it writes noctalia.css), then the session's, which
    # are Caelestia's in Hyprland and empty elsewhere. Keep noctalia.css and
    # @import here: Noctalia's gtk apply script then leaves this file alone.
    gtk3.extraCss = gtkCss "gtk-3.0" "gtk3.css";
    gtk4.extraCss = gtkCss "gtk-4.0" "gtk4.css";
  };
  # A plain file with `@import url("noctalia.css");` exists today.
  xdg.configFile."gtk-3.0/gtk.css".force = true;
  xdg.configFile."gtk-4.0/gtk.css".force = true;

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

  # force: DMS's icon theme setting and its "apply Qt" button replace these
  # symlinks with files, which would otherwise block the next activation.
  xdg.configFile."qt5ct/qt5ct.conf" = {
    text = qtctConf;
    force = true;
  };
  xdg.configFile."qt6ct/qt6ct.conf" = {
    text = qtctConf;
    force = true;
  };

  # DMS's lock screen authenticates against PAM `login`, which takes the
  # YubiKey (hosts/legion/configuration.nix), instead of generating its own
  # password-only service. A config.d partial rather than a settings.json, so
  # the Settings UI keeps writing everything else; DMS only rewrites a partial
  # whose keys change, and merges it over settings.json.
  xdg.configFile."dms/config.d/lock.json".text = builtins.toJSON {
    lockPamExternallyManaged = true;
  };

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
      // assoc "torrent-add.desktop" ["application/x-bittorrent" "x-scheme-handler/magnet"]
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
        "x-scheme-handler/discord" = "discord.desktop";
        "x-scheme-handler/claude-cli" = "claude-code-url-handler.desktop";
        "application/vnd.microsoft.portable-executable" = "steam.desktop";
      };
  };
  xdg.configFile."mimeapps.list".force = true;

  xdg.desktopEntries.torrent-add = {
    name = "Send to homelab qBittorrent";
    exec = "torrent-add %U";
    mimeType = ["application/x-bittorrent" "x-scheme-handler/magnet"];
    noDisplay = true;
  };

  xdg.configFile."nvim" = {
    source = config.lib.file.mkOutOfStoreSymlink "/etc/nixos/dotfiles/nvim";
    force = true;
  };

  xdg.dataFile."nvim/site/parser".source = "${nvimGrammars}/parser";
  xdg.dataFile."nvim/nix/nvim-treesitter".source = pkgs.vimPlugins.nvim-treesitter;

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
      git.diffRenderers = [
        {command = "delta --{{colorScheme}} --paging=never";}
      ];
    };
  };

  home.packages = lib.mkBefore (with pkgs; let
    system = pkgs.stdenv.hostPlatform.system;

    apps = [
      chromium
      inputs.zen-browser.packages.${system}.default
      telegram-desktop
      discord
      obsidian
      obsidian-plugins
      onlyoffice-desktopeditors
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
      shellcheck
      shfmt
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
      zellij
      zellij-pick
      zellij-scratch
      session-theme
      torrent-add
      deploy-homelab
      deploy-homelab-pw
      tealdeer
      delta
      restic
      yubikey-manager
      keyhints
      wtype
      inputs.clin.packages.${system}.default
      # The Hyprland session's binds call `caelestia clipboard`, and the shell
      # starts from its user unit.
      caelestia-cli
      caelestia-shell
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
      gcc
      gh
      alejandra
      stylua
      lua-language-server
      marksman
      markdownlint-cli2
      gofumpt
      golangci-lint
      statix
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
