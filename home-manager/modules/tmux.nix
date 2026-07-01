{pkgs, ...}: {
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
      resurrect
      {
        plugin = continuum;
        extraConfig = ''
          set -g @continuum-restore 'on'
          set -g @continuum-save-interval '15'
        '';
      }
    ];

    extraConfig = ''
      unbind-key -a -T root

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
}
