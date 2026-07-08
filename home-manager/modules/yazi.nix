{pkgs, ...}: {
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
          on = ["c" "m"];
          run = "plugin chmod";
          desc = "Chmod on selected files";
        }
        {
          on = ["c" "a"];
          run = "plugin compress";
          desc = "Compress selected files";
        }
        {
          on = ["c" "d"];
          run = "shell 'ya emit cd \"$(zoxide query -i)\"' --block --confirm";
          desc = "cd via zoxide";
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
}
